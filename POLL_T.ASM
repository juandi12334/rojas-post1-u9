; POLL_T.ASM - Polling con timeout para el puerto de teclado
; Juan Diego Rojas Rey - 1152512
; Compila: nasm -f bin POLL_T.ASM -o POLL_T.COM
; Opciones de compilacion (nasm -d):
;   -dMAX_RETRY=5      reintentos distintos al valor por defecto (0FFFFh)
;   -dESPERA_PREVIA    antes del polling enmascara IRQ1 unos 3 s para dar tiempo
;                      a presionar una tecla y probar la ruta de "dato listo"

[BITS 16]
[ORG 0x100]

%ifndef MAX_RETRY
%define MAX_RETRY 0FFFFh    ; numero maximo de reintentos
%endif

KBD_DATA    EQU 60h
KBD_STATUS  EQU 64h
OBF_MASK    EQU 01h
PIC_IMR     EQU 21h

section .text
start:
%ifdef ESPERA_PREVIA
    MOV AH, 09h
    MOV DX, msg_previa
    INT 21h
    IN  AL, PIC_IMR
    MOV [imr_guardado], AL
    OR  AL, 02h             ; enmascarar IRQ1: la tecla se queda en el 8042
    OUT PIC_IMR, AL
    PUSH ES
    MOV AX, 40h
    MOV ES, AX
    MOV BX, [ES:6Ch]        ; ticks al empezar
.espera:
    MOV AX, [ES:6Ch]
    SUB AX, BX
    CMP AX, 54              ; ~3 segundos
    JB  .espera
    POP ES
%endif

    CLI                     ; el BIOS no debe leer el 60h antes que nosotros
    MOV CX, MAX_RETRY

.poll:
    IN  AL, KBD_STATUS
    TEST AL, OBF_MASK
    JNZ .dato_listo
    LOOP .poll              ; decrementa CX; salta si CX != 0

.timeout:                   ; CX llego a 0 sin dato
    STI
    MOV AH, 09h
    MOV DX, msg_timeout
    INT 21h
    JMP .fin

.dato_listo:
    IN  AL, KBD_DATA
    TEST AL, 80h            ; codigo "break" (p. ej. el Enter con que se lanzo el
    JNZ .descartar          ; programa): se descarta y se sigue contando reintentos
    MOV BL, AL
    STI
    MOV AH, 09h
    MOV DX, msg_dato
    INT 21h
    MOV AL, BL
    CALL imprimir_hex8
    MOV AH, 09h
    MOV DX, crlf
    INT 21h

    JMP .fin

.descartar:
    LOOP .poll
    JMP .timeout

.fin:
%ifdef ESPERA_PREVIA
    MOV AL, [imr_guardado]  ; restaurar el IMR original
    OUT PIC_IMR, AL
%endif
    MOV CX, 3000            ; dejar que el IRQ1 pendiente se atienda...
.pausa: LOOP .pausa
.vaciar:                    ; ...y vaciar el buffer de teclado del BIOS
    MOV AH, 01h
    INT 16h
    JZ  .listo
    MOV AH, 00h
    INT 16h
    JMP .vaciar
.listo:
    MOV AH, 4Ch
    INT 21h

imprimir_hex8:
    PUSH AX
    SHR  AL, 4
    CALL .nibble
    POP  AX
    AND  AL, 0Fh
.nibble:
    ADD  AL, 30h
    CMP  AL, 3Ah
    JL   .imprimir
    ADD  AL, 07h
.imprimir:
    MOV  DL, AL
    MOV  AH, 02h
    INT  21h
    RET

section .data
imr_guardado DB 0
msg_previa  DB "IRQ1 enmascarado 3 s: presione una tecla ahora...", 0Dh, 0Ah, "$"
msg_timeout DB "Timeout: sin respuesta del dispositivo", 0Dh, 0Ah, "$"
msg_dato    DB "Dato listo. Scancode leido: $"
crlf        DB "h", 0Dh, 0Ah, "$"
