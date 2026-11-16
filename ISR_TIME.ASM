; ISR_TIME.ASM - Mide el intervalo entre interrupciones de teclado
; leyendo el contador de ticks del sistema en 0040h:006Ch
; Juan Diego Rojas Rey - 1152512
; Compila: nasm -f bin ISR_TIME.ASM -o ISR_TIME.COM

[BITS 16]
[ORG 0x100]

MAX_KEYS    EQU 5
KBD_DATA    EQU 60h
PIC_CMD     EQU 20h
EOI         EQU 20h
BIOS_SEG    EQU 40h         ; segmento de la zona de datos del BIOS
TICK_OFF    EQU 6Ch         ; offset del contador de ticks (32 bits)

section .text
start:
    ; guardar el vector original de INT 09h
    MOV AX, 3509h
    INT 21h
    MOV [old_isr],   BX
    MOV [old_isr+2], ES

    ; inicializar ticks_prev con la lectura actual del contador (0040h:006Ch)
    PUSH ES
    MOV  AX, BIOS_SEG
    MOV  ES, AX
    MOV  AX, [ES:TICK_OFF]  ; palabra baja del contador de ticks
    MOV  [ticks_prev], AX
    POP  ES

    ; instalar el ISR propio
    PUSH DS
    MOV  AX, CS
    MOV  DS, AX
    MOV  DX, mi_isr
    MOV  AX, 2509h
    INT  21h
    POP  DS

    MOV AH, 09h
    MOV DX, msg_inicio
    INT 21h

    STI
.esperar:
    MOV AX, [contador]
    CMP AX, MAX_KEYS
    JL  .esperar

    CLI
    PUSH DS
    LDS DX, [old_isr]
    MOV AX, 2509h
    INT 21h
    POP DS
    STI

    MOV AH, 09h
    MOV DX, msg_fin
    INT 21h
    MOV AH, 4Ch
    INT 21h

; ---- ISR propio con medicion de intervalo -------------------------------
mi_isr:
    PUSH AX
    PUSH BX
    PUSH DX
    PUSH DS
    PUSH ES

    MOV  AX, CS
    MOV  DS, AX

    IN   AL, KBD_DATA       ; leer el scancode (libera el 8042)
    TEST AL, 80h
    JNZ  .solo_eoi          ; codigo de soltar tecla: no se mide

    ; leer el contador de ticks actual (palabra baja)
    MOV  AX, BIOS_SEG
    MOV  ES, AX
    MOV  AX, [ES:TICK_OFF]
    MOV  BX, AX
    SUB  BX, [ticks_prev]   ; BX = ticks desde la interrupcion anterior
    MOV  [ticks_prev], AX

    ; EOI apenas termino el trabajo sobre el hardware, antes de imprimir
    MOV  AL, EOI
    OUT  PIC_CMD, AL

    MOV  AH, 09h
    MOV  DX, msg_ticks
    INT  21h
    MOV  AX, BX
    CALL imprimir_decimal

    INC  WORD [contador]
    JMP  .salir

.solo_eoi:
    MOV  AL, EOI
    OUT  PIC_CMD, AL

.salir:
    POP  ES
    POP  DS
    POP  DX
    POP  BX
    POP  AX
    IRET

; Subrutina: imprime AX en decimal (sin signo)
imprimir_decimal:
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX
    MOV  BX, 10
    XOR  CX, CX
.divide:
    XOR  DX, DX
    DIV  BX
    PUSH DX
    INC  CX
    TEST AX, AX
    JNZ  .divide
.imprimir:
    POP  DX
    ADD  DL, 30h
    MOV  AH, 02h
    INT  21h
    LOOP .imprimir
    POP  DX
    POP  CX
    POP  BX
    POP  AX
    RET

section .data
old_isr      DD 0           ; SEG:OFF del handler original de INT 09h
ticks_prev   DW 0           ; ultima lectura del contador (palabra baja)
contador     DW 0           ; interrupciones atendidas
msg_inicio   DB "ISR_TIME instalado. Presione 5 teclas con pausas distintas.", 0Dh, 0Ah, "$"
msg_ticks    DB 0Dh, 0Ah, "Ticks desde la interrupcion anterior: $"
msg_fin      DB 0Dh, 0Ah, "ISR_TIME restaurado. Fin del programa.", 0Dh, 0Ah, "$"
