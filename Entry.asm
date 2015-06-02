
update_seconds:
	; If first digit of seconds
	cpi counter, 3
	breq add_tens_sec

	; else add input to seconds
	add timerS, temp3
	rjmp display_input

add_tens_sec:
	; Add 10 * input to seconds 
	ldi temp2, 10
	mul temp3, temp2 ; Result in r0
	add timerS, r0
	rjmp display_input

update_minutes:
	; If first digit of minutes
	cpi counter, 1
	breq add_tens_min

	; else add input to minutes
	add timerM, temp3
	rjmp display_input

add_tens_min:
	;add 10 * input to seconds
	ldi temp2, 10
	mul temp3, temp2 ; Result in r0
	add timerM, r0
	rjmp display_input
