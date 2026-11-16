; ISR_EOI.ASM - Efecto del EOI en un ISR de IRQ1 (programa de apoyo, Parte 2)
; Juan Diego Rojas Rey - 1152512
; Uso: ISR_EOI      -> el ISR envia el EOI (comportamiento correcto)
;      ISR_EOI n    -> el ISR NO envia el EOI (para ver que pasa)
; Espera hasta 3 teclas o 6 segundos y cuenta cuantas atendio el ISR y cuantas
; iteraciones del bucle principal (trabajo "util") alcanzo a hacer mientras tanto.
; Compila: nasm -f bin ISR_EOI.ASM -o ISR_EOI.COM

[BITS 16]
[ORG 0x100]

KBD_DATA    EQU 60h
PIC_CMD     EQU 20h
EOI         EQU 20h
KEYS_META   EQU 3
TICKS_6S    EQU 110

section .text
start:
    ; modo: parametro 'n' = sin EOI
    CMP BYTE [0080h], 0
    JE  .modo_listo
    MOV AL, [0082h]
    OR  AL, 20h
    CMP AL, 'n'
    JNE .modo_listo
    MOV BYTE [sin_eoi], 1
.modo_listo:
    MOV AH, 09h
    MOV DX, msg_con
    CMP BYTE [sin_eoi], 0
    JE  .imprime_modo
    MOV DX, msg_sin
.imprime_modo:
    INT 21h

    ; pausa de ~0.5 s con el handler del BIOS: asi el codigo "break" de la tecla
    ; con que se lanzo el programa (Enter) no cuenta como interrupcion del ISR
    MOV AX, 40h
    MOV ES, AX
    MOV BX, [ES:6Ch]
.asentar:
    MOV AX, [ES:6Ch]
    SUB AX, BX
    CMP AX, 9
    JB  .asentar

    MOV AX, 3509h
    INT 21h
    MOV [old_isr],   BX
    MOV [old_isr+2], ES

    PUSH DS
    MOV AX, CS
    MOV DS, AX
    MOV DX, mi_isr
    MOV AX, 2509h
    INT 21h
    POP DS

    MOV AX, 40h
    MOV ES, AX
    MOV BX, [ES:6Ch]        ; ticks al empezar
    STI

.bucle:
    INC DWORD [trabajo]     ; "trabajo util" del programa principal
    CMP WORD [contador], KEYS_META
    JAE .listo
    MOV AX, [ES:6Ch]
    SUB AX, BX
    CMP AX, TICKS_6S
    JB  .bucle

.listo:
    CLI
    PUSH DS
    LDS DX, [old_isr]
    MOV AX, 2509h
    INT 21h
    POP DS
    ; si el ISR no envio EOI, se envia aqui para no dejar el PIC bloqueado
    MOV AL, EOI
    OUT PIC_CMD, AL
    STI

    ; dejar que el PIC despache lo que haya quedado pendiente (~0.5 s)
    MOV AX, 40h
    MOV ES, AX
    MOV BX, [ES:6Ch]
.pendiente:
    MOV AX, [ES:6Ch]
    SUB AX, BX
    CMP AX, 9
    JB  .pendiente

    MOV AH, 09h
    MOV DX, msg_irq
    INT 21h
    MOV AX, [contador]
    CALL imprimir_decimal
    MOV AH, 09h
    MOV DX, msg_trab
    INT 21h
    MOV EAX, [trabajo]
    CALL imprimir_eax
    MOV AH, 09h
    MOV DX, crlf
    INT 21h

    ; vaciar el buffer del BIOS
.vaciar:
    MOV AH, 01h
    INT 16h
    JZ  .fin
    MOV AH, 00h
    INT 16h
    JMP .vaciar
.fin:
    MOV AH, 4Ch
    INT 21h

mi_isr:
    PUSH AX
    PUSH DS
    MOV  AX, CS
    MOV  DS, AX
    IN   AL, KBD_DATA
    TEST AL, 80h
    JNZ  .eoi               ; break: no se cuenta
    INC  WORD [contador]
.eoi:
    CMP  BYTE [sin_eoi], 0
    JNE  .salir             ; modo 'n': se omite el EOI a proposito
    MOV  AL, EOI
    OUT  PIC_CMD, AL
.salir:
    POP  DS
    POP  AX
    IRET

imprimir_decimal:
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
    RET

imprimir_eax:
    MOV EBX, 10
    XOR CX, CX
.divide:
    XOR EDX, EDX
    DIV EBX
    PUSH DX
    INC CX
    TEST EAX, EAX
    JNZ .divide
.imprimir:
    POP DX
    ADD DL, 30h
    MOV AH, 02h
    INT 21h
    LOOP .imprimir
    RET

section .data
sin_eoi     DB 0
contador    DW 0
trabajo     DD 0
old_isr     DD 0
msg_con     DB "Modo CON EOI. Presione 3 teclas (tiene 6 s)...", 0Dh, 0Ah, "$"
msg_sin     DB "Modo SIN EOI. Presione 3 teclas (tiene 6 s)...", 0Dh, 0Ah, "$"
msg_irq     DB "Interrupciones de teclado atendidas por el ISR: $"
msg_trab    DB 0Dh, 0Ah, "Iteraciones del bucle principal mientras esperaba: $"
crlf        DB 0Dh, 0Ah, "$"
