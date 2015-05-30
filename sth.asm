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
.def timer = r22 ; Time in seconds

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
	clr temp
	st Y+, temp
	st Y, temp
.endmacro

.dseg
time: .byte 2 ; two-bytes for seconds
timeCounter: .byte 2 ; Two bytes to check if 1 second has passed
takeInput: .byte 1 ; Ability to take input (for debouncing)

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

	clr timer ; set timer to 0

	; Enable debounced input
	ldi temp1, 1
	sts takeInput, temp1

	rjmp entry

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

	; Enable input
	ldi temp3, 1
	sts takeInput, temp3

	lds r24, time
	lds r25, time+1
	adiw r25:r24, 1 ; Increment second counter by 1
	
	sts time, r24
	sts time + 1, r25
	
	;rcall displayTime
	
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

displayTime:
	do_lcd_command 0b00000001 ; clear display
	clr temp1	;divideCounter
	clr r26		;quotientL
	clr r27		;quotientH
	clr r11
	ldi r31, '0'
	ldi temp3, 10
	ldi temp4, 0
	;show the waveCounter to the lcd
	division:
		cp r24, temp3
		cpc r25,temp4
		brlo division_end 
		sbiw r25:r24, 10
		adiw r27:r26, 1
		cp r24, temp3
		cpc r25,temp4
		brsh division

	division_end:
		push r24	
		inc temp1
		cp r26,temp4 ;check quotient is zero or not
		cpc r27,temp4
		breq display
		mov r24, r26
		mov r25, r27
		clr r26
		clr r27
		rjmp division	
	
	display:
		show:
		pop r24
		add r24, r31
		do_lcd_data r24
		cpi temp1,1
		breq cleanUp
		inc r11
		cp r11,temp1		
		brne show
		rjmp cleanUp

	cleanUp:
		ret
; End interrupts

; Entry mode
entry: 
	ldi   temp4, INITCOLMASK  ; initial column mask 
	ldi  col, 0      ; initial column 


colloop: 
	cpi  col, 4 
	breq  entry      ; If all keys are scanned, repeat. 
	sts  PORTL, temp4    ; Otherwise, scan a column. 

	ldi   temp1, 0xFF    ; Slow down the scan operation. 
delay:
	dec   temp1 
	brne   delay 

	lds  temp1, PINL    ; Read PORTL 
	andi   temp1, ROWMASK    ; Get the keypad output value 
	cpi   temp1, 0xF    ; Check if any row is low 
	breq   nextcol 
	      ; If yes, find which row is low 
	ldi   temp3, INITROWMASK  ; Initialize for row check 
	clr  row      ; 

rowloop: 
	cpi   row, 4       
	breq   nextcol     ; the row scan is over. 
	mov   temp2, temp1     
	and   temp2, temp3    ; check un-masked bit 
	breq   convert       ; if bit is clear, the key is p
	inc   row      ; else move to the next row 
	lsl   temp3       
	jmp   rowloop 

nextcol:          ; if row scan is over 
	lsl temp4        
	inc col       ; increase column value 
	jmp colloop      ; go to the next column 

convert:
; Compare with previous input value

; If different: continue

; Else, ignore
	cpi   col, 3    ; If the pressed key is in col.3 
	breq   letters    ; we have a letter 
						; If the key is not in col.3 and  					   
	cpi   row, 3    ; If the key is in row3,  
	breq   symbols    ; we have a symbol or 0 

	mov temp3, row  ; Otherwise we have a number in 1-9 
	lsl  temp3 
	add  temp3, row 
	add  temp3, col  ; temp1 = row*3 + col
	subi temp3, -'1'
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
	;ldi temp1, '#'    ; if not we have hash (we don't need hash)
	jmp sleep_loop

star:  
	do_lcd_command 0b00000001 ; clear display
	jmp sleep_loop

zero: 
	ldi temp3, 0    ; Set to zero
	subi temp3, -'0'
	rjmp convert_end 
	
; Print to display if can take input
convert_end:

	;do_lcd_command 0b00000001 ; clear display
	do_lcd_data temp3

	ldi temp3, 100
sleep_loop:
  	rcall sleep_5ms
  	dec temp3
  	cpi temp3, 0
  	brne sleep_loop

	jmp entry
; End Entry mode







