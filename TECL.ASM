; TECL.ASM - Lectura del estado del teclado 8042 por polling
; Juan Diego Rojas Rey - 1152512
; Arquitectura de Computadores - Unidad 9 - Parte 1 (Paso 1)
; Compila: nasm -f bin TECL.ASM -o TECL.COM

[BITS 16]
[ORG 0x100]                 ; programa .COM, CS=DS=ES=SS

KBD_DATA    EQU 60h         ; puerto de datos del 8042
KBD_STATUS  EQU 64h         ; registro de estado del 8042
OBF_MASK    EQU 01h         ; bit 0 = Output Buffer Full

section .text
start:
    MOV AH, 09h
    MOV DX, msg_espera
    INT 21h

    ; CLI para que el handler del BIOS (IRQ1) no lea el puerto 60h antes
    ; que este programa y se lleve el scancode
    CLI

.poll:
    IN  AL, KBD_STATUS      ; leer registro de estado del 8042
    TEST AL, OBF_MASK       ; comprobar bit OBF
    JZ  .poll               ; OBF=0: no hay dato listo, repetir
    MOV [estado], AL        ; guardar el valor de estado que disparo la salida

    IN  AL, KBD_DATA        ; leer scancode (esto baja OBF)
    TEST AL, 80h            ; bit 7 = 1: codigo "break" (tecla soltada), por ejemplo
    JNZ .poll               ; el de la tecla Enter con la que se lanzo el programa
    MOV BL, AL              ; BL = scancode de una tecla presionada (make)
    STI                     ; devolver las interrupciones al sistema

    MOV AH, 09h
    MOV DX, msg_estado
    INT 21h
    MOV AL, [estado]
    CALL imprimir_hex8

    MOV AH, 09h
    MOV DX, msg_scan
    INT 21h
    MOV AL, BL
    CALL imprimir_hex8

    MOV AH, 09h
    MOV DX, crlf
    INT 21h

    ; el IRQ1 de esta tecla ya estaba pendiente en el PIC: al hacer STI el BIOS
    ; la atiende y deja la tecla en su buffer. Se espera un instante y se vacia
    ; el buffer para que la letra no aparezca despues en el prompt de DOS.
    MOV CX, 3000
.pausa: LOOP .pausa
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

; imprimir_hex8: muestra AL como dos digitos hexadecimales
imprimir_hex8:
    PUSH AX
    SHR  AL, 4              ; nibble alto
    CALL .nibble
    POP  AX
    AND  AL, 0Fh            ; nibble bajo
.nibble:
    ADD  AL, 30h
    CMP  AL, 3Ah
    JL   .imprimir
    ADD  AL, 07h            ; ajuste para A-F
.imprimir:
    MOV  DL, AL
    MOV  AH, 02h
    INT  21h
    RET

section .data
estado      DB 0
msg_espera  DB "Presione una tecla...", 0Dh, 0Ah, "$"
msg_estado  DB "Estado 64h = $"
msg_scan    DB "h  Scancode (60h) = $"
crlf        DB "h", 0Dh, 0Ah, "$"
