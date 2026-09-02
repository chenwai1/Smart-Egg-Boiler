;=============================================================================
; SMART EGG BOILER - CORE MINIMALIST VERSION
;=============================================================================
; FEATURES ENABLED: Mode Selection, Heating, DHT11 Humidity, Cooking, Abort (SW2)
; FEATURES REMOVED: 7-Segment, Buzzer, Countdown Timers, Completion Alerts
;=============================================================================
; PIN ASSIGNMENTS:
; P1.0-P1.7 : ADC0804 Data Input (DB0-DB7)
; P2.0      : DHT11 Data (Requires 10k Pull-up)
; P2.1      : Grove Vibration Sensor
; P2.2      : SW1 (Select/Confirm)
; P2.3      : SW2 (Stop/Abort)
; P2.4      : Relay Module
; P2.6      : Red LED (Active Low)
; P2.7      : Green LED (Active Low)
; P3.0/P3.1 : LCD I2C SDA/SCL
; P3.4      : ADC0804 INTR (Pin 5) - Interrupt Input
; P3.5/6/7  : ADC0804 WR / RD / CS
;=============================================================================

TM_CLK      BIT P0.0
TM_DIO      BIT P0.1
	
DHT_DATA    EQU P2.0        
VIBRATION   EQU P2.1        
BUTTON_SW1  EQU P2.2        
BUTTON_SW2  EQU P2.3        
RELAY       EQU P2.4 
BUZZER      EQU P2.5	
LED_RED     EQU P2.6        
LED_GREEN   EQU P2.7
	
I2C_SDA     EQU P3.0        
I2C_SCL     EQU P3.1  
ADC_INTR    EQU P3.4        ; ADC Pin 5	
ADC_WR      EQU P3.5        
ADC_RD      EQU P3.6        
ADC_CS      EQU P3.7        

MODE        EQU 30H         
ADC_VAL     EQU 31H         
HUM_VAL     EQU 33H         
LCD_BYTE    EQU 37H 
DIG1        EQU 42H             ; MM tens
DIG2        EQU 43H             ; MM ones
DIG3        EQU 44H             ; SS tens
DIG4        EQU 45H             ; SS ones	
TIME_MIN    EQU 46H
TIME_SEC    EQU 47H
SEC_FLAG    EQU 48H
INT_CNT     EQU 49H
VIB_SEC     EQU 4AH

;-----------------------------------------------------------------------------
; TM1637 COMMANDS
;-----------------------------------------------------------------------------
TM_CMD_WRITE    EQU 40H         ; write mode, auto-increment
TM_CMD_ADDR     EQU 0C0H        ; start address digit 0
TM_CMD_DISP_ON  EQU 8FH        ; display ON, brightness max
TM_CMD_DISP_OFF EQU 80H        ; display OFF


;=============================================================================
; MAIN SYSTEM BOOT
;=============================================================================
        ORG 0000H
        LJMP MAIN
		
		ORG 000BH
		LJMP TIMER0_ISR
        
        ORG 0030H

MAIN:
        CALL INIT_SYSTEM
        CALL LCD_INIT
		MOV TMOD,#01H; Timer 0 Mode 1

        MOV TH0,#3CH ;(3CB0H = 15536)65536-15536=50000; 50000*1us = 50ms; every 50ms overflow
        MOV TL0,#0B0H

        MOV INT_CNT,#14H;20(20*50ms=1s)
        MOV SEC_FLAG,#00H
		MOV VIB_SEC,#00H

        SETB ET0
        SETB EA

;=============================================================================
; STATE 1: MODE SELECTION
;=============================================================================
MENU_LOOP:
        CALL READ_ADC
        CALL EVALUATE_MODE
        CALL UPDATE_LCD_MENU
        
        JNB  BUTTON_SW1, CONFIRM_MODE
        SJMP MENU_LOOP

CONFIRM_MODE:
        CALL DEBOUNCE_SW1
        CALL LCD_CLEAR
        MOV  DPTR, #STR_CONFIRM
        CALL LCD_PRINT_LINE1
        CALL DELAY_500MS
        SJMP HEATING_PHASE

;=============================================================================
; STATE 2: HEATING PHASE & HUMIDITY DETECTION
;=============================================================================
HEATING_PHASE:
        CALL LCD_CLEAR
        MOV  DPTR, #STR_HEATING
		SETB TR0
        CALL LCD_PRINT_LINE1
        
        CLR  LED_RED             ; Turn ON Red LED (Active Low)
        SETB LED_GREEN           ; Ensure Green is OFF
        SETB RELAY               ; Turn ON Heater

HEAT_LOOP:
		JNB  BUTTON_SW2, DO_ABORT ; 1. Check Emergency Stop
        CALL READ_DHT11           ; 2. Read Humidity
        CALL DISPLAY_HUMIDITY     ; 3. Display Humidity on LCD Line 2
        JNB  VIBRATION, HEAT_WAIT ; 4. Check Vibration (Logic 0 = No vibration)
		
		INC VIB_SEC
		MOV A, VIB_SEC
		CJNE A,#10, HEAT_LOOP
        
        MOV  A, HUM_VAL           ; 5. Vibration detected for 5, check Humidity
        CJNE A, #32H, CHK_THRESH  ; Compare with 50H (70% Decimal) C=1 when A<70, C=0 when A>70
        SJMP COOKING_PHASE        ; Exact match
		
CHK_THRESH:
        JNC  COOKING_PHASE        ; Humidity > 70%, move to cooking
		SJMP HEAT_WAIT
		
HEAT_WAIT:
        CALL DELAY_20MS          ; Wait before next reading
        SJMP HEAT_LOOP

DO_ABORT:
        LJMP ABORT_PROCESS

;=============================================================================
; STATE 3: COOKING PHASE
;=============================================================================
COOKING_PHASE:
        CALL LCD_CLEAR
        MOV  DPTR, #STR_COOKING
        CALL LCD_PRINT_LINE1
        MOV  DPTR, #STR_BLANK     ; Clear the humidity line
        CALL LCD_PRINT_LINE2
		
		MOV A,MODE

        CJNE A,#01H,CHECK_MED

        ; Soft
        MOV TIME_MIN,#00H
        MOV TIME_SEC,#10H
        SJMP TIME_READY

CHECK_MED:

        CJNE A,#02H,CHECK_HARD

        ; Medium
        MOV TIME_MIN,#01H
        MOV TIME_SEC,#00H
        SJMP TIME_READY

CHECK_HARD:

        ; Hard
        MOV TIME_MIN,#12H
        MOV TIME_SEC,#00H

TIME_READY:

		MOV INT_CNT,#14H;Redefine INT_CNT = 20 *20 more interrupts then sec_flag becomes 1
        MOV SEC_FLAG,#00H;Clear the flag

COOK_LOOP:

		CALL TM1637_SHOW
		
        JNB  BUTTON_SW2, DO_ABORT ; Check Emergency Stop
		
		MOV A,TIME_MIN
        JNZ WAIT_SEC

        MOV A,TIME_SEC
        JZ COUNT_DONE

WAIT_SEC:

        MOV A,SEC_FLAG ;wait sec_flag becomes 1
        JZ COOK_LOOP

        MOV SEC_FLAG,#00H

        MOV A,TIME_SEC ;if second is not 0, decrease time second
        JZ DEC_MIN ;if second is 0, decrease time minute

        DEC TIME_SEC
        SJMP COOK_LOOP

DEC_MIN:

        DEC TIME_MIN; min decrease 1 and second add from 0 to 59
        MOV TIME_SEC,#59
        SJMP COOK_LOOP
		
COUNT_DONE:
        CLR TR0
        CLR RELAY

        SETB LED_RED
        CLR LED_GREEN

        CALL LCD_CLEAR
        MOV DPTR,#STR_READY
        CALL LCD_PRINT_LINE1
        MOV DPTR,#STR_BLANK
        CALL LCD_PRINT_LINE2

        CALL PLAY_MELODY
		CALL PLAY_MELODY

DONE_LOOP:
        JNB BUTTON_SW2,DONE_PRESSED ; Wait for the user to press the Stop button(polling)
        SJMP DONE_LOOP

DONE_PRESSED:
        CALL DELAY_20MS            ; Button debounce delay
        JNB BUTTON_SW2,RETURN_MENU
        SJMP DONE_LOOP

RETURN_MENU:
		CALL TM1637_OFF
        LJMP MAIN                  ; Return to the main menu

;=============================================================================
; ABORT ROUTINE
;=============================================================================
ABORT_PROCESS:
        MOV  SP, #07H            ; Clear stack pointer *since there are too many stacks after running the code, 
		;this sp tells the cpu to stack from 08H, WHILE 09H AND MORE DATA DIDNT GET COVERED
        CLR  RELAY               ; Turn OFF Heater
        SETB LED_RED             ; Turn OFF Red LED
        
        CALL LCD_CLEAR
        MOV  DPTR, #STR_STOPPED
        CALL LCD_PRINT_LINE1
        
		CLR TR0
        MOV SEC_FLAG,#00H
        MOV INT_CNT,#14H
		
		MOV TIME_MIN,#00H
        MOV TIME_SEC,#00H
        CALL TM1637_SHOW
		
        CALL DELAY_500MS
		CALL TM1637_OFF
        LJMP MAIN

;=============================================================================
; ADC0804 DRIVER (DELAY BASED - NO INTERRUPTS)
;=============================================================================
READ_ADC:

        MOV P1,#0FFH

        CLR ADC_CS; wanna talk with adc
        CLR ADC_WR
        NOP
        SETB ADC_WR; low to high: start the conversion

        MOV R6,#100

WAIT_ADC:
        JNB ADC_INTR,ADC_READY 
        DJNZ R6,WAIT_ADC

        SETB ADC_CS
        RET

ADC_READY:
        CLR ADC_RD
        MOV A,P1
        MOV ADC_VAL,A
        SETB ADC_RD
        SETB ADC_CS
        RET

EVALUATE_MODE:
        MOV  A, ADC_VAL
        CJNE A, #55H, EV_M1
        SJMP ST_S
EV_M1:  JC   ST_S
        CJNE A, #90H, EV_M2
        SJMP ST_M
EV_M2:  JC   ST_M
        SJMP ST_H
ST_S:   MOV MODE, #01H; 
		RET
ST_M:   MOV MODE, #02H; 
		RET
ST_H:   MOV MODE, #03H; 
		RET

UPDATE_LCD_MENU:
        MOV  A, MODE
        CJNE A, #01H, CH_M2
        MOV  DPTR, #STR_SOFT;string str_soft move to dptr
        CALL LCD_PRINT_LINE1
        SJMP MENU_BOT
CH_M2:  CJNE A, #02H, SET_H2
        MOV  DPTR, #STR_MED
        CALL LCD_PRINT_LINE1
        SJMP MENU_BOT
SET_H2: MOV  DPTR, #STR_HARD
        CALL LCD_PRINT_LINE1
MENU_BOT:
        RET

;=============================================================================
; DHT11 DRIVER 
;=============================================================================
READ_DHT11:

        CLR  DHT_DATA ; DHT11 before reading data, the signal is required to be low for 18ms (this is for mcu calling)
        CALL DELAY_20MS
        SETB DHT_DATA; After MCU calling, DHT will answer for 80us low, 80us high, and MCU will wait for 40us
		CALL DELAY_40US
		
        MOV R6,#255
		
W_ST:   JNB  DHT_DATA, DHT_ALV; if 1, means DHT no answer, move to next line
		DJNZ R6,W_ST

		RET

DHT_ALV:
		MOV R6,#255

WAIT_LOW_END:
        JB DHT_DATA,LOW_DONE; if 1, means DHT finish answering for first 80us, this is response signal
        DJNZ R6,WAIT_LOW_END
        RET

LOW_DONE:
        MOV R6,#255

WAIT_HIGH_END:
        JNB DHT_DATA,HIGH_DONE; if 0, means DHT finish answering for last 80us, this is response signal
        DJNZ R6,WAIT_HIGH_END
        RET

;After response signal, DHT starts to send 40 bits (data byte)
HIGH_DONE:
        CALL READ_BYTE; Humidity Integer
		MOV HUM_VAL, A
        CALL READ_BYTE; Humidity Decimal
        CALL READ_BYTE; Temperature Integer
        CALL READ_BYTE; Temperature Decimal
        CALL READ_BYTE; Checksum
        RET

READ_BYTE:
        MOV  R2, #08H
        MOV  A, #00H
;wait 50us low + 26us high for 0, wait 50us low + 70us high for 1
R_BIT:  JNB  DHT_DATA, $ ;wait 50us here until becomes high
        CALL DELAY_40US ;if 0, 26us < 40us; if1, 70us >40us
        MOV  C, DHT_DATA ; data put into carry
        RLC  A 
        JB   DHT_DATA, $ ; wait til dht goes back to low
        DJNZ R2, R_BIT ;read 8 bits, decrease 8 times
        RET

;=============================================================================
; LCD I2C DRIVERS & DISPLAY SUBROUTINES
;=============================================================================
DISPLAY_HUMIDITY:
        MOV  A, #0C0H            ; Move cursor to Line 2
        CALL LCD_CMD
        MOV  DPTR, #STR_HUM
        CALL LCD_STRING
        
        MOV  A, HUM_VAL ; ex: if A=65, after division with 0AH(10), A=6 B=5
        MOV  B, #0AH
        DIV  AB
        ADD  A, #30H; 6+30=36H,which is 6 in ACSII
		CALL LCD_DATA ;display tens place
        MOV  A, B
        ADD  A, #30H
		CALL LCD_DATA; display ones place
       
        MOV  A, #'%'; 
		CALL LCD_DATA
        MOV  A, #' '; for the case 100% becomes 99%
		CALL LCD_DATA
        MOV  A, #' '; 
		CALL LCD_DATA
        RET

;PCF8574 I2C default setting
LCD_INIT:
        CALL DELAY_20MS
        MOV  A, #30H; send 0011, set to 8 bit mode(30H= 0011 0000, ltr in RST need to ANL, so is 0011)
		CALL LCD_RST; 
		CALL DELAY_2MS
        MOV  A, #30H; 
		CALL LCD_RST; 
		CALL DELAY_2MS
        MOV  A, #30H; confirm trice
		CALL LCD_RST 
        MOV  A, #20H; change to 4 bit mode
		CALL LCD_RST
        MOV  A, #28H; 0010 1000 (4 bit mode, 2lines, 5x8 font)
		CALL LCD_CMD
        MOV  A, #0CH; 0000 1100 (Display ON, Cursor OFF, Blink OFF)
		CALL LCD_CMD
        MOV  A, #06H; 0000 0110 (Cursor move to right each time of key in)
		CALL LCD_CMD
        MOV  A, #01H; 0000 0001 (Clear display)
		CALL LCD_CMD
        CALL DELAY_20MS
        RET

LCD_CLEAR:       
		MOV A, #01H; 
		CALL LCD_CMD; 
		CALL DELAY_20MS; 
		RET
		
LCD_PRINT_LINE1: 
		MOV A, #80H; 
		CALL LCD_CMD; 
		CALL LCD_STRING; 
		RET
		
LCD_PRINT_LINE2: 
		MOV A, #0C0H; 
		CALL LCD_CMD; 
		CALL LCD_STRING; 
		RET

LCD_STRING:      
		CLR A; start from 0
		MOVC A, @A+DPTR; dptr is used for alphabets and symbols in this case
		JZ L_END; check if the value in the address is 0, 0 then jump to l_end and return
		CALL LCD_DATA; 
		INC DPTR; 
		SJMP LCD_STRING
		L_END:           
		RET

LCD_CMD:;give order         
		MOV LCD_BYTE, A; 80H
		ANL A, #0F0H; high 4 bit is involeved in comparison with #80H as #0FFH is 1111 0000 *becomes 1000 0000B
		ORL A, #08H; becomes 88H (last bit is always 0(RS=0) *juz to distinguish between command/output.)
		CALL LCD_WR; 
		MOV A, LCD_BYTE; 
		SWAP A; 
		ANL A, #0F0H; 
		ORL A, #08H; LCD is 4bit mode so need to send twice
		CALL LCD_WR; 
		RET
		
LCD_DATA:;give data
		MOV LCD_BYTE, A; 00H
		ANL A, #0F0H; 
		ORL A, #09H; last bit is 1 (RS=1) 
		CALL LCD_WR; 
		MOV A, LCD_BYTE; 
		SWAP A; 
		ANL A, #0F0H; 
		ORL A, #09H; 
		CALL LCD_WR; 
		RET

;RS 0 MEANS COMMAND
LCD_WR:          
		MOV R4, A; R4 becomes 88H 1000 1000B
		CALL I2C_START; 
		MOV A, #4EH; PCF8574 I2C Address * wanna talk with lcd I2C module * 
		CALL I2C_SEND; 
		MOV A, R4; A back to original value
		ORL A, #04H; A becomes 08CH=1000 1100B when A=88H at previous steps *data is 1000, while 1100 is BL,EN,RW,RS respectively - 4 bit lcd is used*
		CALL I2C_SEND; 
		CALL DELAY_5US; 
		MOV A, R4; Back to original value
		ANL A, #0FBH; A becomes 88H=1000 1000B when A=88H at previous steps *data is 1000, while 1000 is BL,EN,RW,RS respectively - 4 bit lcd is used*
		CALL I2C_SEND; 
		CALL DELAY_2MS; 
		CALL I2C_STOP; 
		RET
		
LCD_RST:         
		ANL A, #0F0H; 
		ORL A, #08H; 
		CALL LCD_WR; 
		RET

I2C_START:      
		SETB I2C_SDA; 
		SETB I2C_SCL; 
		CALL DELAY_5US; 
		CLR I2C_SDA; 
		CALL DELAY_5US; 
		CLR I2C_SCL; 
		RET
		
I2C_STOP:        
		CLR I2C_SDA; 
		SETB I2C_SCL; 
		CALL DELAY_5US; 
		SETB I2C_SDA; 
		CALL DELAY_5US; 
		RET

I2C_SEND:        
		MOV R3, #08H; If A is 08CH = 1000 1100B
		
I2C_LP: RLC A; bit7 move to C, and the original value in C will move to bit0, so it becomes 0001 1000B = 18H
		MOV I2C_SDA, C; 1 *the loop will cause the sequence of C becomes 1 0 0 0 1 1 0 0, which is same as 8CH
		SETB I2C_SCL; When SCL is high, read SDA
		CALL DELAY_5US; 
		CLR I2C_SCL; complete 1 bit
		DJNZ R3, I2C_LP; decrease 1 from R3, loop until become 0
		SETB I2C_SDA; 
		SETB I2C_SCL; 
		CALL DELAY_5US; 
		CLR I2C_SCL; 
		RET

;=============================================================================
; TM1637_SHOW
; Sends current TIME_MIN and TIME_SEC to TM1637 as MM:SS
;
; TRANSACTION SEQUENCE:
; [1] START ? 0x40 ? STOP         set auto-increment write mode
; [2] START ? 0xC0 ? D0 D1 D2 D3 ? STOP   send 4 digit bytes
; [3] START ? 0x8F ? STOP         display ON max brightness
;
; Digit 1 (MM ones) has ORL #80H to turn colon ON
;=============================================================================
TM1637_SHOW:
        ; Split minutes into tens and ones
        MOV  A, TIME_MIN
        MOV  B, #0AH
        DIV  AB
        MOV  DIG1, A
        MOV  DIG2, B

        ; Split seconds into tens and ones
        MOV  A, TIME_SEC
        MOV  B, #0AH
        DIV  AB
        MOV  DIG3, A
        MOV  DIG4, B

        ; Transaction 1: set write mode
        CALL TM_START
        MOV  A, #TM_CMD_WRITE
        CALL TM_SEND_BYTE
        CALL TM_STOP

        ; Transaction 2: send digit data
        CALL TM_START
        MOV  A, #TM_CMD_ADDR
        CALL TM_SEND_BYTE

        MOV  DPTR, #SEG_TABLE   ; digit 0: MM tens
        MOV  A, DIG1
        MOVC A, @A+DPTR
        CALL TM_SEND_BYTE

        MOV  DPTR, #SEG_TABLE   ; digit 1: MM ones + colon
        MOV  A, DIG2
        MOVC A, @A+DPTR
        ORL  A, #80H            ; bit7 = colon ON
        CALL TM_SEND_BYTE

        MOV  DPTR, #SEG_TABLE   ; digit 2: SS tens
        MOV  A, DIG3
        MOVC A, @A+DPTR
        CALL TM_SEND_BYTE

        MOV  DPTR, #SEG_TABLE   ; digit 3: SS ones
        MOV  A, DIG4
        MOVC A, @A+DPTR
        CALL TM_SEND_BYTE

        CALL TM_STOP

        ; Transaction 3: display ON
        CALL TM_START
        MOV  A, #TM_CMD_DISP_ON
        CALL TM_SEND_BYTE
        CALL TM_STOP
        RET

;=============================================================================
; TM_START   Start condition: DIO falls while CLK is HIGH
;=============================================================================
TM_START:
        SETB TM_DIO
        CALL TM_BUS_DELAY
        SETB TM_CLK
        CALL TM_BUS_DELAY
        CLR  TM_DIO             ; DIO falls while CLK HIGH = START
        CALL TM_BUS_DELAY
        CLR  TM_CLK
        CALL TM_BUS_DELAY
        RET

;=============================================================================
; TM_STOP   Stop condition: DIO rises while CLK is HIGH
;=============================================================================
TM_STOP:
        CLR  TM_DIO
        CALL TM_BUS_DELAY
        SETB TM_CLK
        CALL TM_BUS_DELAY
        SETB TM_DIO             ; DIO rises while CLK HIGH = STOP
        CALL TM_BUS_DELAY
        RET

;=============================================================================
; TM_SEND_BYTE   Send 8 bits LSB first, then receive ACK
; Uses R0 as bit counter (safe   delay routines use R3-R7)
;=============================================================================
TM_SEND_BYTE:
        MOV  R0, #08H
TM_LP:  CLR  TM_CLK
        CALL TM_BUS_DELAY
        RRC  A                  ; LSB ? Carry
        MOV  TM_DIO, C
        CALL TM_BUS_DELAY
        SETB TM_CLK
        CALL TM_BUS_DELAY
        DJNZ R0, TM_LP
        ; ACK cycle
        CLR  TM_CLK
        CALL TM_BUS_DELAY
        SETB TM_DIO             ; release DIO for ACK
        CALL TM_BUS_DELAY
        SETB TM_CLK
        CALL TM_BUS_DELAY
        CLR  TM_CLK
        CALL TM_BUS_DELAY
        RET

;=============================================================================
; TM_BUS_DELAY   8x NOP = ~8us per state change
;=============================================================================
TM_BUS_DELAY:
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        NOP
        RET

;=============================================================================
; TM_OFF 
;=============================================================================
TM1637_OFF:
        CALL TM_START
        MOV  A,#TM_CMD_DISP_OFF
        CALL TM_SEND_BYTE
        CALL TM_STOP
        RET
		
;=============================================================================
; PLAY_MELODY: Beethoven's "Ode to Joy"
; Method: Lookup Table Music Player
;=============================================================================
PLAY_MELODY:
MOV  R3, #00H      ; R3 acts as the music data index

READ_NOTE:
;-------------------------------------------------------------
; 1. Read the note pitch from the lookup table
;-------------------------------------------------------------
MOV  A, R3
MOV  DPTR, #MUSIC_DATA
MOVC A, @A+DPTR
JZ   MELODY_END    ; 00H indicates the end of the melody
MOV  R7, A         ; Save pitch value


    INC  R3            ; Move to the duration entry

    ;-------------------------------------------------------------
    ; 2. Read the note duration
    ;-------------------------------------------------------------
    MOV  A, R3
    MOV  DPTR, #MUSIC_DATA
    MOVC A, @A+DPTR
    MOV  R6, A         ; Save duration value

    INC  R3            ; Move to the next note pair

    ;-------------------------------------------------------------
    ; 3. Play the current note
    ;-------------------------------------------------------------


PLAY_CURRENT:
MOV  R4, #120      ; Base timing loop

TOGGLE_BEEP:
CPL  BUZZER
MOV A,R7
MOV R5,A

PITCH_DELAY:
DJNZ R5, PITCH_DELAY
DJNZ R4, TOGGLE_BEEP
DJNZ R6, PLAY_CURRENT


    ;-------------------------------------------------------------
    ; 4. Short pause between notes for articulation
    ;-------------------------------------------------------------
    CLR  BUZZER
    CALL DELAY_20MS

    SJMP READ_NOTE


MELODY_END:
CLR  BUZZER        ; Ensure the buzzer is turned off
CALL DELAY_200MS
RET

;=============================================================================
; MUSIC DATA TABLE
; Format:
;     DB Pitch, Duration
;
; Smaller pitch values produce higher tones.
; Larger duration values produce longer notes.
;
; Reference pitches:
;     C = 60H
;     D = 55H
;     E = 4CH
;     F = 48H
;     G = 40H
;
; Reference durations:
;     Quarter note      = 04H
;     Half note         = 02H
;     Dotted quarter    = 06H
;     Half note (long)  = 08H
;=============================================================================
MUSIC_DATA:

    ; Phrase 1: E E F G
    DB 4CH,04H, 4CH,04H, 48H,04H, 40H,04H

    ; Phrase 2: G F E D
    DB 40H,04H, 48H,04H, 4CH,04H, 55H,04H

    ; Phrase 3: C C D E
    DB 60H,04H, 60H,04H, 55H,04H, 4CH,04H

    ; Phrase 4: E (long), D (short), D (long)
    DB 4CH,06H, 55H,02H, 55H,08H

    ; End marker
    DB 00H,00H


;=============================================================================
; SYSTEM UTILITIES & DELAYS
;=============================================================================
INIT_SYSTEM:
        SETB DHT_DATA; 
		SETB VIBRATION; 
		SETB BUTTON_SW1; 
		SETB BUTTON_SW2
        CLR  RELAY; 
		SETB LED_RED; 
		SETB LED_GREEN
		
        SETB I2C_SDA; 
		SETB I2C_SCL; 
		SETB ADC_CS; 
		SETB ADC_RD; 
		SETB ADC_WR
		
        MOV  P1, #0FFH
        RET

DEBOUNCE_SW1:
        CALL DELAY_20MS
        JNB  BUTTON_SW1, $
        CALL DELAY_20MS
        RET

DELAY_5US:   
		NOP; 
		NOP; 
		RET
		
DELAY_40US:
        MOV R7,#18
D40:
        DJNZ R7,D40
        RET
		
DELAY_2MS:   
		MOV R6, #0AH; 
		D2_L: MOV R7, #0FFH; 
		DJNZ R7, $; 
		DJNZ R6, D2_L; 
		RET
		
DELAY_20MS:  MOV R5, #14H; 
		D20_L: CALL DELAY_2MS; 
		DJNZ R5, D20_L; 
		RET
		
DELAY_500MS: MOV R4, #19H; 
		D500_L: CALL DELAY_20MS; 
		DJNZ R4, D500_L; 
		RET
		
DELAY_100MS:
        MOV  R2, #05H
D100_L: CALL DELAY_20MS
        DJNZ R2, D100_L
        RET

DELAY_200MS:
        CALL DELAY_100MS
        CALL DELAY_100MS
        RET
		
;=============================================================================
; STRINGS
;=============================================================================
STR_SOFT:    DB '> SOFT  BOILED ', 0 ; if no '', db 0 means address 00H
STR_MED:     DB '> MEDIUM BOILED', 0
STR_HARD:    DB '> HARD  BOILED ', 0
STR_CONFIRM: DB 'Mode Confirmed! ', 0
STR_HEATING: DB 'Heating...      ', 0
STR_HUM:     DB 'Hum: ', 0
STR_COOKING: DB 'Cooking...      ', 0
STR_BLANK:   DB '                ', 0
STR_STOPPED: DB 'Process Stopped!', 0
STR_READY: DB 'Egg is Ready!   ',0

;=============================================================================
; 7-SEGMENT ENCODING TABLE (common cathode)
; bit0=a, bit1=b, bit2=c, bit3=d, bit4=e, bit5=f, bit6=g, bit7=colon
;=============================================================================
SEG_TABLE:
        DB 3FH  ; 0
        DB 06H  ; 1
        DB 5BH  ; 2
        DB 4FH  ; 3
        DB 66H  ; 4
        DB 6DH  ; 5
        DB 7DH  ; 6
        DB 07H  ; 7
        DB 7FH  ; 8
        DB 6FH  ; 9

;=============================================================================
; TIMER 0 ISR   fires every 50ms
; Reloads timer, counts 20 interrupts, sets SEC_FLAG on 1 second
;=============================================================================
TIMER0_ISR:

        MOV TH0,#3CH; Reload timer immediately for next 50ms period
        MOV TL0,#0B0H

        DJNZ INT_CNT,EXIT_ISR; Decrement interrupt counter

		; 20 interrupts done = 1 second elapsed
        MOV INT_CNT,#14H; reset counter (14H = 20 decimal)
        MOV SEC_FLAG,#01H; signal main loop: 1 second passed

EXIT_ISR:
        RETI

        END
