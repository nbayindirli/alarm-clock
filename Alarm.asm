;-------------------------------------------------------------------------------
; MSP430 Assembler Code Template for use with TI Code Composer Studio
;
;
;-------------------------------------------------------------------------------
            .cdecls C,LIST,"msp430.h"       ; Include device header file

;-------------------------------------------------------------------------------
            .def    RESET                   ; Export program entry-point to
                                            ; make it known to linker.
;-------------------------------------------------------------------------------
            .data

time:		.word	0, 0, 0		; Sec, Min, Hr
AMPM:		.word	0			; 0 - am, 1 - pm

alarmOn:	.word	0			; 0 - off, 1 - on

alarm:		.word	0, 0, 0		; Sec, Min, Hr
alarmAMPM:	.word	0			; 0 - am, 1 - pm

timeTillAlarm:
			.word	0, 0

; PWM Parameters
; Modify these parameters to give you proper wake up light behavior
lowerDC:	.word	20
upperDC:	.word	4000
step:		.word	1
samplingPr:	.word	150

            .text                           ; Assemble into program memory.
            .retain                         ; Override ELF conditional linking
                                            ; and retain current section.
            .retainrefs                     ; And retain any sections that have
                                            ; references to current section.

;-------------------------------------------------------------------------------
RESET       mov.w   #__STACK_END,SP         ; Initialize stackpointer
StopWDT     mov.w   #WDTPW|WDTHOLD,&WDTCTL  ; Stop watchdog timer


;-------------------------------------------------------------------------------
; Main loop here
;-------------------------------------------------------------------------------

debugPin:	.set	BIT2

debugLED:	.set	BIT0
alarmLED:	.set	BIT6

button:		.set	BIT3

; Configure peripherals

			; Set up alarm button
			bic.b	#button, &P1SEL
			bic.b	#button, &P1DIR
			bis.b	#button, &P1IE
			bis.b	#button, &P1IES
			bis.b	#button, &P1REN
			bis.b	#button, &P1OUT

			bic.b	&button,P1IFG

			; Set up LEDS
			bic.b	#debugLED, &P1SEL
			bis.b	#debugLED, P1DIR

			bic.b	#alarmLED, &P1SEL
			bis.b	#alarmLED, P1DIR


			call	#ConfigSysClks			; Configure system clock
			call	#ConfigClockTimer		; Configure timer A1 to generate 1Hz frequency

			;call	#StartPWMTimer			; Configure timer A0 to start generating PWM

			bis.w	#GIE, SR

			bis.b	#debugPin, &P1DIR

loop:		bis.w	#LPM1+GIE, SR

			; update time (Hr Min Sec AM/PM) routine starts here

			add.w   #1, &time			    ; Increment seconds count
			cmp.w   #60, &time  			; Compare to full minute
			jnz     TimeCountFull
			clr.w   &time   				; Clear the seconds count
			add.w	#1, &time+2				; Increment the minutes count
			cmp.w	#60, &time+2			; Check for full minutes
			jnz 	TimeCountFull
			clr.w 	&time+2					; Clear the minutes count
			add.w	#1, time+4				; Increment hours counts
			cmp.w	#13, &time+4			; Compare AM/PM
			jnz		TimeCountFull
			clr.w	&time+4					; Clear the hours count
			xor.w	#BIT0, &AMPM			; Toggle AM/PM

			; -----------------------------------

TimeCountFull:

			jmp		loop

ConfigSysClks:
			clr.b	&DCOCTL
			mov.b	&CALBC1_1MHZ, &BCSCTL1	; Config MCLK to calibrated 1MHz
			mov.b	&CALDCO_1MHZ, &DCOCTL
			mov.b	#DIVS_3, &BCSCTL2		; Config SMCLK to 1/8MHz

			ret

ConfigClockTimer:
			mov.w	#ID_3+MC_1+TASSEL_2+TACLR, &TA1CTL		; Config Timer Clock to SMCLK/8MHz and count upto CCR0
			mov.w	#15624, &TA1CCR0							; Generate a ~1Hz clock.
			mov.w	#CCIE, &TA1CCTL0						; Enable CCR0 Interrupt
			ret

StartPWMTimer:
			mov.w	&samplingPr, &TA0CCR0					; Update PWM sampling period
			mov.w	&lowerDC, &TA0CCR1						; Set lower threshold of PWM duty cycle.
															; TA0CCR1 cannot start with 0!

			bis.b	#alarmLED, &P1DIR						; Configure P1.6 to be used as TA0CCR1 output
			bis.b	#alarmLED, &P1SEL
			bic.b	#alarmLED, &P1SEL2

			bic.b	#alarmLED, &P1OUT

			mov.w	#OUTMOD_7, &TA0CCTL1					; Use reset/set mode to generate PWM
			mov.w	#MC_1 + TASSEL_2 + TACLR, &TA0CTL		; Config Timer Clock to SMCLK.
															; Start Timer in up mode to count up to CCR0
			ret

StopPWMTimer:
			bic.b	#alarmLED, &P1SEL						; disconnect debug LED from timerA0 CCR0

			mov.w	#MC_0 + TACLR, &TA0CTL					; clear timerA0 config for PWM
			clr.w	&TA0CCTL0
			clr.w	&TA0CCR0
			clr.w	&TA0CCR1

			ret

StartAlarmTimer:
			bis.b	#BIT0, &P1SEL
			bic.b	#BIT0, &P1SEL2
			bic.b	#BIT0, &P1DIR

			mov.w	#CCIE, &TA0CCTL0
			mov.w	#ID_0+MC_1+TASSEL_0+TACLR, &TA0CTL

			ret

FindTimeTillAlarm:

			mov.w	&time, R8								; Move seconds into arbitrary register
			push.w	&time+2
			call 	#MultBy60
			pop.w	R7
			add.w	R7, R8

			push.w	&time+4
			call	#MultBy60
			call	#MultBy60
			pop.w	R7
			add.w	R7, R8

			mov.w	&alarm, R9
			push.w	&alarm+2
			call	#MultBy60
			pop.w	R7
			add.w	R7, R9

			push.w	&alarm+4
			call	#MultBy60
			call	#MultBy60
			pop.w	R7
			add.w	R7, R9

			sub.w	R9, R8
			mov.w	R8, &timeTillAlarm

			ret


;------------------------------- subroutine MultBy60 ---------------------------
;
; 	function:
;			accept 1 parameter via stack.
;			return result of multiplying the parameter with 60 via stack
;
;	prerequisit:
;			the parameter is passed to the routine via stack
;			before calling this subroutine, push the parameter
;			to be multiplied onto the stack
;
;   postrequisit:
;			upon return from subroutine, the result of
;			multiplication will be stored at the top of the stack,
;			replacing the original parameter passed to this routine.
;
;--------------------------------------------------------------------------------
MultBy60:
			push.w	R12

			mov.w	4(SP), R12
			rla		R12
			rla		R12
			rla		R12
			rla		R12
			rla		R12
			rla		R12

			sub.w	4(SP), R12
			sub.w	4(SP), R12
			sub.w	4(SP), R12
			sub.w	4(SP), R12

			mov.w	R12, 4(SP)

			pop.w	R12
			ret
;----------------- End of subroutine MultBy60 subroutine -----------------------

;-------------------------------------------------------------------------------
; Interrupt Service Routines
;-------------------------------------------------------------------------------

; Port1 ISR
SetAlarmISR:

			xor.b	#BIT0, &alarmOn							; Toggles on alarm
			xor.b	#debugLED, &P1OUT
			cmp.w	#0, &alarmOn							; Check if alarm is on
			jeq		AlarmOff
			call	#FindTimeTillAlarm
			call	#StartAlarmTimer

AlarmOff:

			bic.b	#button, &P1IFG

			reti

; TA1CCR0 ISR
ClockTickTimerISR:
			xor.b	#debugPin, &P1OUT						; Toggle debug pin

			; Update PWM duty cycle
			cmp.w	&TA0CCR1, &upperDC						; update PWM duty cycle
			jl		endPWM
			add.w	&step, &TACCR1

			; in class
			bic.w	#LPM1, 0(SP)

			reti

endPWM:
			call	#StopPWMTimer
			bis.b	#alarmLED, &P1OUT						; keep the alarm LED on

			reti

; TA0CCR0 ISR
DownCntISR:
			; Downcount to alarm time routine starts here

			; -------------------------------------------
			reti


;-------------------------------------------------------------------------------
; Stack Pointer definition
;-------------------------------------------------------------------------------
            .global __STACK_END
            .sect   .stack

;-------------------------------------------------------------------------------
; Interrupt Vectors
;-------------------------------------------------------------------------------

			.sect	".int02"	; Port1 ISR
			.short	SetAlarmISR

			.sect	".int09"	; TimerA0 CCR0 ISR
			.short	DownCntISR

            .sect	".int13"	; TimerA1 CCRO ISR
            .short	ClockTickTimerISR

            .sect   ".reset"                ; MSP430 RESET Vector
            .short  RESET
