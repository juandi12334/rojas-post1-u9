; ITER_T.ASM - Cuantas iteraciones de polling caben en ~1 segundo reales
; Juan Diego Rojas Rey - 1152512
; Programa de apoyo para la decision tecnica sobre el timeout (Parte 1):
; un contador de reintentos mide iteraciones, no tiempo. Aqui se cuentan las
; iteraciones de un bucle de polling durante 18 ticks (~1 s) del BIOS.
; Compila: nasm -f bin ITER_T.ASM -o ITER_T.COM

[BITS 16]
[ORG 0x100]

TICKS_1S    EQU 18

section .text
start:
    MOV AH, 09h
    MOV DX, msg_inicio
    INT 21h

    MOV AX, 40h
    MOV ES, AX
    MOV AX, [ES:6Ch]
.sincro:                    ; esperar al inicio de un tick para no medir de menos
    CMP AX, [ES:6Ch]
    JE  .sincro
    MOV BX, [ES:6Ch]
    XOR EDI, EDI            ; EDI = iteraciones (32 bits)

.cuenta:
    IN  AL, 64h             ; mismo trabajo que el bucle .poll de POLL_T
    TEST AL, 01h
    INC EDI
    MOV AX, [ES:6Ch]
    SUB AX, BX
    CMP AX, TICKS_1S
    JB  .cuenta

    MOV AH, 09h
    MOV DX, msg_res
    INT 21h
    MOV EAX, EDI
    CALL imprimir_eax
    MOV AH, 09h
    MOV DX, crlf
    INT 21h
    MOV AH, 4Ch
    INT 21h

; imprimir_eax: imprime EAX en decimal
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
msg_inicio  DB "Contando iteraciones de polling durante 18 ticks (~1 s)...", 0Dh, 0Ah, "$"
msg_res     DB "Iteraciones en ~1 segundo: $"
crlf        DB 0Dh, 0Ah, "$"
