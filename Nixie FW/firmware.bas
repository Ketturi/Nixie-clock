'Firmware for Ketturi Electronics Nixie clock
'Version 1.3
'
'ATmega16A, 16 MHz external crystal, Low Fuse:0x3E, High Fuse 0xD9
'RTC: DS1307
'
'Henri Keinonen 2012-2013
'Thanks to vsaar for help :-)



'********************
'* Initial settings *
'********************
'*******************************************************************************
$regfile = "m16def.dat"                                     ' specify the used micro
$crystal = 16000000                                         ' used crystal frequency
$hwstack = 32                                               ' default use 32 for the hardware stack
$swstack = 10                                               ' default use 10 for the SW stack
$framesize = 40                                             ' default use 40 for the frame space

'***** Declare subprograms
Declare Sub Nixie_write
Declare Sub Nixie_roll
Declare Sub Alarm
Declare Sub Almtune_restore
Declare Sub Switch_read
Declare Sub Rtc_read
Declare Sub Rtc_write_hr
Declare Sub Rtc_write_minsec
Declare Sub Rtc_write_setting


'****** Set i/o ports
 Ddra = &B00000011                                          'Set Port As Input / Output
 Porta = &B11111111                                         'Enable input pull-ups, 1=on

 Ddrb = &B10000011

 Ddrc = &B00000100
 Portc = &B11111000

 Ddrd = &B00100100


'****** Define variables
Dim Bcdsec As Byte                                          'BCD Seconds
Dim Bcdmin As Byte                                          'BCD Minutes
Dim Bcdhr As Byte                                           'BCD Hours
Dim Decsec As Byte , Decsec2 As Byte                        'Decimal seconds & temp minutes
Dim Decmin As Byte , Decmin2 As Byte                        'Decimal minutes & temp minutes
Dim Dechr As Byte
Dim Nixmin As Byte                                          'To be written to minutes nixie
Dim Nixhr As Byte                                           'To be written to hours nixie

Dim Tmp1 As Byte : Dim Tmp2 As Byte                         'For temporal use only

Dim Blinkyglim As Bit                                       'Blinking glim lights
Dim Blinkhm As Byte                                         'bit 0=1min, 1=10min, 2=1h, 3=10h for nixies,5= Alarm_led,freq: 6= 1Hz, 7= 2Hz

Dim Mainmode As Byte
Dim Countr As Byte

Dim T1count As Word , Nfreq As Word , Nlen As Integer       'Alarm buzzer things
Dim T1countd As Dword
Dim Almtune As Byte : Almtune = 1                           'Selected alarm tune
Dim Almmin As Byte : Almmin = 0                             'Alarm minutes in decimal format
Dim Almhr As Byte : Almhr = 1                               'Alarm hours in decimal format
Dim Almon As Byte : Almon = 0                               'Alarm enabled
Dim Almon2 As Byte                                          'Alarm tune test
Dim Snzlen As Byte : Snzlen = 5                             'Snooze length
Dim Countasb As Byte : Countasb = 0                         'Astop button timeout counter (show time when dspoff)
Dim Selpos As Byte : Selpos = 1

'For nixie roll)
Dim Rollen As Byte : Rollen = 1                             'Nixie rolling interval, def. 5m
Dim Countrol As Byte : Countrol = Rollen + 1                'Rolling counter, mins to next roll
Dim Countrol2 As Byte : Countrol2 = 0                       'Rolling counter, 6/122
Dim Countrol3 As Byte : Countrol3 = 0                       'Rolling counter, 0-9 numbers
Dim Rolph As Byte : Rolph = 0                               'Rolling phase, 0=roll not in action
Dim Roll_order(10) As Byte                                  'Order of nixie numbers
Roll_order(1) = 1 : Roll_order(2) = 6
Roll_order(3) = 2 : Roll_order(4) = 7
Roll_order(5) = 5 : Roll_order(6) = 0
Roll_order(7) = 4 : Roll_order(8) = 9
Roll_order(9) = 8 : Roll_order(10) = 3
Const Rolphset = 2

'Buttons & switches
Dim Swdebr As Byte : Swdebr = 0                             'Rotary switch debounce counter
Dim Swdebb As Byte : Swdebb = 0                             'Pushbutton debounce counter
Dim Swrep As Byte : Swrep = 0                               'Switch repeat counter
Dim Swrs As Byte                                            'Rotary switches status (new)
Dim Swrs2 As Byte                                           'Rotary switches status (previous)
Dim Swpb As Byte                                            'Pushbuttons status (new)
Dim Swpb2 As Byte                                           'Pushbuttons status (previous)
Dim Swbut As Byte                                           'Pressed button



'****** Play some alias
Sw_snooze Alias Pinc.6                                      'Sw on when 1
Sw_alarm Alias Pinc.7                                       'Sw on when 0 for all but snooze
Sw_up Alias Pinc.3
Sw_dn Alias Pinc.5
Sw_select Alias Pinc.4

Upper_glim Alias Portb.1
Lower_glim Alias Portb.0
Alarm_led Alias Portc.2
Hv_power Alias Portd.2

Off_rty Alias Pina.7
Normal_rty Alias Pina.6
Alarm_set_rty Alias Pina.5
Setup_rty Alias Pina.4

Buzzer Alias Tccr1a.com1a1                                  'PWM controlled buzzer

Alarm_output Alias Pinb.7
Testpin Alias Porta.0

'****** I2C IC addresses
Const Rtcw = &HD0                                           'RTC write address
Const Rtcr = &HD1                                           'RTC read address
Const Nmin = &H42                                           'Nixie minutes address
Const Nhr = &H40                                            'Nixie hours address

'****** Config I2C bus
Config I2cdelay = 10
Config Scl = Portc.0
Config Sda = Portc.1
I2cinit
Waitms 10

'Set timer and interrupts, 16000000/256/256 = 244Hz interrupt rate
Config Timer0 = Timer , Prescale = 256
Enable Timer0
Enable Interrupts

'Set Timer1 & alarm buzzer
Tccr1a = Bits(wgm11)
Tccr1b = Bits(wgm12 , Wgm13 , Cs10)
Call Almtune_restore
'*******************************************************************************



'*******************
'* Boot & Selftest *
'*******************
'*******************************************************************************
Set Hv_power                                                'Enable nixie power supply

'***** Nixie testing
For Tmp1 = 0 To 9                                           'Rolls all digits
 Tmp2 = Tmp1 * 16
 Tmp2 = Tmp2 + Tmp1
  Nixhr = Tmp2 : Nixmin = Tmp2
 Call Nixie_write
Waitms 150
Next
 Nixhr = &HFF : Nixmin = &HFF
 Call Nixie_write

'Read RTC settings byte
I2cstart
 I2cwbyte Rtcw                                              'RTC write
 I2cwbyte &H08                                              'time&settings avail flag adr
I2cstop
I2cstart
 I2cwbyte Rtcr                                              'RTC read
 I2crbyte Tmp1 , Nack                                       '02 hr
I2cstop

'If settings present, read them
If Tmp1 = &H0F Then                                         'If d/t/s available, then...
  I2cstart
  I2cwbyte Rtcw                                             'RTC write
  I2cwbyte &H09                                             'h00 start adr
 I2cstop
 I2cstart                                                   'Read other settings from RTC
 I2cwbyte Rtcr                                              'RTC read
  I2crbyte Almhr , Ack                                      '09 Almhr
  I2crbyte Almmin , Ack                                     '0A Almmin
  I2crbyte Almtune , Ack                                    '0B Almtune
  I2crbyte Snzlen , Ack                                     '0C Snzlen
  I2crbyte Rollen , Nack                                    '0D Rollen
 I2cstop
'Date and time will be read when entering main program loop

'If no settings present, RTC cleared, set default time & data
Else                                                        'If d/t/s not available, then...
 I2cstart                                                   'Write default settings to RTC
  I2cwbyte Rtcw                                             'RTC write
  I2cwbyte &H00                                             'memory adr
  I2cwbyte 0                                                '00 Bcdsec
  I2cwbyte 0                                                '01 Bcdmin
  I2cwbyte 0                                                '02 Bcdhr
  I2cwbyte 7                                                '03 Wkday
  I2cwbyte &H01                                             '04 date (bcd)
  I2cwbyte &H01                                             '05 mon  (bcd)
  I2cwbyte &H12                                             '06 year (bcd)
  I2cwbyte &H00                                             '07 rtc mode setting
  I2cwbyte &H0F                                             '08 &h0F=user settings available
  I2cwbyte Almhr                                            '09 Almhr
  I2cwbyte Almmin                                           '0A Almmin
  I2cwbyte Almtune                                          '0B Almtune
  I2cwbyte Snzlen                                           '0C Snzlen
  I2cwbyte Rollen                                           '0D Rollen
 I2cstop

  Nixhr = &H88 : Nixmin = &H88
  Call Nixie_write
  Do
  Loop Until Sw_snooze = 1
  'Waitms 1500
End If

Waitms 300

'*******************************************************************************



'*********************
'* Main program loop *
'*********************
'*******************************************************************************
Do
Set Testpin
'Executed regardless of Mainmode
Incr Countr

Call Rtc_read
If Decsec2 <> Decsec Then                                   'if seconds changed
 Decsec2 = Decsec
 Countr = 0
 If Countasb > 0 Then Decr Countasb
 Call Nixie_write
End If

If Countr < 61 Then Set Blinkhm.7                           'Blinkhm.7 = 2Hz strobe
If Countr > 60 And Countr < 122 Then Reset Blinkhm.7
If Countr > 121 And Countr < 183 Then Set Blinkhm.7
If Countr > 182 Then Reset Blinkhm.7
If Countr < 122 Then Reset Blinkhm.6 Else Set Blinkhm.6     '1Hz strobe for glims

Call Switch_read


If Rolph > 0 Then                                           'increase Countrol2 if rolling is active
 Incr Countrol2
  If Mainmode <> 1 Then Rolph = 0
  If Countrol2 = 12 Then Call Nixie_roll
End If


If Decmin2 <> Decmin Then                                   'If minutes has been changed...
 Decmin2 = Decmin                                           'update Decmin2
 If Almon > 0 Then Decr Almon
 If Almhr = Dechr And Almmin = Decmin And Sw_alarm = 0 Then 'if alarm time matches...
  Almon = 1                                                 'set alarm on
  Call Almtune_restore
 End If

 If Mainmode = 1 And Almon <> 1 And Rollen > 0 Then         'check roll counter
  Decr Countrol
  If Countrol = 0 Then
   Countrol = Rollen : Countrol2 = 0 : Countrol3 = 0
   Rolph = Rolphset                                         'activate roll
  End If
 End If
End If


If Almon > 0 And Sw_alarm = 1 Then                          'stop alarm if Alm turned off (0=on)
 Almon = 0
 Reset Buzzer
End If

If Almon = 1 And Swbut.4 = 1 Then                           'stop alarm if snooze pressed
 Almon = Snzlen + 1
 Reset Buzzer
End If

If Almon = 1 Then Call Alarm                                'call for alarm tune

If Mainmode <> 3 And Almon2 = 1 Then                        'Resets tune test if mode changed
 Almon2 = 0 : Reset Buzzer
End If

If Mainmode <> 0 And Sw_alarm = 0 Or Countasb > 0 Then Set Alarm_led Else Reset Alarm_led

 If Almon > 0 Then
  If Blinkhm.6 = 0 Then
   Set Alarm_led
  Else
   Reset Alarm_led
  End If
 End If

 If Almon > 0 Then Set Alarm_output Else Reset Alarm_output  'Set alarm_output if alarm or snooze is on for external alarm device
 
'Mainmode 0 = dsp off, 1 = time, 2 = alm set, 3 = setup

'*****                      *****
'*  Mainmode 0 a.k.a Display off*
'*****                      *****
If Mainmode = 0 Then
 If Sw_snooze = 1 Or Almon = 1 Then
  Countasb = 5
  Set Hv_power
  If Sw_alarm = 0 Then
      Set Alarm_led
  End If
 End If

 If Countasb = 0 Then
   Reset Hv_power
   Reset Alarm_led
 End If
End If

'*****                              *****
'*  Mainmode 1 a.k.a Normal time display*
'*****                              *****
If Mainmode = 0 Or Mainmode = 1 Then
 Reset Blinkhm.0 : Reset Blinkhm.1
 Reset Blinkhm.2 : Reset Blinkhm.3

 If Rolph = 0 Then
  If Blinkhm.6 = 0 Then                                     'Blink glims 1Hz
   Set Upper_glim : Set Lower_glim
  Else
   Reset Upper_glim : Reset Lower_glim
  End If
 End If



 If Swbut.3 = 1 Then
   Countrol = Rollen : Countrol2 = 0 : Countrol3 = 0
   Rolph = Rolphset                                         'activate roll
 End If

 Nixhr = Makebcd(dechr) : Nixmin = Makebcd(decmin)          'Read and show time
 If Rolph = 0 Then Call Nixie_write :
End If

'*****                         *****
'*  Mainmode 2 a.k.a Alarm Time set*
'*****                         *****
If Mainmode = 2 Then
  Nixhr = Makebcd(almhr) : Nixmin = Makebcd(almmin)         'Convert and show alarm time
  Call Nixie_write
  Set Upper_glim : Set Lower_glim

 If Swbut.3 = 1 Then
  Incr Selpos                                               'Select between hrs and mins
  If Selpos > 2 Or Selpos = 0 Then Selpos = 1
 End If

 If Selpos = 1 Then                                         'hours selected
  Set Blinkhm.1 : Reset Blinkhm.0                           'Incr hrs when up pressed
  If Swbut.1 = 1 Then
   If Almhr = 23 Then Almhr = 0 Else Incr Almhr
   Call Rtc_write_setting
  End If
  If Swbut.2 = 1 Then
   If Almhr = 0 Then Almhr = 23 Else Decr Almhr             'Decrs hrs when down pressed
   Call Rtc_write_setting
  End If
 End If

 If Selpos = 2 Then                                         'minutes selected
  Set Blinkhm.0 : Reset Blinkhm.1
  If Swbut.1 = 1 Then                                       'Incrs mins when up pressed
   If Almmin = 59 Then Almmin = 0 Else Incr Almmin
   Call Rtc_write_setting
  End If
  If Swbut.2 = 1 Then                                       'Decrs mins when down pressed
   If Almmin = 0 Then Almmin = 59 Else Decr Almmin
   Call Rtc_write_setting
  End If
 End If

End If

'*****                        *****
'*  Mainmode 3 a.k.a Settings menu*
'*****                        *****
If Mainmode = 3 Then

 If Selpos < 3 Then
  Nixhr = Makebcd(dechr) : Nixmin = Makebcd(decmin)         'Convert and show alarm time
  Set Upper_glim : Set Lower_glim
 Else
  Nixhr = Selpos - 2                                        'Convert 0x to xF
  Nixhr = Nixhr * 16
  Nixhr = Nixhr + 15
  Reset Upper_glim : Reset Lower_glim
 End If

 Call Nixie_write

 If Swbut.3 = 1 Then
  Incr Selpos
  Almon2 = 0 : Reset Buzzer                                 'Select setting to be changed
  If Selpos > 5 Or Selpos = 0 Then Selpos = 1
 End If

'----Set hours
 If Selpos = 1 Then                                         'hours selected
  Set Blinkhm.1 : Reset Blinkhm.0                           'Incr hrs when up pressed
  If Swbut.1 = 1 Then
   If Dechr = 23 Then Dechr = 0 Else Incr Dechr
   Call Rtc_write_hr
  End If
  If Swbut.2 = 1 Then
   If Dechr = 0 Then Dechr = 23 Else Decr Dechr             'Decrs hrs when down pressed
   Call Rtc_write_hr
  End If
 End If

'----Set Minutes
 If Selpos = 2 Then                                         'minutes selected
  Set Blinkhm.0 : Reset Blinkhm.1
  If Swbut.1 = 1 Then                                       'Incrs mins when up pressed
   If Decmin = 59 Then Decmin = 0 Else Incr Decmin
   Decsec = 0 : Countr = 0
   Call Rtc_write_minsec
  End If
  If Swbut.2 = 1 Then                                       'Decrs mins when down pressed
   If Decmin = 0 Then Decmin = 59 Else Decr Decmin
    Decsec = 0 : Countr = 0
    Call Rtc_write_minsec
   End If
 End If

'----Set alarm tune
If Selpos = 3 Then
  Set Blinkhm.0 : Reset Blinkhm.1
  If Swbut.1 = 1 Then                                       'Incrs almtune when up pressed
   If Almtune = 6 Then Almtune = 1 Else Incr Almtune
   Almon2 = 0 : Reset Buzzer
   Call Rtc_write_setting
  End If
  If Swbut.2 = 1 Then                                       'Decrs almtune when down pressed
   If Almtune = 1 Then Almtune = 6 Else Decr Almtune
   Almon2 = 0 : Reset Buzzer
   Call Rtc_write_setting
  End If

  If Swbut.4 = 1 Then                                       'test play
   If Almon2 = 0 Then
    Almon2 = 1 : Call Almtune_restore
   Else
    Almon2 = 0 : Reset Buzzer
   End If
  End If

  Nixmin = &HF0 + Almtune                                   'convert 0x to Fx
  If Almon2 = 1 Then Call Alarm
 End If

'Set snooze length
If Selpos = 4 Then                                          '
  Set Blinkhm.0 : Reset Blinkhm.1
  If Swbut.1 = 1 Then                                       'Incrs snzlen when up pressed
   If Snzlen = 15 Then Snzlen = 3 Else Incr Snzlen
   Call Rtc_write_setting
  End If
  If Swbut.2 = 1 Then                                       'Decrs snzlen when down pressed
   If Snzlen = 3 Then Snzlen = 15 Else Decr Snzlen
   Call Rtc_write_setting
  End If
  If Snzlen < 10 Then Nixmin = &HF0 + Snzlen                'convert 0x to Fx
  If Snzlen > 9 Then Nixmin = Makebcd(snzlen)
 End If

'Set nixie roll interval
If Selpos = 5 Then
  Set Blinkhm.0 : Reset Blinkhm.1
  If Swbut.1 = 1 Then                                       'Incrs rollen when up pressed
   If Rollen < 10 Then Incr Rollen Else Rollen = Rollen + 5
   If Rollen > 60 Then Rollen = 0
   Countrol = Rollen
   Call Rtc_write_setting
  End If
  If Swbut.2 = 1 Then                                       'Decrs rollen when down pressed
   If Rollen = 0 Then Rollen = 65
   If Rollen > 10 Then Rollen = Rollen - 5 Else Decr Rollen
   Countrol = Rollen
   Call Rtc_write_setting
  End If
  If Rollen < 10 Then Nixmin = &HF0 + Rollen                'convert 0x to Fx
  If Rollen > 9 Then Nixmin = Makebcd(rollen)
 End If

End If

Reset Testpin
Idle                                                        'idle until next interrupt
Loop
End                                                         'end of main program loop
'*******************************************************************************

'****************
'* Sub programs *
'****************
'*******************************************************************************

'****Read & Write time,date & settings ****
'Read time and date
Sub Rtc_read
 I2cstart
  I2cwbyte Rtcw                                             'ds1307 write
  I2cwbyte &H00
 I2cstop
 I2cstart
  I2cwbyte Rtcr                                             'ds1307 read
  I2crbyte Bcdsec , Ack
  I2crbyte Bcdmin , Ack
  I2crbyte Bcdhr , Nack
 I2cstop
 Decsec = Makedec(bcdsec)
 Decmin = Makedec(bcdmin)
 Dechr = Makedec(bcdhr)                                     'convert from bcd to dec
End Sub

'Write hours into RTC
Sub Rtc_write_hr
 Bcdhr = Makebcd(dechr)
 I2cstart
  I2cwbyte Rtcw
  I2cwbyte &H02
  I2cwbyte Bcdhr
 I2cstop
End Sub

'Write min+sec into RTC
Sub Rtc_write_minsec
 Bcdsec = Makebcd(decsec)
 Bcdmin = Makebcd(decmin)                                   'convert dec to bcd

 I2cstart
  I2cwbyte Rtcw
  I2cwbyte &H00
   I2cwbyte Bcdsec
   I2cwbyte Bcdmin
 I2cstop
End Sub

'Write settings into RTC
Sub Rtc_write_setting

I2cstart
 I2cwbyte Rtcw
 I2cwbyte &H09
  I2cwbyte Almhr                                            '09 Almhr
  I2cwbyte Almmin                                           '0A Almmin
  I2cwbyte Almtune                                          '0B Almtune
  I2cwbyte Snzlen                                           '0C Snzlen
  I2cwbyte Rollen                                           '0D Rollen
 I2cstop
End Sub

'***** Nixie functions *****

'Wite to Nixie buffers
Sub Nixie_write

 If Blinkhm.7 = 1 And Swrep < 107 Then                      'Blink nixies
  If Blinkhm.0 = 1 Then Nixmin = &HFF
  If Blinkhm.1 = 1 Then Nixhr = &HFF
 End If

 I2csend Nhr , Nixhr                                        'Write hours
 I2csend Nmin , Nixmin                                      'Write minutes
End Sub


'Roll nixie numbers (Prevents cathode poisoning)
Sub Nixie_roll
 Reset Upper_glim : Reset Lower_glim
 Countrol2 = 0
 Incr Countrol3
 If Countrol3 = 10 Then
  Countrol3 = 0 : Decr Rolph
 End If

 Tmp2 = Countrol3 + 1
 If Rolph.0 = 1 Then Tmp2 = 11 - Tmp2                       'if rolph is odd number, invert roll order
  Tmp1 = Roll_order(tmp2)
  Nixmin = Tmp1 * 16
  Nixmin = Nixmin + Tmp1
  Nixhr = Nixmin
  Call Nixie_write
End Sub



'****Read switches****
Sub Switch_read
'Read Mode rotary switch
 If Swdebr = 0 Then                                         'if debounce not going
  Swrs = 0
  Swrs.0 = Off_rty
  Swrs.1 = Normal_rty
  Swrs.2 = Alarm_set_rty
  Swrs.3 = Setup_rty
 End If

 If Swrs <> Swrs2 And Swrs < &B1111 And Swdebr = 0 Then     'if status changed
  Swdebr = 10                                               'set debounce counter
  Swrs2 = Swrs
  Selpos = 1
  If Swrs.0 = 0 Then
   Mainmode = 0 : Countasb = 0
  End If                                                    'dsp off
  If Swrs.1 = 0 Then
   Mainmode = 1 : Set Hv_power
  End If                                                    'time
  If Swrs.2 = 0 Then Mainmode = 2                           'alm set
  If Swrs.3 = 0 Then Mainmode = 3                           'setup
 End If

 If Swdebr > 0 Then Decr Swdebr

'Read pushbuttons
 Swbut = 0                                                  'reset pushbutton output
 If Swdebb = 0 Then                                         'if debouncing not active...
  Swpb = &B00000001
  Swpb.1 = Sw_up                                            'read Up button
  Swpb.2 = Sw_dn                                            'read Down button
  Swpb.3 = Sw_select                                        'read Select button
  Swpb.4 = Sw_snooze                                        'read Snooze button
  Swpb = 31 - Swpb                                          'invert results to 1=on
  Toggle Swpb.4
 End If

 If Swpb <> Swpb2 And Swdebb = 0 Then                       'if status changed and debouncing not active...
  Swdebb = 5                                                'set debounce counter
  Swpb2 = Swpb                                              'copy status for comparing next time
  Swrep = 0                                                 'reset repeat counter
 End If

 If Swpb > 0 Then Incr Swrep                                'if button pressed, increase repeat counter
 If Swpb.0 = 1 Or Swpb.3 = 1 Or Swpb.4 = 1 Then             'if Astop or Select pressed...
  If Swrep = 1 Then Swbut = Swpb                            'if just pressed, copy to output
  If Swrep > 1 Then Swrep = 2                               'hold repeat counter for these buttons
 End If

 If Swpb.1 = 1 Or Swpb.2 = 1 Then                           'if Set+ or Set- pressed...
  If Swrep = 1 Then Swbut = Swpb                            'if just pressed, copy to output
  If Swrep = 122 Then                                       'if repeat threshold reached...
   Swbut = Swpb                                             'copy to output
   Swrep = 107                                              'decrease repeat counter
  End If
 End If
 If Swdebb > 0 Then Decr Swdebb
End Sub


'****Alarm sound**** (Alarm tunes at end)
Sub Alarm
 If Nlen = 0 Then
  Reset Buzzer                                              'PWM off
  Read Nfreq
  Read Nlen
  Nlen = Nlen * 2
  If Nlen = 0 Then                                          'Tune ends
   Call Almtune_restore
   Read Nfreq
   Read Nlen
   Nlen = Nlen * 2
  End If

  If Nfreq > 0 Then

   T1countd = 16000000 / Nfreq
   T1count = T1countd                                       'set freq. (Crystal / desired freq.)
   Icr1h = High(t1count)
   Icr1l = Low(t1count)
   Compare1a = T1count \ 2                                  '50% duty cycle
   Set Buzzer                                               'PWM on
   Decr Nlen
  End If
 Else
  Decr Nlen
 End If

End Sub

'Almtune restore
Sub Almtune_restore
 Nlen = 0
 Select Case Almtune
  Case 1 : Restore Almtune1
  Case 2 : Restore Almtune2
  Case 3 : Restore Almtune3
  Case 4 : Restore Almtune4
  Case 5 : Restore Almtune5
  Case 6 : Restore Almtune6
 End Select
End Sub


'----------------------------------------------------------------------
'                      Data lines for alarm notes by vsaar
'----------------------------------------------------------------------
'
'Note data: Frequency (Hz, 0 = silent), Duration (1 = 1/122 s, max. 255)
'end mark: 0% , 0%

'     Octave1  Octave2  Octave3  Octave4  Octave5
'C     262      523     1046     2093     4186
'C#    277      554     1109     2217
'D     294      587     1175     2349
'D#    311      622     1245     2489
'E     330      659     1319     2637
'F     349      698     1397     2794
'F#    370      740     1480     2960
'G     392      784     1568     3136
'G#    415      831     1661     3322
'A     440      880     1760     3520
'A#    466      932     1865     3729
'B/H   494      988     1976     3951


Almtune1:                                                   'Basic beep
Data 2048% , 8% , 0% , 7% , 2048% , 8% , 0% , 7% , 2048% , 8% , 0% , 7%
Data 2048% , 8% , 0% , 69% , 0% , 0%

Almtune2:                                                   'Nokia alarm
Data 2640% , 12% , 0% , 11% , 2640% , 12% , 0% , 11%
Data 2640% , 12% , 0% , 11% , 2640% , 12% , 0% , 11%
Data 2640% , 12% , 0% , 11% , 2640% , 12% , 0% , 11%
Data 2640% , 12% , 0% , 11% , 2640% , 12% , 0% , 11%
Data 2640% , 12% , 0% , 11% , 2640% , 12% , 0% , 149% , 0% , 0%

Almtune3:                                                   'Cacophony
Data 3292% , 7% , 2072% , 7% , 1320% , 7% , 3122% , 7%
Data 2281% , 7% , 2609% , 7% , 3186% , 7% , 2848% , 7%
Data 1744% , 7% , 2224% , 7% , 3843% , 7% , 3121% , 7%
Data 3951% , 7% , 1144% , 7% , 2390% , 7% , 3077% , 7%
Data 3040% , 7% , 2891% , 7% , 1680% , 7% , 2595% , 7% , 0% , 0%

Almtune4:                                                   'Grande valse
Data 1319% , 16% , 1175% , 16% , 740% , 32% , 831% , 32%
Data 1109% , 16% , 988% , 16% , 587% , 32% , 659% , 32%
Data 988% , 16% , 880% , 16% , 554% , 32% , 659% , 32%
Data 880% , 96% , 0% , 280% , 0% , 0%

Almtune5:                                                   'Leisure Suit Larry
Data 587% , 45% , 622% , 45% , 659% , 45%
Data 698% , 30% , 784% , 15% , 587% , 30% , 698% , 30%      't1
Data 0% , 15% , 784% , 30% , 0% , 15% , 587% , 15%
Data 698% , 30% , 784% , 15% , 698% , 30% , 932% , 60%      't2
Data 0% , 45%
Data 784% , 30% , 932% , 15% , 740% , 30% , 784% , 30%      't3
Data 0% , 15% , 932% , 30% , 0% , 15% , 740% , 15%
Data 784% , 30% , 932% , 15% , 1046% , 30%                  't4
Data 1109% , 60% , 932% , 15% , 0% , 30%
Data 1175% , 44% , 0% , 2% , 1175% , 14% , 0% , 30%         't5
Data 1175% , 44% , 0% , 2% , 1175% , 14% , 0% , 30%
Data 1175% , 30% , 1109% , 15% , 1046% , 30%                't6
Data 988% , 60% , 784% , 15% , 0% , 30%
Data 1175% , 30% , 1109% , 15% , 1175% , 15% , 0% , 30%     't7
Data 932% , 30% , 1046% , 15% , 0% , 30% , 932% , 15%
Data 0% , 45% , 0% , 0%                                     't8

Almtune6:                                                   'Pipapiipaa
Data 880% , 37% , 740% , 37% , 659% , 74% , 554% , 74%
Data 880% , 37% , 740% , 37% , 659% , 74% , 554% , 74%
Data 1109% , 37% , 988% , 37% , 880% , 74% , 740% , 73%
Data 0% , 1% , 740% , 73% , 0% , 1% , 740% , 148%
Data 988% , 37% , 880% , 37% , 831% , 74% , 659% , 74%
Data 622% , 74% , 587% , 74% , 659% , 111% , 587% , 36%
Data 0% , 1% , 587% , 74% , 554% , 148% , 0% , 222% , 0% , 0%