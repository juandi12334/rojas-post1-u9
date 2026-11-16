; MULTI_ST.ASM - Polling combinado de dos puertos de estado (teclado + LPT1)
; Juan Diego Rojas Rey - 1152512
; Compila: nasm -f bin MULTI_ST.ASM -o MULTI_ST.COM
; Opcion: -dESPERA_PREVIA enmascara IRQ1 unos 3 s antes del polling, para poder
;         presionar una tecla y ver el caso en que se disparan los dos a la vez.

[BITS 16]
[ORG 0x100]

KBD_STATUS   EQU 64h
KBD_DATA     EQU 60h
STATUS_PORT  EQU 0379h
PIC_IMR      EQU 21h

section .text
start:
%ifdef ESPERA_PREVIA
    MOV AH, 09h
    MOV DX, msg_previa
    INT 21h
    IN  AL, PIC_IMR
    MOV [imr_guardado], AL
    OR  AL, 02h             ; enmascarar IRQ1
    OUT PIC_IMR, AL
    PUSH ES
    MOV AX, 40h
    MOV ES, AX
    MOV BX, [ES:6Ch]
.espera:
    MOV AX, [ES:6Ch]
    SUB AX, BX
    CMP AX, 54              ; ~3 segundos
    JB  .espera
    POP ES
%endif

.poll:
    ; Bandera de teclado: bit 0 (OBF) del registro de estado 64h
    IN  AL, KBD_STATUS
    AND AL, 01h
    MOV BL, AL              ; BL = bandera_teclado (0 o 1)

    ; Bandera de LPT1: bit 7 (listo) del registro de estado 0x379
    MOV DX, STATUS_PORT     ; 0379h no cabe en el operando inmediato de IN: va en DX
    IN  AL, DX
    AND AL, 80h
    SHR AL, 7               ; normaliza a 0 o 1
    MOV BH, AL              ; BH = bandera_lpt1 (0 o 1)

    MOV AL, BL
    OR  AL, BH              ; AL = bandera_teclado OR bandera_lpt1
    JZ  .poll               ; ningun dispositivo listo -> repetir

    ; El OR descarta cual de las dos fue: se examinan BL y BH por separado
    TEST BL, BL
    JZ  .soloLpt1
    MOV AH, 09h
    MOV DX, msg_tecl
    INT 21h

.soloLpt1:
    TEST BH, BH
    JZ  .fin
    MOV AH, 09h
    MOV DX, msg_lpt1
    INT 21h

.fin:
%ifdef ESPERA_PREVIA
    MOV AL, [imr_guardado]
    OUT PIC_IMR, AL
    MOV CX, 3000
.pausa: LOOP .pausa
.vaciar:
    MOV AH, 01h
    INT 16h
    JZ  .listo
    MOV AH, 00h
    INT 16h
    JMP .vaciar
.listo:
%endif
    MOV AH, 4Ch
    INT 21h

section .data
imr_guardado DB 0
msg_previa  DB "IRQ1 enmascarado 3 s: presione una tecla ahora...", 0Dh, 0Ah, "$"
msg_tecl    DB "Teclado listo (OBF=1).", 0Dh, 0Ah, "$"
msg_lpt1    DB "LPT1 listo (BUSY#=1).", 0Dh, 0Ah, "$"
