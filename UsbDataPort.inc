;******************************************************************************
;	AntLift.inc -- macro, defines and what not
;******************************************************************************

;*******************************************************************************
;Defines
;*******************************************************************************
; Memory Banks I touch
#define Bank0		0x000
#define	Bank1		0x080
#define Bank2		0x100
#define Bank3		0x180
#define Bank4		0x200
#define Bank5		0x280
#define Bank6		0x300
#define Bank7		0x380

;*******************************************************************************

;*******************************************************************************
;Port defines -- Where I plan to hook everything up
;
; I use binary because it makes a nice visual depiction
;*******************************************************************************
; Port B bit masks, mostly just EUSART RX/TX
; I may add a hearbeat LED later

#define E_Line		b'00000001'	; pin RB0 connected to the LCD E line, pin 6
#define RX_DATA		b'00000010'	; pin RB1 is serial receive data
#define TX_DATA		b'00000100'	; pin RB2 is serial transmit data
#define LCD_RW  	b'00001000'	; pin RB3 connected to the LCD R/W line, pin 5
#define LCD_RS  	b'00010000'	; pin RB4 connected to the LCD R/S line, pin 4

PORTB_INPUTS	equ	E_Line | LCD_RW | LCD_RS

#define E_Line_BIT	.0
#define RX_DATA_BIT	.1
#define TX_DATA_BIT	.2


; Port A, bit masks, all lines are input
; Hooked to the LCD data lines

#define	Data_0		b'00000001'	; pin RA0
#define	Data_1		b'00000010'	; pin RA1
#define	Data_2		b'00000100'	; pin RA2
#define	Data_3		b'00001000'	; pin RA3
#define	Data_4		b'00010000'	; pin RA4
#define	Data_5		b'00010000'	; pin RA5
#define	Data_6		b'00010000'	; pin RA6
#define	Data_7		b'00010000'	; pin RA7

PORTA_INPUTS	equ	0xff

		page
