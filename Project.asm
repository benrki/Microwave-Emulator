.include "m2560def.inc"

.equ PORTLDIR = 0xF0 ; PD7-4: output, PD3-0, input
.equ INITCOLMASK = 0xEF ; scan from the rightmost column,
.equ INITROWMASK = 0x01 ; scan from the top row
.equ ROWMASK = 0x0F ; for obtaining input from Port D
.equ ENTRY_MODE = 0
.equ RUNNING_MODE  = 1
.equ PAUSED_MODE  = 2
.equ FINISHED_MODE  = 3
.equ SECOND = 7812 ; 10**6 / 128
.equ LCD_RS = 7
.equ LCD_E = 6
.equ LCD_RW = 5
.equ LCD_BE = 4

.equ F_CPU = 16000000
.equ DELAY_1MS = F_CPU / 4 / 1000 - 4

.def row = r16; current row number
.def col = r17; current column number
.def temp1 = r18
.def temp2 = r19
.def temp3 = r20
.def temp4 = r21
.def timerM = r22 
.def timerS = r23
.def counter = r24

.macro do_lcd_command
	ldi r16, @0
	rcall lcd_command
	rcall lcd_wait
.endmacro

.macro do_lcd_data
	mov r16, @0
	rcall lcd_data
	rcall lcd_wait
.endmacro

.macro lcd_set
	sbi PORTA, @0
.endmacro
.macro lcd_clr
	cbi PORTA, @0
.endmacro

; Macro for clearing a word (@0) in memory
.macro clear
	ldi YL, low(@0)
	ldi YH, high(@0)
	clr r16
	st Y+, r16
	st Y, r16
.endmacro

.dseg
mode: .byte 1 ; for storing the current mode
timeCounter: .byte 2 ; Two bytes to check if 1 second has passed
takeInput: .byte 1 ; Ability to take input (for debouncing)
inputTime: .byte 2	;for storing the time of input

.cseg
.org 0
	jmp RESET

.org OVF0addr
	jmp Timer0


RESET: 
	ldi  temp1, low(RAMEND)  ; initialize the stack
	out  SPL, temp1 
	ldi  temp1, high(RAMEND) 
	out  SPH, temp1 
	;initialise keyboard
	ldi  temp1, PORTLDIR  ; PL7:4/PA3:0, out/in 
	sts  DDRL, temp1 

	;initialise LCD
	ser temp1
	sts DDRk, temp1
	out DDRA, temp1
	clr temp1
	sts PORTk, temp1
	out PORTA, temp1

	do_lcd_command 0b00111000 ; 2x5x7
	rcall sleep_5ms
	do_lcd_command 0b00111000 ; 2x5x7
	rcall sleep_1ms
	do_lcd_command 0b00111000 ; 2x5x7
	do_lcd_command 0b00111000 ; 2x5x7
	do_lcd_command 0b00001000 ; display off?
	do_lcd_command 0b00000001 ; clear display
	do_lcd_command 0b00000110 ; increment, no display shift
	do_lcd_command 0b00001110 ; Cursor on, bar, no blink


	;initialise timer
	ldi temp1,0b00000000
	out TCCR0A, temp1
	ldi temp1, 0b00000010
	out TCCR0B, temp1 ;Prescaling value = 8
	ldi temp1, 1<<TOIE0 ;=128 ms
	sts TIMSK0,temp1		;R/C0 interrupt enable
	sei

	ldi timerM, 0
	ldi timerS, 0
	
	; Display 00:00
	rcall display_time

	;clear up the data string
	clear inputTime
	clear mode

	;clear register for entry
	clr counter
	clr r30
	clr r29

	; Jump straight to entry mode
	jmp set_entry_mode

;end of the RESET

;
; Send a command to the LCD (r16)
;

lcd_command:
	sts PORTk, r16
	rcall sleep_1ms
	lcd_set LCD_E
	rcall sleep_1ms
	lcd_clr LCD_E
	rcall sleep_1ms
	ret

lcd_data:
	sts PORTk, r16
	lcd_set LCD_RS
	rcall sleep_1ms
	lcd_set LCD_E
	rcall sleep_1ms
	lcd_clr LCD_E
	rcall sleep_1ms
	lcd_clr LCD_RS
	ret

lcd_wait:
	push r16
	clr r16
	sts DDRk, r16
	sts PORTk, r16
	lcd_set LCD_RW
lcd_wait_loop:
	rcall sleep_1ms
	lcd_set LCD_E
	rcall sleep_1ms
	lds r16, PINk
	lcd_clr LCD_E
	sbrc r16, 7
	rjmp lcd_wait_loop
	lcd_clr LCD_RW
	ser r16
	sts DDRk, r16
	pop r16
	ret


; 4 cycles per iteration - setup/call-return overhead
sleep_1ms:
	push r24
	push r25
	ldi r25, high(DELAY_1MS)
	ldi r24, low(DELAY_1MS)
delayloop_1ms:
	sbiw r25:r24, 1
	brne delayloop_1ms
	pop r25
	pop r24
	ret

sleep_5ms:
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	rcall sleep_1ms
	ret

;End LCD function

; Interrupts
Timer0:	
	;in temp1, SREG
	push temp1
	push temp2
	push r24
	push r25

	lds r24, timeCounter
	lds r25, timeCounter + 1
	adiw r25:r24, 1 ; inc timeCounter by 1
	sts timeCounter, r24
	sts timeCounter + 1, r25

	cpi r24, low(SECOND)
	ldi temp1, high(SECOND)
	cpc r25, temp1
	brne NotSecond

	; Second has passed
	; clear timeCounter
	clr r24
	clr r25
	sts timeCounter, r24
	sts timeCounter + 1, r25

	lds temp1, mode

	; If running mode then decrement the timer(s)
	cpi temp1, RUNNING_MODE
	breq dec_timer
	rjmp end_timer0

; Dec time
dec_timer:
	cpi timerS, 0
	breq dec_min
	dec timerS
	rcall display_time
	rjmp end_timer0

dec_min:
	cpi timerM, 0
	breq finished_timer

	; Else: take a min
	dec timerM
	ldi timerS, 59
	rcall display_time
	rjmp end_timer0

finished_timer:
	; If no input then add 60 and return
	cpi counter, 0
	breq add_60
	; TODO timer finished
	rjmp end_timer0

add_60:
	ldi timerS, 60
	rcall display_time
	rjmp end_timer0

NotSecond: ; Store in temporary counter
	sts timeCounter, r24
	sts timeCounter + 1, r25
	rjmp end_timer0

end_timer0:
	pop r25
	pop r24
	pop temp2
	pop temp1
	;out SREG,temp1

	reti

; End interrupts

; Helper functions

display_time:
	push timerM
	push timerS
	push temp1

	; Clear display
	do_lcd_command 0b00000001
	clr temp1
	rjmp display_min

display_min:
	cpi timerM, 10
	brge divide_min

	; Display first digit
	subi temp1, -'0'
	do_lcd_data temp1
	; Display second digit timerM
	subi timerM, -'0'
	do_lcd_data timerM
	; Display ';' separator
	ldi temp1, ':'
	do_lcd_data temp1
	
	; Finished displaying minutes, display seconds
	clr temp1
	rjmp display_sec
divide_min:
	inc temp1
	subi timerM, 10
	rjmp display_min

display_sec:
	cpi timerS, 10
	brge divide_sec

	; Display first digit
	subi temp1, -'0'
	do_lcd_data temp1
	; Display second digit timerM
	subi timerS, -'0'
	do_lcd_data timerS

	; Finished displaying
	pop temp1
	pop timerS
	pop timerM	
	ret

divide_sec:
	inc temp1
	subi timerS, 10
	rjmp display_sec

; End helper functions

; Start microwave lifecycle modes

; Start entry mode
set_entry_mode:
	ldi temp1, ENTRY_MODE
	sts mode, temp1
	clr counter
	jmp input_loop

input_loop:
	ldi  temp4, INITCOLMASK  ; initial column mask (temp4 = cmask)
	ldi  col, 0      ; initial column 
	rjmp colloop

colloop: 
	cpi  col, 4 
	breq  input_loop      ; If all keys are scanned, repeat. 
	sts  PORTL, temp4    ; Otherwise, scan a column. 

	ldi   temp1, 0xFF    ; Slow down the scan operation. 
	rjmp delay

delay:
	dec   temp1 
	brne   delay 

	lds  temp1, PINL    ; Read PORTL 
	andi  temp1, ROWMASK    ; Get the keypad output value 
	cpi   temp1, 0xF    ; Check if any row is low 
	breq   nextcol 
	      ; If yes, find which row is low 
	ldi   temp3, INITROWMASK  ; Initialize for row check (temp3 = rmask)
	clr  row      ; 
	rjmp rowloop

rowloop: 
	cpi   row, 4       
	breq   nextcol     ; the row scan is over. 
	mov   temp2, temp1     
	and   temp2, temp3    ; check un-masked bit 
	breq  convert       ; if bit is clear, the key is press
	inc   row      ; else move to the next row 
	lsl   temp3       
	jmp   rowloop 

nextcol:          ; if row scan is over 
	lsl temp4        
	inc col       ; increase column value 
	jmp colloop      ; go to the next column 

; TODO: verify this
convert:
	cp r30, row	
	brne press

	cp r29, col
	brne press
 
 	jmp goback

goback:
	ldi temp3,60
	rcall sleepL
	jmp press

press:	
	mov r30, row ;prev row
	mov r29, col ;prev col

	cpi   col, 3    ; If the pressed key is in col.3 
	breq   letters    ; we have a letter 
						; If the key is not in col.3 and  					   
	cpi   row, 3    ; If the key is in row3,  
	breq   jmp_symbols    ; we have a symbol or 0

	mov temp3, row  ; Otherwise we have a number in 1-9 
	lsl  temp3 
	add  temp3, row 
	add  temp3, col  ; temp1 = row*3 + col+1
	inc temp3
	
	jmp convert_end

jmp_symbols:
	jmp symbols

letters: 
	;convert numbers seen on LCD to full number
	;check the row is zero to make sure it is A
	;once is A then clear next and add the numbe up
	;ldi temp3, 'A' 
	;add temp3, row    ; Get the ASCII value for the key
	cpi row, 0
	breq letter_A
	cpi row, 1
	breq letter_B
	cpi row, 2
	breq letter_C
	cpi row, 3
	breq letter_D
	jmp convert_end

letter_A:
	ldi temp3, 'A'
	jmp convert_end

letter_B:
	ldi temp3, 'B'
	jmp convert_end	

letter_C:
	lds temp2,mode
	cpi temp2, RUNNING_MODE
	breq add_30sec
	jmp input_loop	


letter_D:
	lds temp2,mode
	cpi temp2, RUNNING_MODE
	breq sub_30sec
	jmp input_loop	

add_30sec:
	ldi counter, 5
	cpi timerS, 30		;check timerS less than 30 or not
	brlt directly_add	;if it is then add 30 directly
	ldi temp2, 60		;if it is not, timerS = 30-(60-timerS) and timerM + 1
	sub	temp2, timerS
	ldi temp4, 30
	sub temp4, temp2
	clr timerS
	mov timerS, temp4
	inc timerM
	jmp convert_end

directly_add:
	ldi temp2, 30
	add timerS, temp2
	jmp convert_end

sub_30sec:
	ldi counter, 5
	cpi timerM,0	;check timerM is zero or not
	breq set_all_zero	;make the time to zero [?]
	cpi timerS,30	;check timerS bigger than 30 or not
	brge directly_sub;if it is then sub 30
	ldi temp2,30;if it is not, timerS = 60 - (30 - timerS) and timerM - 1 
	sub temp2,timerS
	ldi temp4,60
	sub temp4, temp2
	mov timerS, temp4
	dec timerM
	jmp convert_end

set_all_zero:
	;ldi timerS,0
	;clr counter
	jmp convert_end

directly_sub:
	subi timerS, 30
	jmp convert_end


symbols: 
	cpi col, 0    ; Check if we have a star 
	breq star
	cpi col, 1    ; or if we have zero 
	breq zero     

	; Somehow is being called when not hash!
	cpi col, 2
	brne input_return

	;Hash bottom:
	; Stop the entry mode, clear up the data
		
	; Check the mode
	lds temp1, mode
	cpi temp1, ENTRY_MODE
	breq entry_hash

	cpi temp1, RUNNING_MODE
	breq running_pause

	jmp input_loop

; Clears the current time
entry_hash:
	clr counter
	clr temp3
	clr timerM
	clr timerS
	; BREAKS because of one of these variables
	jmp display_input

running_pause:
	ldi temp4, PAUSED_MODE
	sts mode, temp4
	jmp input_loop

star: 
	lds temp1, mode

	;subi temp1, - '0'

	;do_lcd_data temp1

	; If we're not in entry mode then return to loop
	;cpi temp1, ENTRY_MODE
	;brne input_return

	ldi temp1, RUNNING_MODE
	; Else: go to running mode
	sts mode, temp1

	jmp input_loop

input_return:
	jmp input_loop

zero:
	ldi temp3, 0    ; Set to zero
	rjmp convert_end 
	
; Update timer to reflect input
; TODO: make correct for when user enters only 2 numbers
convert_end:
	clr temp1

	inc counter

	cpi counter, 5
	brge sleep_loop
	cpi counter, 3
	breq update_minutes
	cpi counter, 4
	breq update_minutes2

update_minutes:
	; Get tens of timerS into temp1
	cpi timerS, 10
	brge divide_seconds
	
	add timerM, temp1

	; Multiply remainder of timerS
	; by 10 and add the new input
	ldi temp1, 10
	mul timerS, temp1
	mov timerS, r0
	add timerS, temp3

	rjmp display_input

divide_seconds:
	inc temp1
	subi timerS, 10

	rjmp update_minutes

update_minutes2:
	; Multiply timerM by 10
	ldi temp1, 10
	mul timerM, temp1
	mov timerM, r0
	clr temp1

	rjmp update_minutes
	

display_input:
	; tests	
	;ldi timerS, 34
	;ldi timerM, 12
	rcall display_time
	ldi temp3, 60 ; Wait 60 cycles before next input
	rjmp sleep_loop

sleep_loop:
  	rcall sleep_5ms
  	dec temp3
  	cpi temp3, 0
  	brne sleep_loop
	jmp input_loop

sleepL:
	rcall sleep_5ms
	rcall sleep_1ms
  	dec temp3
  	cpi temp3, 0
  	brne sleepL
	ret
	
; End entry mode


; Start running mode

; End running mode


; Start paused mode

; End paused mode


; Start finished mode

; End finished


; End microwave lifecycle modes





