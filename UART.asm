;*******************************************************************************
; UART -- Send/Receive via the UART
;

	list      p=16F1826     ; list directive to define processor
	#include <p16f1826.inc> ; processor specific variable definitions
	errorlevel -302			; turn off banksel warning

	#include	"UsbDataPort.inc"	; Project specific data

; Pins used to talk via the UART

#define USB_RX	.1	; pin RB1, receives from USB
#define USB_TX	.2	; pin RB2, send to the USB


	; baud rate comes from the datasheet table 25-5, page 303
	; for SYNC = 0, BRGH = 1, BRG16 = 1
	; set SPBRG = 138 for 57.6k baud, with error of -0.08%
	; set SPBRG = 832 for 9600 baud
	; set SPBRG = 6666 for 1200 baud

#define BAUDCON_MASK	b'00001000'	; set BRG16 datasheet pg 298
#define BAUDRATEH		0x00	; 57,600 baud
#define BAUDRATEL		0x22
;
;#define BAUDRATEH		0x1A	; 1,200 baud, sometimes slow down for my logic analyzer
;#define BAUDRATEL		0x0A

	udata

byte_to_send	RES	1	;used in SendByte
bitcounter		RES 1
hexbyte_to_send RES 1	; used in SendHexByte
hexnibble_to_send RES 1	 ; used in SendHexNibble

	page

;*******************************************************************************
;*******************************************************************************
; my two ring buffer pointers for TX


;*******************************************************************************
;	Storage for TX/RX ring buffers
;
; The buffers themselves sit in different banks, but they are mapped to look
; identically to each other.  This allows them to share some common sub-routines
;*******************************************************************************

; the map for each bank

write_ptr		equ	0x20
read_ptr		equ	0x21
temp_write		equ	0x22		; when writing to buffer, holds byte for usec
temp_read		equ	0x23		; when reading from buffer, holds byte for usec
read_save_fsrl	equ	0x24
read_save_fsrh	equ	0x25
write_save_fsrl	equ	0x26
write_save_fsrh	equ	0x27
buffer			equ	0x28

#define	BUFF_SIZE	0x70-buffer	; eighty bytes in both buffers, minus my temp values
							; let's hope I don't need more

#define TXBank	Bank1
#define RXBank	Bank2

tx_data	udata	TXBank+0x20
tx_buff_write	res 1		;offset to write into the ring buffer
tx_buff_read	res 1		;offset to read from the ring buffer
tx_temp_write	res	1
tx_temp_read	res	1
tx_read_fsrl	res	1
tx_read_fsrh	res	1
tx_write_fsrl	res	1
tx_write_fsrh	res	1
tx_buff			res	BUFF_SIZE

rx_data	udata	RXBank+0x20
rx_buff_write	res	1
rx_buff_read	res	1
rx_temp_write	res	1
rx_temp_read	res 1
rx_read_fsrl	res	1
rx_read_fsrh	res	1
rx_write_fsrl	res	1
rx_write_fsrh	res	1
rx_buff			res	BUFF_SIZE


	Page
;*******************************************************************************
; UARTInit -- Get the UART, or EUSART, ready for use
;
; Turns on transmit and receive and configures the baud rate based on the
; calculations above.  Then fires up the interrupts to make it all fun!
;*******************************************************************************

uart	code

	Global	UARTInit

UARTInit
	; setup my ring buffers

	BankSel	TXBank			; which is Bank1
	call	BufferInit		; Initialize the transmit buffer
	bsf		TRISB,USB_RX	; as long as I'm on Bank1, set RX pin as input

	BankSel	RXBank
	call	BufferInit

	BankSel	Bank3		; UART control registers are in Bank3

	bsf		TXSTA,TXEN	; enable transmit, datasheet page 289
	bcf		TXSTA,SYNC	; clear for ASYNC operation
	bsf		TXSTA,BRGH
	bsf		RCSTA,SPEN	; turn on the EUSART, datasheet page 289
	bsf		RCSTA,CREN	; enables receive, datasheet page 292
	bcf		RCSTA,ADDEN	; Not using address decode, datasheet page 293

	bsf		BAUDCON,BRG16	; datasheet page 298

	movlw	BAUDRATEH	; set baudrate for 57.6K
	movwf	SPBRGH		; datasheet page 299
	movlw	BAUDRATEL
	movwf	SPBRGL		; also page 299

	BankSel	Bank1
	bsf		TRISB,USB_RX	; set receive pin as input
	bsf		PIE1,RCIE		; enable RC interrupts, datasheet page 90

	; set up for interrupts to control my life

	BankSel	Bank0

	bsf		INTCON,PEIE	; enable external interrupts, datasheet page 89

	return

	page
;*******************************************************************************
; BufferInit - Initialize the read & write pointers to zero
;
; Doesn't really do much but zero the read and write pointers for the ring
; buffers.  I did put some unit testing code here that exercises the ring
; buffer routines.  I switch it out for production builds.
;*******************************************************************************

BufferInit:
	clrf	write_ptr
	clrf	read_ptr

	ifdef	__DEBUG2
;
; Some Unit test code for the ring buffers

	call	ReadAByte
	btfsc	STATUS,Z		; should be zero, no data
	nop

	movlw	'T'				; write some data then read it back
	call	WriteAByte
	movlw	'e'
	call	WriteAByte
	movlw	's'
	call	WriteAByte
	movlw	't'
	call	WriteAByte

	call	ReadAByte
	btfss	STATUS,Z
	nop
	call	ReadAByte
	btfss	STATUS,Z
	nop
	call	ReadAByte
	btfss	STATUS,Z
	nop
	call	ReadAByte
	btfss	STATUS,Z
	nop
	call	ReadAByte		; should run out of data here
	btfsc	STATUS,Z
	nop

	; now let's fill the buffer up and make sure he detects it

fillbuffer:
	movlw	'X'
	call	WriteAByte
	btfsc	STATUS,C		; if carry set, he had room
	goto	fillbuffer
	nop

	; drain the buffer and make sure he finds the end

drainbuffer:
	call	ReadAByte
	btfss	STATUS,Z		; uses Z to indicate I got a byte back
	goto	drainbuffer
	nop

	movlw	'A'
	call	WriteAByte

	endif		; end of my unit test code
	return


;*******************************************************************************
; SendHexByte -- take a byte and send it as two hex digits
;
; Sends a byte as two hex characters.  If you call here with W holding 0x3b,
; this routine will send "3B"
;*******************************************************************************
	global	SendHexByte
SendHexByte:
	movwf	hexbyte_to_send   ; save him for now
	movlw	"$"
	call	SendByte
	; send the high nibble
	swapf	hexbyte_to_send,0 ; load it back swapping the nibbles
	call	SendHexNibble     ; send the high nibble, which is now in the low nibble
  
  ; send the low nibble
	movf	hexbyte_to_send,0 ; reload w with full byte
	call	SendHexNibble     ; send the low nibble
	return
  
;*******************************************************************************
; SendHexNibble -- take a byte and send low nibble as a hex digit
;
; Maps the bottom four bits to a character 0-9,A-F
;*******************************************************************************
SendHexNibble:
	andlw 0x0f                ; clear all the high bits
	movwf hexnibble_to_send   ; save the value
	movlw 0x0a
	subwf hexnibble_to_send,0 ; check for above or below 0x0a
	movlw 0x30                ; I don't need the computed value, just the DC status bit
	btfsc STATUS,DC           ; if a borrow occurred, send letter instead of digit
	movlw 0x37                ; 0x0a + 0x37 = 0x41 = 'A'  :)
	addwf hexnibble_to_send,0 ; 0x00 + 0x30 = 0x30 = '0'
	call  SendByte           ; send my calculated value
	return

	page

;*******************************************************************************
;	SendByte - Queue up a byte for transmission
;
; If the transmitter is empty, and I'm here, it means that interrupts are off.
; To get them started again, I write the byte directly to the transmit
; register.  In all cases, I make sure the transmit interrupt is back on as 
; I leave.
;
;	Parameter: Byte to send is passed in 'W' register
;
;	RETURNED FLAG!  C=1, byte stored
;					C=0, buffer overrun
;*******************************************************************************

	global	SendByte
SendByte:
	Banksel	Bank3
	btfsc	TXSTA,TRMT		; is the transmitter empty?
	goto	primethepump

	Banksel	TXBank
	call	WriteAByte		; add character to the queue
	goto	send_exit		; get out

primethepump:
	movwf	TXREG			; write directly to the transmitter to get him going

send_exit:
	Banksel	PIE1
	bsf		PIE1,TXIE		; turn on interrupts if the transmitter was empty
	BankSel	Bank0
	return

	page
;*******************************************************************************
;	ReadByte - Read the next byte received over the UART
;
; If there is one, if not returns with Z set, as in "Zero bytes returned"
;
;	Returned value in W, byte received
;	RETURNED FLAG!  Z=1, no byte returned
;					Z=0, byte returned
;*******************************************************************************

	global	ReadByte
ReadByte:
	Banksel	RXBank
	call	ReadAByte
	Banksel	Bank0
	return


	page
;*******************************************************************************
;	UART_RX -- Accept a byte from the UART
;*******************************************************************************

	global	UART_RX
UART_RX
	Banksel	PIE1
	bcf		PIE1,RCIE		; turn off RX interrupts

	Banksel	Bank3			; get access to the UART registers
	movfw	RCREG			; load the byte he has

	Banksel	RXBank			; select my ring buffer
	call	WriteAByte		; save it in my ring buffer

	Banksel PIE1
	bsf		PIE1,RCIE		; enable interrupts
	return


	page
;*******************************************************************************
;	UART_TX -- Feed the UART the next byte, if there is one
;
;	Select the buffer memory for transmit, which is in the same bank as the 
;	UART file registers, use ReadAByte to pull the next one, and if I get
;	one, write it into TXREG for transmission.
;*******************************************************************************

	global	UART_TX
UART_TX
	Banksel	TXBank
	bcf		PIE1,TXIE		; turn off interrupts from transmit

	Banksel	TXBank
	call	ReadAByte		; read the next byte
	btfsc	STATUS,Z		; if Z is set, no data came back
	goto	tx_exit
	
	Banksel	Bank3
	movwf	TXREG			; write it out

tx_exit:
	Banksel	PIE1
	btfss	STATUS,Z		; don't turn on interrupts if I don't have more data
	bsf		PIE1,TXIE		; let interrupts fly again
	return

	page

;*******************************************************************************
;	ReadAByte - Reads the next byte from the buffer
;
; Check the Z flag in STATUS to see if you got something back.
;
;	1. Make sure there is a byte waiting
;	2. Setup in the indirect registers
;	3. Increment the read pointer
;	4. Read the byte
;	5. Return the byte in W
;
;	RETURNED FLAG!  Z=1, no byte returned
;					Z=0, byte returned
;*******************************************************************************

ReadAByte:

; first, check if I have more data to send

	movfw	read_ptr		; (1) Make sure there is a byte to send
	subwf	write_ptr,W
	btfsc	STATUS,Z		; if I got zero, they match, no more data in buffer
	goto	readabyte_exit2

	movfw	FSR0L			; save indirect pointer
	movwf	read_save_fsrl
	movfw	FSR0H
	movwf	read_save_fsrh

	movfw	read_ptr		; (2) calculate the address I'm reading from
	addlw	low buffer
	movwf	FSR0L
	movfw	BSR				; caller set the right bank, so use it
	movwf	FSR0H

	rlf		FSR0L,F			; get the bits right
	rrf		FSR0H,F
	rrf		FSR0L,F

	movfw	read_ptr		; (3) bump the read pointer
	addlw	1
	movwf	read_ptr		; assume it is all good
	sublw	BUFF_SIZE
	btfss	STATUS,Z		; zero means we've gone off the end
	goto	readabyte_exit	; just get out

	clrf	read_ptr

readabyte_exit:
	movfw	INDF0			; (4) read the next byte to go out
	movwf	temp_read		; stash it for usec

	movfw	read_save_fsrl	; restore indirect pointer register
	movwf	FSR0L
	movfw	read_save_fsrh
	movwf	FSR0H

	movfw	temp_read		; (5) return byte value in W
	bcf		STATUS,Z		; tell caller he has data

readabyte_exit2:
	return

	page

;*******************************************************************************
;	WriteAByte - 
;
; Call me with the byte in W and the correct memory bank selected for the buffer
;
;	1. Stash the byte for second
;	2. Setup in the indirect registers
;	3. Poke the byte into the buffer
;	4. Calculate the new write pointer
;	5. Check for buffer overrun
;	6. Save off the new write pointer
;
;	RETURNED FLAG!  C=1, byte stored
;					C=0, buffer overrun
;*******************************************************************************

WriteAByte:

	movwf	temp_write		; (1) stash my parameter

	movfw	FSR0L			; save indirect pointer
	movwf	write_save_fsrl
	movfw	FSR0H
	movwf	write_save_fsrh

	movfw	write_ptr		; (2) calculate the address I'm writing to
	addlw	low buffer
	movwf	FSR0L
	movfw	BSR				; caller set the right bank, so use it
	movwf	FSR0H

	rlf		FSR0L,F			; do the bit shuffle!
	rrf		FSR0H,F
	rrf		FSR0L,F

	movfw	temp_write		; (3) save my parameter
	movwf	INDF0			; points into my ring buffer

	movfw	write_ptr		; (4) bump the write pointer
	addlw	1
	movwf	write_ptr		; assume it is all good
	sublw	BUFF_SIZE		; but check if it isn't
	btfss	STATUS,Z		; zero means we've gone off the end
	goto	writeabyte_ovrtest

	clrf	write_ptr

writeabyte_ovrtest:
	movfw	write_ptr		; (5) check for buffer overrun
	subwf	read_ptr,W
	btfss	STATUS,Z		; carry will also be set
	goto	writeabyte_exit	; they aren't

	movlw	low buffer		; just go back to value I started with
	subwf	FSR0L,W
	andlw	0x7f			; drop the high bit
	movwf	write_ptr
	bcf		STATUS,C		; byte not stored
	goto	writeabyte_exit2

writeabyte_exit:
	bsf		STATUS,C
writeabyte_exit2:
	movfw	write_save_fsrl	; restore indirect pointer register
	movwf	FSR0L
	movfw	write_save_fsrh
	movwf	FSR0H

	return

	end