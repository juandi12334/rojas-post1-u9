; MASK_KB.ASM - Enmascarar y desenmascarar IRQ1 con el IMR del PIC 8259A
; Juan Diego Rojas Rey - 1152512
; Compila: nasm -f bin MASK_KB.ASM -o MASK_KB.COM

[BITS 16]
[ORG 0x100]

PIC_IMR     EQU 21h         ; Interrupt Mask Register del PIC maestro
IRQ1_MASK   EQU 02h         ; bit 1 = IRQ1 (teclado)
TICKS_3S    EQU 55          ; 18.2 ticks/s * 3 s

section .text
start:
    ; leer el IMR actual y guardarlo
    IN  AL, PIC_IMR
    PUSH AX                 ; conservar valor original

    ; enmascarar IRQ1 (bit en 1 = deshabilitada)
    OR  AL, IRQ1_MASK
    OUT PIC_IMR, AL

    MOV AH, 09h
    MOV DX, msg_mask
    INT 21h

    ; esperar ~3 segundos con el timer del BIOS
    MOV AH, 00h
    INT 1Ah                 ; CX:DX = ticks
    MOV BX, DX              ; BX = ticks al empezar
.wait:
    MOV AH, 00h
    INT 1Ah
    SUB DX, BX              ; ticks transcurridos (aritmetica modulo 2^16)
    CMP DX, TICKS_3S
    JB  .wait

    ; cuantas teclas se acumularon en el buffer del BIOS mientras IRQ1 estaba apagada
    CALL contar_buffer
    MOV [antes], AX

    ; restaurar el IMR original
    POP AX
    OUT PIC_IMR, AL

    MOV AH, 09h
    MOV DX, msg_unmask
    INT 21h

    ; dar tiempo a que el PIC despache lo que quedo pendiente
    MOV AH, 00h
    INT 1Ah
    MOV BX, DX
.pausa:
    MOV AH, 00h
    INT 1Ah
    SUB DX, BX
    CMP DX, 9               ; ~0.5 s
    JB  .pausa

    CALL contar_buffer
    MOV [despues], AX

    ; informe
    MOV AH, 09h
    MOV DX, msg_antes
    INT 21h
    MOV AX, [antes]
    CALL imprimir_decimal
    MOV AH, 09h
    MOV DX, msg_despues
    INT 21h
    MOV AX, [despues]
    CALL imprimir_decimal
    MOV AH, 09h
    MOV DX, crlf
    INT 21h

    ; vaciar el buffer para no dejar teclas sueltas en el prompt
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

; contar_buffer: devuelve en AX el numero de teclas en el buffer del BIOS
; (cabeza en 0040h:001Ah, cola en 0040h:001Ch, 2 bytes por tecla)
contar_buffer:
    PUSH ES
    PUSH BX
    MOV AX, 40h
    MOV ES, AX
    MOV AX, [ES:1Ch]        ; cola
    MOV BX, [ES:1Ah]        ; cabeza
    SUB AX, BX
    JNS .positivo
    ADD AX, 20h             ; el buffer es circular de 32 bytes
.positivo:
    SHR AX, 1               ; bytes -> teclas
    POP BX
    POP ES
    RET

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
antes       DW 0
despues     DW 0
msg_mask    DB "IRQ1 enmascarado (teclado deshabilitado)... presione teclas ahora.", 0Dh, 0Ah, "$"
msg_unmask  DB "IRQ1 restaurado.", 0Dh, 0Ah, "$"
msg_antes   DB "Teclas en el buffer del BIOS con IRQ1 enmascarada: $"
msg_despues DB 0Dh, 0Ah, "Teclas en el buffer tras desenmascarar: $"
crlf        DB 0Dh, 0Ah, "$"
