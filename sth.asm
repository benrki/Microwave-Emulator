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
time: .byte 2 ; two-bytes for seconds
mode: .byte 2 ; for storing the current mode
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

	; If running mode 
	; decrement the time
	; If paused mode
	; Do nothing
	; If entry mode
		; TODO
		; Enable input
		;ldi temp3, 1
		;sts takeInput, temp3
	; If finished 
	; do nothing

	lds r24, time
	lds r25, time+1
	adiw r25:r24, 1 ; Increment second counter by 1
	
	sts time, r24
	sts time + 1, r25
		
	; clear timeCounter
	clr r24
	clr r25
	sts timeCounter, r24
	sts timeCounter + 1, r25
	
	rjmp ENDIF

NotSecond: ; Store in temporary counter
	sts timeCounter, r24
	sts timeCounter + 1, r25
	rjmp ENDIF

ENDIF:
	pop r25
	pop r24
	pop temp2
	pop temp1
	;out SREG,temp1

	reti

; End interrupts

; Helper functions

; Display timerS
display_time:
	push timerM
	push timerS
	push temp1

	rjmp convert_time

convert_time:
	; Keep dividing timerS by 60 to get timerM
	cpi timerS, 61
	brge divide_time
	rjmp end_convert_time

divide_time:
	subi timerS, 60
	inc timerM
	rjmp convert_time
	
end_convert_time:
	; Clear display
	do_lcd_command 0b00000001

	clr temp1
	rjmp display_min

display_min:
	; First digit
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

; Microwave lifecycle modes

; Entry mode
set_entry_mode:
	ldi temp1, ENTRY_MODE
	sts mode, temp1
	jmp entry

entry:
	ldi  temp4, INITCOLMASK  ; initial column mask (temp4 = cmask)
	ldi  col, 0      ; initial column 
	rjmp colloop

colloop: 
	cpi  col, 4 
	breq  entry      ; If all keys are scanned, repeat. 
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

convert:
	cpi r31,0
	brne press
	
	cp r30, row	
	brne press	

	cp r29,col
	brne press
 
goback:
	ldi temp3,60
	rcall sleepL

	
press:	
	mov r30,row ;prev row
	mov r29,col ;prev col

	cpi   col, 3    ; If the pressed key is in col.3 
	breq   letters    ; we have a letter 
						; If the key is not in col.3 and  					   
	cpi   row, 3    ; If the key is in row3,  
	breq   symbols    ; we have a symbol or 0

 
	mov temp3, row  ; Otherwise we have a number in 1-9 
	lsl  temp3 
	add  temp3, row 
	add  temp3, col  ; temp1 = row*3 + col'

	inc counter
	jmp convert_end

letters: 
	;convert numbers seen on LCD to full number
	;check the row is zero to make sure it is A
	;once is A then clear next and add the numbe up
	ldi temp3, 'A' 
	add temp3, row    ; Get the ASCII value for the key
	jmp convert_end

symbols: 
	cpi col, 0    ; Check if we have a star 
	breq star 
	cpi col, 1    ; or if we have zero 
	breq zero           
	
	; Hash bottom:
	; Stop the entry mode, clear up the data
		
	; Check the mode
	lds temp1, mode
	cpi temp1, ENTRY_MODE
	breq entry_pause

	cpi temp1, RUNNING_MODE
	breq running_pause

	jmp entry

entry_pause:
	;clr counter
	;do_lcd_command 0b00000001 ; clear display
	;clr temp3
	;clr timerM
	;clr timerS
	;rcall display_time
	;jmp entry

running_pause:
	ldi temp4, PAUSED_MODE
	sts mode, temp4
	jmp entry

star:  
	; TODO
	jmp entry

zero: 
	ldi temp3, 0    ; Set to zero
	rjmp convert_end 
	
; Update timer to reflect input
convert_end:
	ldi temp2, 10
	mul timerS, temp2
	mov timerS, r0
	add timerS, temp3
	rjmp display_input

display_input:	
	rcall display_time
	ldi temp3, 60 ; Wait 60 cycles before next input
	rjmp sleep_loop

sleep_loop:
  	rcall sleep_5ms
  	dec temp3
  	cpi temp3, 0
  	brne sleep_loop
	jmp entry

sleepL:
	rcall sleep_5ms
	rcall sleep_1ms
  	dec temp3
  	cpi temp3, 0
  	brne sleepL
	ret
	
; End Entry mode

; End lifecycle modes



