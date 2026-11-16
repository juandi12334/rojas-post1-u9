; ISR_KB.ASM - ISR personalizado para IRQ1 (teclado, INT 09h)
; Juan Diego Rojas Rey - 1152512
; Arquitectura de Computadores - Unidad 9 - Parte 2 (Paso 1)
; Compila: nasm -f bin ISR_KB.ASM -o ISR_KB.COM

[BITS 16]
[ORG 0x100]

MAX_KEYS    EQU 5           ; teclas a atender antes de terminar
KBD_DATA    EQU 60h
PIC_CMD     EQU 20h         ; puerto de comandos del PIC maestro
EOI         EQU 20h         ; End Of Interrupt no especifico

section .text
start:
    ; (1) guardar el vector original de INT 09h
    MOV AX, 3509h           ; AH=35h: obtener vector
    INT 21h                 ; ES:BX = direccion del handler actual
    MOV [old_isr],   BX
    MOV [old_isr+2], ES

    ; (2) instalar el ISR propio
    PUSH DS
    MOV  AX, CS
    MOV  DS, AX
    MOV  DX, mi_isr         ; DS:DX = direccion del nuevo handler
    MOV  AX, 2509h          ; AH=25h: fijar vector
    INT  21h
    POP  DS

    MOV AH, 09h
    MOV DX, msg_inicio
    INT 21h

    STI                     ; asegurar interrupciones habilitadas

    ; (3) espera activa hasta atender MAX_KEYS pulsaciones
.esperar:
    MOV AX, [contador]
    CMP AX, MAX_KEYS
    JL  .esperar

    ; (4) restaurar el handler original
    CLI
    PUSH DS
    LDS DX, [old_isr]       ; DS:DX = handler original
    MOV AX, 2509h
    INT 21h
    POP DS                  ; LDS cambio DS: se recupera antes de usar los mensajes
    STI

    MOV AH, 09h
    MOV DX, msg_fin
    INT 21h
    MOV AH, 4Ch
    INT 21h

; ---- ISR propio ------------------------------------------------------
mi_isr:
    PUSH AX
    PUSH DX
    PUSH DS

    MOV  AX, CS
    MOV  DS, AX             ; DS apunta al segmento del programa

    IN   AL, KBD_DATA       ; leer el scancode (libera el buffer del 8042)
    TEST AL, 80h            ; bit 7 = 1: codigo de soltar tecla (break)
    JNZ  .enviar_eoi        ; las teclas se cuentan solo al presionarlas

    MOV  AH, 09h
    MOV  DX, msg_tecla
    INT  21h

    INC  WORD [contador]

.enviar_eoi:
    MOV  AL, EOI            ; EOI siempre, tambien para los codigos break
    OUT  PIC_CMD, AL

    POP  DS
    POP  DX
    POP  AX
    IRET

section .data
contador    DW 0            ; numero de teclas atendidas
old_isr     DD 0            ; SEG:OFF del handler original
msg_inicio  DB "ISR propio instalado. Presione 5 teclas.", 0Dh, 0Ah, "$"
msg_tecla   DB 0Dh, 0Ah, "Tecla detectada por ISR propio$"
msg_fin     DB 0Dh, 0Ah, "ISR restaurado. Fin del programa.", 0Dh, 0Ah, "$"
