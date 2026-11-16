; LPT1.ASM - Envio de un caracter al puerto paralelo LPT1 (protocolo centronics)
; Juan Diego Rojas Rey - 1152512
; Compila: nasm -f bin LPT1.ASM -o LPT1.COM

[BITS 16]
[ORG 0x100]

DATA_PORT    EQU 0378h      ; registro de datos (D0-D7)
STATUS_PORT  EQU 0379h      ; registro de estado
CTRL_PORT    EQU 037Ah      ; registro de control
BUSY_BIT     EQU 80h        ; bit 7 de estado: 1 = impresora lista (BUSY# alto)
ACK_BIT      EQU 40h        ; bit 6 de estado: ACK# (activo en bajo)
STROBE_BIT   EQU 01h        ; bit 0 de control: STROBE
CARACTER     EQU 41h        ; 'A'
MAX_ESPERA   EQU 0FFFFh     ; tope de reintentos para no bloquearse

section .text
start:
    ; (1) esperar BUSY# = 1 (impresora lista), con tope de reintentos
    MOV CX, MAX_ESPERA
.wait_ready:
    MOV DX, STATUS_PORT     ; puertos > 0FFh: IN/OUT solo aceptan el puerto en DX
    IN  AL, DX
    TEST AL, BUSY_BIT
    JNZ .lista
    LOOP .wait_ready
    MOV AH, 09h
    MOV DX, msg_ocupada
    INT 21h
    JMP .fin

.lista:
    MOV [estado_ini], AL
    MOV AH, 09h
    MOV DX, msg_estado
    INT 21h
    MOV AL, [estado_ini]
    CALL imprimir_hex8
    MOV AH, 09h
    MOV DX, msg_listo
    INT 21h

    ; (2) colocar el dato en el bus de datos
    MOV DX, DATA_PORT
    MOV AL, CARACTER
    OUT DX, AL

    ; (3) pulso STROBE. En el registro de control el bit 0 esta invertido por
    ;     hardware: escribir 1 baja la linea STROBE# (activa), escribir 0 la sube.
    MOV DX, CTRL_PORT
    IN  AL, DX
    OR  AL, STROBE_BIT      ; STROBE activo
    OUT DX, AL

    MOV CX, 0Fh             ; retardo minimo (> 1 us)
.delay: LOOP .delay

    AND AL, 0FEh            ; STROBE inactivo
    OUT DX, AL              ; DX sigue valiendo CTRL_PORT

    ; (4) esperar ACK# en bajo (bit 6 = 0), tambien con tope
    MOV CX, MAX_ESPERA
.wait_ack:
    MOV DX, STATUS_PORT
    IN  AL, DX
    TEST AL, ACK_BIT
    JZ  .ack_recibido
    LOOP .wait_ack
    MOV AH, 09h
    MOV DX, msg_sin_ack
    INT 21h
    JMP .fin

.ack_recibido:
    MOV AH, 09h
    MOV DX, msg_ack
    INT 21h

.fin:
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
estado_ini  DB 0
msg_estado  DB "Estado 0379h = $"
msg_listo   DB "h -> BUSY#=1, impresora lista.", 0Dh, 0Ah
            DB "Dato 41h ('A') enviado a 0378h y pulso STROBE aplicado.", 0Dh, 0Ah, "$"
msg_ocupada DB "Impresora ocupada: no se envio el dato.", 0Dh, 0Ah, "$"
msg_ack     DB "ACK# recibido.", 0Dh, 0Ah, "$"
msg_sin_ack DB "ACK# no observado (no hay periferico conectado).", 0Dh, 0Ah, "$"
