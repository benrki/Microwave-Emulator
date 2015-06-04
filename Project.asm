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
.equ QUARTER_SECOND = SECOND / 4
.equ HALF_SECOND = SECOND / 2
.equ LCD_RS = 7
.equ LCD_E = 6
.equ LCD_RW = 5
.equ LCD_BE = 4
.equ CLOCKWISE = 0
.equ ANTI_CLOCKWISE = 1
.equ F_CPU = 16000000
.equ DELAY_1MS = F_CPU / 4 / 1000 - 4
.equ ROT1 = '-'
.equ ROT2 = '`'
.equ ROT3 = '|'
.equ ROT4 = '/'
.equ RPM = 19530 ; 7812 * 60 / 24 ; 60s / 8 characters * 3 revolutions
.equ DOOR_CLOSED = 0
.equ DOOR_OPEN = 1
.equ LED_OFF = 0b00000000 
.equ LED_ON = 0b11111111
.equ LED_MAX = 0b11111111
.equ LED_50 = 0b00001111
.equ LED_25 = 0b00000011
.equ SPEED_MAX = 0xFF

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

.macro print_char
	ldi r16, @0
	rcall lcd_data
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
quartCounter: .byte 1 ; Check how many quarter seconds have passed
rotCounter: .byte 2 ; Count for when to rotate
takeInput: .byte 1 ; Ability to take input (for debouncing)
input: .byte 1 ; Input for a particular loop
inputTime: .byte 2	;for storing the time of input
enteredInput: .byte 1 ; Whether we have entered any numbers in the timer
turnRotation: .byte 1 ; Last rotation direction of the turntable
rotChar: .byte 1 ; Number of last rotation character
doorStatus: .byte 1 ; Door open/closed
magnetronSpeed: .byte 1 ; Rotation speed % of the magnetron/motor
setPower: .byte 1 ; Check whether to get power level input

.cseg
.org 0
	jmp RESET

.org 0x0002
	jmp EXT_INT0
	jmp EXT_INT1

.org OVF0addr
	jmp Timer0

RESET: 
	; initialize the stack
	ldi  temp1, low(RAMEND)
	out  SPL, temp1 
	ldi  temp1, high(RAMEND) 
	out  SPH, temp1 
	
	;initialise keyboard
	ldi  temp1, PORTLDIR  ; PL7:4/PA3:0, out/in 
	sts  DDRL, temp1 

	; set INT0 as falling-edge triggered interrupt
	ldi temp1, (2 << ISC00)
	sts EICRA, temp1
	in temp1, EIMSK

	; Enable INT0
	ori temp1, (1<<INT0)
	out EIMSK, temp1

	; set INT1 as falling-edge triggered interrupt
	ldi temp1, (2 << ISC10)
	sts EICRA, temp1
	in temp1, EIMSK
	
	; enable INT1
	ori temp1, (1<<INT1)
	out EIMSK, temp1

	; set INT2 as falling-edge triggered interrupt
	ldi temp1, (2 << ISC20)
	sts EICRA, temp1
	in temp1, EIMSK
	
	; enable INT2
	ori temp1, (1<<INT2)
	out EIMSK, temp1

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

	;intialise LED
	; set Port C as output
	ser temp1
	out DDRC, temp1
	clr temp1
	out PORTC, temp1

	; set Port E as output for the top LED
	ser temp1
	out DDRF, temp1
	clr temp1
	out PORTF, temp1

	; Motor port
	ldi temp1, 0b00010000
	out DDRE, temp1

	ldi temp1, 0x00
	sts OCR3BL, temp1

	clr temp1
	sts OCR3BH, temp1

	; Set the Timer5 to Phase Correct PWM mode
	ldi temp1,(1<<CS50)
	sts TCCR3B, temp1
	ldi temp1, (1<< WGM30)| (1<<COM3B1)
	sts TCCR3A, temp1

	; Initialise timer0
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

	; Set last spin as anti-clockwise so the first
	; rotation is clockwise
	ldi temp1, ANTI_CLOCKWISE
	sts turnRotation, temp1
	ldi temp1, 1
	sts rotChar, temp1

	; Set door closed by default
	ldi temp1, DOOR_CLOSED
	sts doorStatus, temp1

	ldi temp1, 0
	sts setPower, temp1

	sts timeCounter, temp1
	sts timeCounter + 1, temp1

	sts quartCounter, temp1
	
	; Show inital 100% speed on LEDs
	ldi temp1, LED_MAX
	out PORTC, temp1	

	; Default speed of 100%
	ldi temp1, 100
	sts magnetronSpeed, temp1

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

; Button on the right
; Close door
EXT_INT0:
	push temp1
	in temp1, SREG
	push temp1

	ldi temp1, DOOR_CLOSED
	sts doorStatus, temp1

	rcall display_time

	pop temp1
	out SREG, temp1
	pop temp1

	reti
	
; Button on the left
; Open door
; When finished, will enter entry mode
; As in assignment spec, and display 00:00
; But can't take input until door is closed!
EXT_INT1:
	push temp1
	in temp1, SREG
	push temp1

	ldi temp1, DOOR_OPEN
	sts doorStatus, temp1

	lds temp1, mode
	cpi temp1, FINISHED_MODE
	breq set_entry

	rcall display_time

	jmp finish_INT1

finish_INT1:
	pop temp1
	out SREG, temp1
	pop temp1

	reti

set_entry:
	ldi temp1, ENTRY_MODE
	sts mode, temp1
	rcall display_time
	
	jmp finish_INT1

Timer0:	
	push temp1
	push temp2
	push r24
	push r25
	push r26
	push r27
	in temp1, SREG
	push temp1

	; Do not dec timer if door open
	lds temp1, doorStatus
	cpi temp1, DOOR_OPEN
	breq timer_end

	; Do not dec timer if we're not in
	; running mode
	lds temp1, mode
	cpi temp1, RUNNING_MODE
	brne timer_end

	; Increment timeCounter
	lds r24, timeCounter
	lds r25, timeCounter + 1
	adiw r25:r24, 1 
	sts timeCounter, r24
	sts timeCounter + 1, r25

	; Increment the rotation counter
	lds r26, rotCounter
	lds r27, rotCounter + 1
	adiw r27:r26, 1
	sts rotCounter, r26
	sts rotCounter + 1, r27

	cpi r26, low(RPM)
	ldi temp1, high(RPM)
	cpc r27, temp1
	brne check_speed

	clr r26
	clr r27
	sts rotCounter, r26
	sts rotCounter + 1, r27
	rjmp rotate_turntable

timer_end:
	jmp end_timer0

check_speed:
	lds temp1, magnetronSpeed

	cpi temp1,100
	breq run_max

	cpi temp1, 50
	breq check_half_sec

	cpi temp1, 25
	breq check_quart_sec

	cpi r24, low(QUARTER_SECOND)
	ldi temp1, high(QUARTER_SECOND)
	cpc r25, temp1
	breq check_second
	
	jmp check_second

check_half_sec:
	cpi r24, low(HALF_SECOND)
	ldi temp1, high(HALF_SECOND)
	cpc r25, temp1
	brlt run_max
	
	ldi temp1, 0
	sts OCR3BL, temp1

	jmp check_second

check_quart_sec:
	cpi r24, low(QUARTER_SECOND)
	ldi temp1, high(QUARTER_SECOND)
	cpc r25, temp1
	brlt run_max
	
	ldi temp1, 0
	sts OCR3BL, temp1

	jmp check_second
run_max:
	ldi temp1, SPEED_MAX
	sts OCR3BL, temp1
	jmp check_second

check_second:
	cpi r24, low(SECOND)
	ldi temp1, high(SECOND)
	cpc r25, temp1
	brne timer_end

	; Second has passed
	; Clear timeCounter
	clr r24
	clr r25
	sts timeCounter, r24
	sts timeCounter + 1, r25

	jmp dec_timer

; Print ascii of turntable in top right corner
display_rotation:
	rcall display_time
	jmp check_second

rotate_turntable:
	lds temp1, turnRotation
	cpi temp1, CLOCKWISE
	breq rotate_clockwise
	rjmp rotate_anticlockwise

rotate_clockwise:
	lds temp1, rotChar
	cpi temp1, 4
	breq loop_clockwise
	inc temp1
	sts rotChar, temp1
	rjmp display_rotation

loop_clockwise:
	ldi temp1, 1
	sts rotChar, temp1
	rjmp display_rotation

rotate_anticlockwise:
	lds temp1, rotChar
	cpi temp1, 1
	breq loop_anticlockwise
	dec temp1
	sts rotChar, temp1
	rjmp display_rotation

loop_anticlockwise:
	ldi temp1, 4
	sts rotChar, temp1
	rjmp display_rotation

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
	lds temp1, enteredInput
	; If no input then add 60 and return
	cpi temp1, 0
	breq add_min

	; Turn off motor
	ldi temp1, 0x00
	sts OCR3BL, temp1

	ldi temp1, FINISHED_MODE
	sts mode, temp1

	; Clear display
	do_lcd_command 0b00000001

	; Display 'Done' on first line
	print_char 'D'
	print_char 'o'
	print_char 'n'
	print_char 'e'

	; Display 'Remove food' on second line
	do_lcd_command 0b11000000 ;next line
	print_char 'R'
	print_char 'e'
	print_char 'm'
	print_char 'o'
	print_char 'v'
	print_char 'e'
	print_char ' '
	print_char 'f'
	print_char 'o'
	print_char 'o'
	print_char 'd'

	rjmp end_timer0

add_min:
	ldi timerS, 59
	rcall display_time
	rjmp end_timer0

end_timer0:
	pop temp1
	out SREG, temp1
	pop r27
	pop r26
	pop r25
	pop r24
	pop temp2
	pop temp1

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

	ldi temp2, 10; 11 spaces to display
	rjmp display_space 

divide_sec:
	inc temp1
	subi timerS, 10
	rjmp display_sec

; Print out whitespace to show the turntable in the upper-right
display_space:
	cpi temp2, 0
	breq display_turntable
	print_char ' '
	dec temp2
	rjmp display_space

display_turntable:
	lds temp1, rotChar
	cpi temp1, 1
	breq display_turn1
	cpi temp1, 2
	breq display_turn2
	cpi temp1, 3
	breq display_turn3
	cpi temp1, 4
	breq display_turn4

display_turn1:
	ldi temp1, ROT1
	do_lcd_data temp1
	rjmp display_2nd_line

display_turn2:
	ldi temp1, ROT2
	do_lcd_data temp1
	rjmp display_2nd_line

display_turn3:
	ldi temp1, ROT3
	do_lcd_data temp1
	rjmp display_2nd_line

display_turn4:
	ldi temp1, ROT4
	do_lcd_data temp1
	rjmp display_2nd_line

display_2nd_line:
	do_lcd_command 0b11000000 ; Second line
	ldi temp2, 15

	jmp display_space_bottom

; Print out whitespace to show the turntable in the upper-right
display_space_bottom:
	cpi temp2, 0
	breq display_door
	print_char ' '
	dec temp2
	rjmp display_space_bottom

display_door:
	lds temp1, doorStatus
	cpi temp1, DOOR_OPEN
	breq display_open
	cpi temp1, DOOR_CLOSED
	breq display_closed

	jmp finish_display ; Should not occur

display_open:
	print_char 'O'
	; light top most LED
	ldi temp1, LED_ON
	out PORTF, temp1
	jmp finish_display

display_closed:
	print_char 'C'
	ldi temp1,LED_OFF
	out PORTF, temp1
	jmp finish_display

finish_display:
	; Finished displaying
	pop temp1
	pop timerS
	pop timerM	
	ret

; End helper functions

; Start input loop

set_entry_mode:
	ldi temp1, ENTRY_MODE
	sts mode, temp1
	clr counter
	ldi temp2, 0
	sts enteredInput, temp2
	jmp input_loop

input_loop:
	; Take no input if door open
	lds temp1, doorStatus
	cpi temp1, DOOR_OPEN
	breq input_loop

	ldi  temp4, INITCOLMASK  ; initial column mask (temp4 = cmask)
	ldi  col, 0      ; initial column 
	ldi temp1, 0
	sts input, temp1
	rjmp colloop

colloop: 
	cpi  col, 4 
	breq  end_input_loop      ; If all keys are scanned, repeat. 
	sts  PORTL, temp4    ; Otherwise, scan a column. 

	ldi   temp1, 0xFF    ; Slow down the scan operation. 
	rjmp delay

end_input_loop:
	; Check if we had any input this loop
	lds temp1, input
	cpi temp1, 0
	breq allow_input
	; Disallow input until no input
	ldi temp1, 0
	sts takeInput, temp1
	rjmp input_loop

allow_input:
	ldi temp1, 1
	sts takeInput, temp1
	rjmp input_loop

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
	breq  press       ; if bit is clear, the key is press
	inc   row      ; else move to the next row 
	lsl   temp3       
	jmp   rowloop 

nextcol:          ; if row scan is over 
	lsl temp4        
	inc col       ; increase column value 
	jmp colloop      ; go to the next column 

press:	
	mov r30, row ;prev row
	mov r29, col ;prev col

	cpi   col, 3    ; If the pressed key is in col.3 
	breq   letters    ; we have a letter 
						; If the key is not in col.3 and  					   
	cpi   row, 3    ; If the key is in row3,  
	breq  jmp_symbols    ; we have a symbol or 0

	; Numbers
	mov temp3, row  ; Otherwise we have a number in 1-9 
	lsl  temp3 
	add  temp3, row 
	add  temp3, col  ; temp1 = row*3 + col+1
	inc temp3

	ldi temp1, 1
	sts input, temp1

	sts enteredInput, temp1
	
	lds temp1, setPower
	cpi temp1, 1
	breq jmp_set_power

	jmp convert_end

jmp_set_power:
	jmp set_power

jmp_symbols:
	jmp symbols

letters:
	ldi temp1, 1
	sts input, temp1

	cpi row, 0
	breq letter_A
	cpi row, 1
	breq letter_B
	cpi row, 2
	breq letter_C
	cpi row, 3
	breq letter_D
	jmp display_input

letter_A:
	;ldi temp3, 'A'
	lds temp1, mode
	cpi temp1, ENTRY_MODE
	breq display_set_power
	jmp convert_end

letter_B:
	ldi temp3, 'B'
	jmp convert_end	

letter_C:
	lds temp2, mode
	cpi temp2, RUNNING_MODE
	breq add_30sec
	jmp input_loop	


letter_D:
	lds temp2,mode
	cpi temp2, RUNNING_MODE
	breq sub_30sec
	jmp input_loop	

add_30sec:
	cpi timerS, 30		;check timerS less than 30 or not
	brlt directly_add	;if it is then add 30 directly
	subi timerS, 30
	inc timerM
	jmp display_input

directly_add:
	ldi temp2, 30
	add timerS, temp2
	jmp display_input

sub_30sec:
	cpi timerS,30	;check timerS bigger than 30 or not
	brge directly_sub;if it is then sub 30

	; Else check if we have minutes to subtract
	cpi timerM, 0	;check timerM is zero or not
	breq set_all_zero	; Set time zero

	dec timerM
	;ldi temp1, 60
	;add timerS temp1
	;subi timerS, 30

	ldi temp2, 30;if it is not, timerS = 60 - (30 - timerS) and timerM - 1 
	add timerS, temp2
	
	jmp display_input

set_all_zero:
	ldi timerS, 0
	jmp display_input

directly_sub:
	subi timerS, 30
	jmp display_input

goToInput:
	jmp display_input

display_set_power:
	do_lcd_command 0b00000001 ; clear display
	; Display 'Set Power 1/2/3'
	print_char 'S'
	print_char 'e'
	print_char 't'
	print_char ' '
	print_char 'P'
	print_char 'o'
	print_char 'w'
	print_char 'e'
	print_char 'r'
	print_char ' '
	print_char '1'
	print_char '/'
	print_char '2'
	print_char '/'
	print_char '3'

	ldi temp1, 1
	sts setPower, temp1

	jmp input_loop

symbols:
	; Check if we can take input
	lds temp1, takeInput
	cpi temp1, 1
	brne goToInput

	ldi temp1, 1
	sts input, temp1

	cpi col, 0    ; Check if we have a star 
	breq star
	cpi col, 1    ; or if we have zero 
	breq jmp_zero

	cpi col, 2
	brne input_return
	; Hash
	ldi temp3, '#'

	lds temp1, setPower
	cpi temp1, 1
	breq jmp_set_power2
		
	; Check the mode
	lds temp1, mode

	cpi temp1, RUNNING_MODE
	breq running_pause

	cpi temp1, ENTRY_MODE
	breq clear_time

	cpi temp1, PAUSED_MODE
	breq clear_time

	jmp display_input

jmp_zero:
	jmp zero

jmp_set_power2:
	jmp set_power

; Clears the current time
clear_time:
	ldi temp1, ENTRY_MODE
	sts mode, temp1

	clr counter
	clr temp3
	clr timerM
	clr timerS
	jmp display_input

running_pause:
	ldi temp4, PAUSED_MODE
	sts mode, temp4

	jmp display_input

input_return:
	jmp display_input

star: 
	ldi temp3, '*'
	lds temp1, mode
	lds temp2, takeInput
	lds temp4, setPower

	cpi temp4, 1
	breq goto_set_power

	cpi temp2, 0
	breq input_return
	
	ldi temp2, 1
	sts input, temp2

	ldi temp2, 0
	sts takeInput, temp2

	ldi temp1, RUNNING_MODE
	sts mode, temp1

	lds temp1, turnRotation
	cpi temp1, CLOCKWISE
	breq set_anticlockwise
	ldi temp1, CLOCKWISE
	sts turnRotation, temp1
	jmp input_loop

goto_set_power:
	jmp set_power

set_anticlockwise:
	ldi temp1, ANTI_CLOCKWISE	
	sts turnRotation, temp1
	jmp input_loop

zero:
	ldi temp3, 0    ; Set to zero

	lds temp1, setPower
	cpi temp1, 1
	breq set_power

	jmp convert_end
	
; Update timer to reflect input
convert_end:
	clr temp1

	; Check if we can take input
	lds temp1, takeInput
	cpi temp1, 1
	brne display_input

	ldi temp1, 0
	sts takeInput, temp1

	inc counter

	cpi counter, 5
	brge input_return
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
	rjmp input_loop

set_power:
	cpi temp3, 1
	breq set_power_max

	cpi temp3, 2
	breq set_power_half

	cpi temp3, 3
	breq set_power_quart

	cpi temp3, '#'
	breq return_entry

	; Otherwise, do nothing
	jmp input_loop

set_power_max:
	clr temp3
	ldi temp1, 0
	sts setPower, temp1
	
	ldi temp1, 100
	sts magnetronSpeed, temp1

	; Show speed on LEDs
	ldi temp1, LED_MAX
	out PORTC, temp1

	jmp display_input

set_power_half:
	clr temp3
	ldi temp1, 0
	sts setPower, temp1
	
	ldi temp1, 50
	sts magnetronSpeed, temp1

	; Show speed on LEDs
	ldi temp1, LED_50
	out PORTC, temp1
	
	jmp display_input

set_power_quart:
	clr temp3
	ldi temp1, 0
	sts setPower, temp1
	
	ldi temp1, 25
	sts magnetronSpeed, temp1

	; Show speed on LEDs
	ldi temp1, LED_25
	out PORTC, temp1

	jmp display_input

return_entry:
	clr temp3
	ldi temp1, 0
	sts setPower, temp1
	
	ldi temp1, ENTRY_MODE
	sts mode, temp1

	jmp display_input

; End input loop
