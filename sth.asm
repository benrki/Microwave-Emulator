.include "m2560def.inc"
.equ LCD_RS = 7
.equ LCD_E = 6
.equ LCD_RW = 5
.equ LCD_BE = 4

.equ F_CPU = 16000000
.equ DELAY_1MS = F_CPU / 4 / 1000 - 4
; 4 cycles per iteration - setup/call-return overhead

.equ HalfSecond = 3906 ; 500000ms (0.5s) / 128ms

.def waveStatus = r20
.def temp = r21
.def divideCounter = r22 
.def ten = r23
.def quotientL = r24
.def quotientH = r25
.def timerCounterL = r26
.def timerCounterH = r27
.def waveCounterL = r28
.def waveCounterH = r29

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

.org 0
	jmp RESET
.org OVF0addr
	jmp Timer0

RESET:
	ldi temp, low(RAMEND)		;initialize the stack
	out SPL,temp
	ldi temp, high(RAMEND)
	out SPH,temp
	
	ser temp					;initialize lcd output
	sts DDRK, temp
	out DDRA, temp	 
	clr temp
	sts PORTK, temp
	out PORTA, temp
	
	;initialize the lcd
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
	

	;clean up all the Registers
	clr timerCounterL
	clr timerCounterH
	clr waveCounterL
	clr waveCounterH
	clr waveStatus
	clr divideCounter
	ldi ten, 10

main:
	;initialize port D
	clr temp
	out DDRD, temp ; Make PORTD as input port
	out PORTD, temp

	;intialize timer0
	ldi temp, 0b00000000
	out TCCR0A,temp
	ldi temp, 0b00000010
	out TCCR0B, temp	;orescaling value = 8
	ldi temp, 1<<TOIE0	;=128 ms
	sts TIMSK0, temp	;T/C0 inyerrupt enable
	sei					;Enable global interrupt

wait:
	rjmp wait

Timer0:
	in temp,PIND		;load input from PIND to temp
	cp temp,waveStatus	;compare the waveStatus whether it has changed or not
	brne updateWaveCounter
	rjmp checkHalfSecond

updateWaveCounter:
	mov waveStatus, temp
	cpi temp, 0
	breq checkHalfSecond
	adiw waveCounterH:waveCounterL,1	;increase the wave count when temp is 1 which is a whole wave
	rjmp checkHalfSecond

checkHalfSecond:
	cpi timerCounterL, low(HalfSecond)	;compare with half second
	ldi temp, high(HalfSecond)
	cpc timerCounterH, temp
	brne notHalfSecond
	rjmp isHalfSecond


isHalfSecond:
	do_lcd_command 0b00000001 ; clear display

	;divide by 4
	lsr waveCounterH
	ror	waveCounterL
	lsr waveCounterH
	ror waveCounterL

	clr divideCounter
	clr quotientH
	clr quotientL
	clr r11		;zero
	ldi r31, '0'
	;show the waveCounter to the lcd
	division:
		cp waveCounterL, ten
		cpc waveCounterH,r11
		brlo division_end 
		sbiw waveCounterH:waveCounterL, 10
		adiw quotientH:quotientL, 1
		cp waveCounterL, ten
		cpc waveCounterH,r11
		brsh division
	
	division_end:
		push waveCounterL	
		inc divideCounter
		cp quotientL,r11 ;check quotient is zero or not
		cpc quotientH,r11
		breq display
		mov waveCounterL, quotientL
		mov waveCounterH, quotientH
		clr quotientL
		clr quotientH
		rjmp division	
		
	display:
		show:
		pop waveCounterL
		add waveCounterL, r31
		do_lcd_data waveCounterL
		cpi divideCounter,1
		breq cleanUp
		inc r11
		cp r11,divideCounter		
		brne show
		rjmp cleanUp
	
	cleanUp:
		clr waveCounterL
		clr waveCounterH
		clr timerCounterL
		clr timerCounterH
	

notHalfSecond:
	adiw timerCounterH:timerCounterL,1	;increase timeCounter
	reti
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

