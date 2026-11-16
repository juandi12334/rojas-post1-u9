; ISR_CHAIN.ASM - ISR de IRQ1 encadenado con el handler original del BIOS
; Juan Diego Rojas Rey - 1152512
; Registra cada tecla en un contador propio y despues llama al handler anterior,
; de modo que DOS sigue recibiendo las teclas con normalidad.
; Compila: nasm -f bin ISR_CHAIN.ASM -o ISR_CHAIN.COM

[BITS 16]
[ORG 0x100]

MAX_KEYS    EQU 5
KBD_DATA    EQU 60h

section .text
start:
    ; guardar el vector original de INT 09h
    MOV AX, 3509h
    INT 21h
    MOV [old_isr],   BX
    MOV [old_isr+2], ES

    ; instalar el ISR encadenado
    PUSH DS
    MOV  AX, CS
    MOV  DS, AX
    MOV  DX, mi_isr_chain
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

    ; restaurar el vector original
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

; ---- ISR encadenado ----------------------------------------------------
mi_isr_chain:
    PUSH AX
    PUSH DX
    PUSH DS
    MOV  AX, CS
    MOV  DS, AX

    IN   AL, KBD_DATA       ; leer el scancode sin consumirlo para el BIOS:
                            ; el 8042 conserva el valor hasta la siguiente tecla
    TEST AL, 80h
    JNZ  .encadenar         ; break: no se cuenta, pero igual se encadena

    MOV  AH, 09h
    MOV  DX, msg_tecla
    INT  21h
    INC  WORD [contador]

.encadenar:
    POP  DS
    POP  DX
    POP  AX
    ; simular una INT: apilar los flags y hacer un far call al handler original.
    ; El handler original envia el EOI, por eso este ISR no lo envia.
    PUSHF
    CALL FAR [CS:old_isr]
    IRET

section .data
contador    DW 0
old_isr     DD 0
msg_inicio  DB "ISR encadenado instalado. Presione 5 teclas (abcde).", 0Dh, 0Ah, "$"
msg_tecla   DB "[ISR_CHAIN] tecla registrada", 0Dh, 0Ah, "$"
msg_fin     DB "Vector restaurado. Lo tecleado deberia aparecer en el prompt:", 0Dh, 0Ah, "$"
