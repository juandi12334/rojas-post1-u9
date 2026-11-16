# Post-contenido Unidad 9 — Entrada y salida avanzadas: puertos, polling e interrupciones

**Estudiante:** Juan Diego Rojas Rey — código 1152512
**Materia:** Arquitectura de Computadores — Ingeniería de Sistemas, UFPS
**Repositorio:** `rojas-post1-u9` (una sola entrega para las dos partes)

Laboratorio guiado de la Unidad 9. La Parte 1 trabaja el acceso directo a puertos con `IN`/`OUT` (controlador de teclado 8042 y puerto paralelo LPT1), el polling con y sin timeout y el polling combinado de dos puertos. La Parte 2 instala un ISR propio para IRQ1, programa el IMR y el EOI del PIC 8259A, encadena con el handler original y mide el intervalo entre interrupciones con el contador de ticks del BIOS (`0040h:006Ch`).

## Objetivo, prerrequisitos y entorno

- **Objetivo:** programar E/S a bajo nivel en NASM (formato `.COM`) y comprobar su comportamiento en DOSBox, con evidencia en capturas y cuatro decisiones técnicas justificadas.
- **Prerrequisitos:** DOSBox 0.74 y NASM accesible desde el prompt; conocer `INT 21h`, segmentos y direccionamiento x86; para la Parte 2, la IVT, `INT 21h AH=25h/35h` y el flag IF.
- **Entorno usado:** DOSBox 0.74-3, con `cycles=fixed 8000` (salvo en `ITER_T`, donde se cambia a propósito), y NASM 2.15.05 para DOS (`nasm.exe` con `cwsdpmi.exe`) en `C:\NASM`. Los directorios de trabajo fueron `C:\U9P1` y `C:\U9P2`, como pide la guía. Todas las compilaciones de las capturas se hicieron dentro de DOSBox, y los `.COM` del repositorio son idénticos byte a byte a los que se generaron allí.
- Las teclas de las pruebas se enviaron como pulsaciones reales a la ventana de DOSBox (no se simularon desde el programa).

## Contenido

| Archivo | Descripción | Compilar y ejecutar |
|---|---|---|
| `TECL.ASM` | Parte 1, Paso 2: scancode por polling sobre 64h/60h | `nasm -f bin TECL.ASM -o TECL.COM` y `TECL` |
| `POLL_T.ASM` | Parte 1, Paso 3: polling con timeout (`MAX_RETRY`) | `nasm -f bin -dMAX_RETRY=5 POLL_T.ASM -o POLL_T.COM` y `POLL_T` |
| `LPT1.ASM` | Parte 1, Paso 4: envío de un carácter por LPT1 (protocolo centronics) | `nasm -f bin LPT1.ASM -o LPT1.COM` y `LPT1` (ver nota sobre el nombre) |
| `MULTI_ST.ASM` | Parte 1, Paso 5: polling combinado con OR (teclado + LPT1) | `nasm -f bin MULTI_ST.ASM -o MULTI_ST.COM` y `MULTI_ST` |
| `ITER_T.ASM` | Apoyo a la decisión técnica 1: iteraciones de polling en ~1 s | `nasm -f bin ITER_T.ASM -o ITER_T.COM` y `ITER_T` |
| `ISR_KB.ASM` | Parte 2, Paso 1: ISR propio para IRQ1 | `nasm -f bin ISR_KB.ASM -o ISR_KB.COM` y `ISR_KB` |
| `MASK_KB.ASM` | Parte 2, Paso 2: enmascarar IRQ1 con el IMR | `nasm -f bin MASK_KB.ASM -o MASK_KB.COM` y `MASK_KB` |
| `ISR_CHAIN.ASM` | Parte 2, Paso 3: ISR encadenado con el handler original | `nasm -f bin ISR_CHAIN.ASM -o ISR_CHAIN.COM` y `ISR_CHAIN` (ver nota) |
| `ISR_TIME.ASM` | Parte 2, Paso 4: intervalo entre interrupciones con `0040h:006Ch` | `nasm -f bin ISR_TIME.ASM -o ISR_TIME.COM` y `ISR_TIME` |
| `ISR_EOI.ASM` | Apoyo a la decisión técnica 3: ISR con y sin EOI | `ISR_EOI` (con EOI) o `ISR_EOI n` (sin EOI) |
| `capturas/` | Capturas de DOSBox de cada checkpoint | |

Opciones de compilación (`nasm -d`) de `POLL_T` y `MULTI_ST`: `-dMAX_RETRY=N` cambia el número de reintentos (por defecto `0FFFFh`) y `-dESPERA_PREVIA` enmascara IRQ1 unos 3 s antes del polling para dar tiempo de presionar una tecla y recorrer la ruta de "dato listo". Los `.COM` del repositorio son la compilación por defecto.

**Nota sobre los nombres de archivo:** `LPT1` es el nombre de un dispositivo de DOS, así que dentro de DOSBox `nasm ... LPT1.ASM -o LPT1.COM` se queda esperando al dispositivo y nunca termina; lo mismo con `ISR_CHAIN`, que tiene 9 caracteres y DOS solo admite 8. Por eso en las capturas esos dos programas aparecen como `LPTP1` e `ISR_CHN` (el mismo código). En el repositorio se conservan los nombres que pide la entrega.

---

# Parte 1 — Acceso directo a puertos

## Registros usados

**Controlador de teclado 8042**

| Puerto | Registro | Uso en el laboratorio |
|---|---|---|
| `60h` | Data Port | Scancode de la última tecla. Leerlo baja el flag OBF |
| `64h` | Status Register | Bit 0 = OBF (Output Buffer Full): hay un dato listo para leer |

El bit 7 del scancode indica si es un código *make* (0, tecla presionada) o *break* (1, tecla soltada): la tecla A genera `1Eh` al presionarla y `9Eh` al soltarla.

**Puerto paralelo LPT1** (puertos `0378h`–`037Ah`)

| Puerto | Registro | Bits usados |
|---|---|---|
| `0378h` | Data | D0–D7 hacia el conector |
| `0379h` | Status | bit 7 = BUSY# (1 = lista), bit 6 = ACK# (activo en bajo) |
| `037Ah` | Control | bit 0 = STROBE |

Como `0378h`–`037Ah` no caben en el operando inmediato de `IN`/`OUT` (solo llega a `0FFh`), esos accesos se hacen siempre con el puerto en `DX`.

## Cómo funcionan los programas

### `TECL.ASM`
Bucle de polling: `IN AL,64h` / `TEST AL,01h` / `JZ .poll` espera OBF=1, luego `IN AL,60h` lee el scancode y se imprime en hexadecimal junto con el valor de estado. Se hicieron dos ajustes respecto a la guía: el polling va entre `CLI` y `STI` (si no, el handler del BIOS de IRQ1 puede leer el puerto 60h antes y llevarse el scancode), y se descartan los códigos *break*. Esto último hizo falta de verdad: en la primera prueba el programa mostró `9Ch`, que es el código de soltar la tecla Enter con la que se lanzó el programa, y no la tecla pulsada. Con el filtro, al presionar A muestra `Estado 64h = 1Dh  Scancode (60h) = 1Eh`. Al final se vacía el buffer del BIOS, porque el IRQ1 ya estaba pendiente en el PIC y, si no, la letra aparecía luego en el prompt.

### `POLL_T.ASM`
Es el mismo polling pero con un contador `CX = MAX_RETRY` y `LOOP`: si CX llega a 0 sin OBF imprime el mensaje de timeout. Con `MAX_RETRY=5` y sin tocar el teclado aparece `Timeout: sin respuesta del dispositivo`. Con la opción `ESPERA_PREVIA` se enmascara IRQ1, se espera ~3 s con el contador de ticks, y al presionar una tecla en ese lapso el polling encuentra el dato (`Scancode leido: 1Eh`). También descarta los códigos *break* sin perder la cuenta de reintentos.

### `LPT1.ASM`
Sigue el protocolo centronics: (1) espera BUSY#=1 en `0379h`, (2) pone el dato `41h` en `0378h`, (3) da un pulso de STROBE en `037Ah` y (4) espera ACK# en bajo. Las esperas tienen un tope de reintentos para que el programa no pueda bloquearse. En el registro de control el bit 0 está invertido por hardware (escribir 1 baja la línea STROBE#), así que el pulso es `OR AL,1` para activarlo y `AND AL,0FEh` para soltarlo; en la guía el orden venía al revés. En DOSBox el puerto responde `87h` en `0379h` (bit 7 en 1: lista; bit 6 en 0: ACK), de modo que el programa termina de inmediato con `ACK# recibido`, sin errores de acceso ni bloqueo, aunque no haya impresora.

### `MULTI_ST.ASM`
Lee las dos banderas (OBF de `64h`; bit 7 de `0379h` normalizado con `SHR AL,7`), las guarda en BL y BH, y las combina con `OR`: el bucle solo continúa mientras el resultado es 0. Al salir examina BL y BH por separado e imprime el mensaje que corresponde a cada uno. Como DOSBox reporta LPT1 como lista desde el primer momento, la ejecución normal imprime solo `LPT1 listo (BUSY#=1).` y termina en la primera iteración. Para ver el caso de ambos mensajes se compila con `-dESPERA_PREVIA` y se presiona una tecla durante la pausa: imprime `Teclado listo (OBF=1).` y `LPT1 listo (BUSY#=1).`.

### `ITER_T.ASM` (apoyo)
Cuenta cuántas iteraciones de un bucle de polling (`IN AL,64h` + `TEST`) caben en 18 ticks del BIOS (~1 s reales), y se ejecuta con dos velocidades de CPU de DOSBox (`config -set "cpu cycles=fixed N"`).

## Checkpoints de la Parte 1 (capturas)

| Checkpoint | Captura 1 | Captura 2 |
|---|---|---|
| 1 — Lectura de scancode | [compilación](capturas/parte1/cp1_compilacion.png) | [ejecución con la tecla A](capturas/parte1/cp1_ejecucion.png) |
| 2 — Polling con timeout | [compilación con `MAX_RETRY=5`](capturas/parte1/cp2_compilacion.png) | [timeout y ruta de dato listo](capturas/parte1/cp2_ejecucion.png) |
| 3 — Escritura a LPT1 | [compilación](capturas/parte1/cp3_compilacion.png) | [ejecución](capturas/parte1/cp3_ejecucion.png) |
| 4 — Polling combinado con OR | [compilación](capturas/parte1/cp4_compilacion.png) | [ejecución normal y con tecla](capturas/parte1/cp4_ejecucion.png) |
| 5 — Decisiones técnicas | [`ITER_T` con CPU lenta](capturas/parte1/cp5_iteraciones_lento.png) | [`ITER_T` con CPU rápida](capturas/parte1/cp5_iteraciones_rapido.png) |

Resultados observados: `1Eh` para la tecla A; `Timeout` con 5 reintentos; `LPT1.COM` sin errores ni bloqueo; en `MULTI_ST` solo LPT1 sin tecla y ambos con tecla; y en `ITER_T`, 247 120 iteraciones por segundo con `cycles=fixed 2000` frente a 837 559 con `cycles=fixed 30000`.

---

# Parte 2 — ISR personalizado y PIC 8259A

## Conceptos aplicados

El PIC maestro entrega IRQ0–IRQ7 como INT 08h–0Fh, así que IRQ1 (teclado) es INT 09h. El IMR está en el puerto `21h` (bit en 1 = IRQ enmascarada, IRQ1 es el bit 1, máscara `02h`) y el EOI se envía al puerto `20h` (`MOV AL,20h` / `OUT 20h,AL`). Mientras el PIC no recibe el EOI, mantiene activo el bit de "en servicio" de esa IRQ y no despacha otras de igual o menor prioridad.

## Cómo funcionan los programas

### Instalación y restauración del vector (`ISR_KB`, `ISR_CHAIN`, `ISR_TIME`)
Los tres siguen el mismo esquema: `INT 21h AX=3509h` devuelve en `ES:BX` el handler actual y se guarda en `old_isr` (dos palabras: offset y segmento); `INT 21h AX=2509h` con `DS:DX = mi_isr` instala el propio; un bucle espera hasta contar 5 pulsaciones; y se restaura el vector original con `LDS DX,[old_isr]` + `AX=2509h`. Como `LDS` cambia DS, se envuelve con `PUSH DS`/`POP DS`; sin eso, el mensaje final se imprimía desde un segmento equivocado.

### `ISR_KB.ASM`
El ISR guarda AX, DX y DS, pone DS = CS, lee el scancode con `IN AL,60h`, imprime el mensaje, incrementa el contador y envía el EOI justo antes del `IRET`. Cada tecla genera dos interrupciones (make y break), por eso el ISR cuenta solo los códigos con el bit 7 en 0 (para que "5 teclas" sean 5 pulsaciones); el EOI se envía igualmente en las dos. Resultado: el mensaje `Tecla detectada por ISR propio` aparece exactamente 5 veces y luego `ISR restaurado. Fin del programa.`

### `MASK_KB.ASM`
Lee el IMR con `IN AL,21h`, lo guarda en la pila, pone el bit 1 con `OR AL,02h`, lo escribe, espera 55 ticks (~3 s) con `INT 1Ah` y restaura el IMR. Para que el efecto sea visible (el eco no se ve de todos modos mientras corre un programa), mide cuántas teclas hay en el buffer del BIOS (cabeza en `0040h:001Ah`, cola en `0040h:001Ch`) justo antes y 0,5 s después de desenmascarar. Presionando `x`, `y`, `z` durante el enmascaramiento: 0 teclas en el buffer con IRQ1 enmascarada y 3 después de restaurar. O sea que las pulsaciones no se pierden, se quedan en el 8042 hasta que IRQ1 se habilita.

### `ISR_CHAIN.ASM`
Cuenta la tecla y después llama al handler original simulando una interrupción: `PUSHF` + `CALL FAR [CS:old_isr]` + `IRET`. El handler del BIOS es quien envía el EOI, así que este ISR no lo envía. Resultado: aparecen cinco `[ISR_CHAIN] tecla registrada` y, al terminar, lo tecleado (`abcde`) aparece en el prompt de DOS, lo que demuestra que el sistema siguió recibiendo las teclas (con `ISR_KB`, que no encadena, el buffer del BIOS queda vacío).

### `ISR_TIME.ASM`
En cada pulsación lee la palabra baja del contador de ticks (`MOV AX,[ES:6Ch]` con `ES = 40h`), calcula la diferencia con la lectura anterior (`SUB BX,[ticks_prev]`, aritmética módulo 2^16, correcta aunque el contador dé la vuelta), envía el EOI apenas termina de leer y recién después imprime el número en decimal. Presionando las teclas con pausas de ~1,1 s, ~2,1 s, ~0,4 s y ~3,1 s se obtuvieron `20`, `39`, `7` y `57` ticks (la primera, `19`, es el tiempo desde que se instaló el ISR), es decir unos 18 ticks por segundo, como se esperaba.

### `ISR_EOI.ASM` (apoyo)
Instala un ISR que cuenta pulsaciones y, según el parámetro, envía o no el EOI. El programa principal mientras tanto ejecuta un contador de 32 bits (el "trabajo útil") hasta recibir 3 teclas o pasar 6 s. Con EOI: el ISR atendió las 3 teclas y el bucle principal dio 2 051 651 iteraciones. Sin EOI (`ISR_EOI n`): atendió solo 1 de las 3 teclas y el teclado dejó de responder hasta que el programa envió el EOI manualmente al final.

## Checkpoints de la Parte 2 (capturas)

| Checkpoint | Captura 1 | Captura 2 |
|---|---|---|
| 1 — ISR propio para IRQ1 | [compilación](capturas/parte2/cp1_compilacion.png) | [5 pulsaciones](capturas/parte2/cp1_ejecucion.png) |
| 2 — Enmascaramiento con el IMR | [compilación](capturas/parte2/cp2_compilacion.png) | [ejecución](capturas/parte2/cp2_ejecucion.png) |
| 3 — Encadenamiento | [compilación (`ISR_CHN`)](capturas/parte2/cp3_compilacion.png) | [ejecución](capturas/parte2/cp3_ejecucion.png) |
| 4 — Medición con ticks | [compilación](capturas/parte2/cp4_compilacion.png) | [ejecución](capturas/parte2/cp4_ejecucion.png) |
| 5 — Decisiones técnicas | [`ISR_EOI` con EOI](capturas/parte2/cp5_con_eoi.png) | [`ISR_EOI n` sin EOI](capturas/parte2/cp5_sin_eoi.png) |

---

# Decisiones técnicas

## Decisión 1 (Parte 1) — ¿Polling sin límite o polling con timeout configurable?

El bucle sin límite de `TECL.ASM` es aceptable cuando el dispositivo tiene garantizado responder, por ejemplo en un programa de demostración como este laboratorio, donde el propio estudiante va a presionar la tecla; si por algún motivo no responde, basta con reiniciar. El timeout de `POLL_T.ASM` es preferible, y en la práctica indispensable, cuando el programa no puede asumir que el dispositivo responderá (un periférico que puede estar desconectado, una impresora sin papel, hardware que falla), porque convierte un bloqueo indefinido en un error que se puede reportar. El costo es el riesgo contrario: si `MAX_RETRY` es demasiado pequeño (por ejemplo 5h en vez de 0FFFFh), el programa declara timeout aunque el dispositivo sí fuera a responder un poco más tarde, es decir, produce falsos timeouts con dispositivos lentos pero funcionales. Además, el contador mide iteraciones, no tiempo: lo que tarda una iteración depende de la velocidad de la CPU o del emulador. Con `ITER_T` se midió que en 1 s real caben 247 120 iteraciones con `cycles=fixed 2000` y 837 559 con `cycles=fixed 30000`, de modo que el mismo `MAX_RETRY` esperaría tiempos muy distintos según la máquina. El contador de ticks de `0040h:006Ch`, que sube unas 18,2 veces por segundo por la IRQ0 del timer, mide tiempo real sin importar qué tan rápido se ejecute el bucle que lo consulta, y por eso es la referencia correcta cuando el límite debe estar en segundos.

## Decisión 2 (Parte 1) — ¿Combinar banderas de dos puertos con OR o verificarlas por separado?

En DOSBox el puerto `0379h` responde `87h`, así que el bit de "listo" de LPT1 vale 1 de forma permanente. Con eso, el `OR` de `MULTI_ST.ASM` es distinto de cero desde la primera iteración, el bucle `.poll` termina de inmediato sin importar el teclado, y la ejecución normal imprime solo `LPT1 listo`: la espera combinada no espera nada, porque un dispositivo siempre listo anula su utilidad. Solo cuando el teclado ya tiene una tecla pendiente (caso que se forzó con `ESPERA_PREVIA`) se ven los dos mensajes. Después de salir del bucle es necesario volver a examinar BL y BH por separado, porque el `OR` descarta la información de cuál bandera causó la salida: AL vale 1 tanto si fue el teclado, como si fue LPT1, como si fueron los dos, y sin las banderas individuales el programa no sabría a quién atender. Si en lugar de `OR` se usara `AND`, el programa esperaría a que ambas condiciones se cumplan a la vez; eso tiene sentido en una sincronización tipo rendezvous, por ejemplo no enviar un carácter a la impresora hasta que el usuario haya presionado una tecla y la impresora esté lista. El `OR` sirve para "lo primero que ocurra" y el `AND` para "las dos cosas a la vez".

## Decisión 3 (Parte 2) — ¿En qué punto del ISR debe ir el EOI?

El EOI le avisa al PIC que la interrupción terminó; mientras no llega, el PIC mantiene en servicio esa IRQ y no despacha otras de igual o menor prioridad. En `ISR_KB.ASM` el EOI va al final, después de imprimir con `INT 21h`; si esa impresión tarda varios milisegundos, durante todo ese lapso las demás IRQ de prioridad menor o igual que quedaron pendientes en el PIC no pueden despacharse, lo que aumenta su latencia. Como el ISR no ejecuta `STI`, la CPU mantiene IF=0 hasta el `IRET`, así que enviar el EOI temprano no habilita por sí solo la reentrada de IRQ1: esa seguiría bloqueada por IF=0, y solo sería posible si el código además rehabilitara las interrupciones. Hay que distinguir entonces "permitir que el PIC despache otras IRQ pendientes", que depende del EOI, de "permitir que IRQ1 reentre", que depende de IF. Lo que gana el EOI temprano es no retrasar a las otras IRQ (por ejemplo cuando algo dentro del ISR, como las rutinas de DOS, vuelve a habilitar interrupciones). Por eso `ISR_TIME.ASM` lo envía apenas termina el trabajo estrictamente necesario sobre el hardware (leer el scancode y los ticks) y deja la impresión para después, que es la práctica recomendada. El caso extremo se comprobó con `ISR_EOI n`: sin EOI, el ISR atendió solo 1 de 3 teclas y el teclado quedó bloqueado hasta que se envió el EOI a mano. Enviarlo demasiado tarde retrasa a las demás IRQ y no enviarlo bloquea el sistema.

## Decisión 4 (Parte 2) — ¿Polling o interrupción para el mismo dispositivo?

El polling de `TECL.ASM` ocupa el 100 % de la CPU en un busy-wait mientras no hay tecla, así que es inaceptable en cualquier programa que deba seguir haciendo trabajo útil mientras espera: un juego o programa que anima la pantalla, atiende otro periférico o reproduce sonido no puede quedarse dando vueltas en `.poll`. Con el ISR, el programa principal sigue ejecutándose y solo se interrumpe cuando ocurre el evento; en `ISR_EOI` el bucle principal alcanzó 2 051 651 iteraciones de trabajo mientras esperaba las teclas, algo que con el polling bloqueante habría sido cero. En latencia también gana el ISR: el hardware activa la línea IRQ1 y la CPU salta al handler en cuanto termina la instrucción en curso, mientras que el polling solo se entera cuando el programa vuelve a ejecutar el `IN AL,64h`, y si el programa está ocupado en otra cosa, la tecla espera. Para un dispositivo lento y esporádico como el teclado, donde pueden pasar minutos entre eventos, mantener la CPU girando en un bucle durante todo ese tiempo es un desperdicio de ciclos (y de energía) que el esquema por interrupciones evita por diseño. El polling queda para esperas muy cortas, donde instalar y restaurar un ISR no se justifica, o para dispositivos que no generan interrupciones.

---

# Observaciones sobre el código de la guía

Al ensamblar y ejecutar los ejemplos en DOSBox hubo que ajustar varias cosas:

- **`IN`/`OUT` con puertos mayores a `0FFh`:** `IN AL, 0379h` o `OUT 037Ah, AL` no son válidos (el operando inmediato es de 8 bits; NASM avisa "byte data exceeds bounds" y trunca a `79h`). Hay que cargar el puerto en `DX`.
- **Polaridad de STROBE:** en el registro de control, escribir 1 en el bit 0 activa la línea (invertida por hardware); en la guía el comentario decía lo contrario.
- **Nombres de archivo en DOS:** `LPT1` es un dispositivo y `ISR_CHAIN` excede los 8 caracteres (ver la nota de nombres arriba).
- **Orden de secciones:** en formato binario con `ORG`, lo primero que aparece en el archivo es lo que ejecuta la CPU; `MASK_KB` de la guía ponía los mensajes antes de `start` y se habrían ejecutado como código. Aquí todas las secciones `.text` van primero y `.data` al final.
- **`LDS DX,[old_isr]`** modifica DS; se protege con `PUSH DS`/`POP DS` antes de imprimir el mensaje final.
- **Códigos break:** cada tecla produce dos interrupciones; los ISR cuentan solo los make y envían el EOI en ambos. En los programas con polling se descartan los break (el de Enter apareció como `9Ch`).
- **`CLI` durante el polling de teclado:** evita que el handler del BIOS consuma el scancode antes que el programa.
- **Espera de 3 s en `MASK_KB`:** se usó `SUB` + `JB` (sin signo) en vez de `CMP` + `JL`, que falla cuando el contador de ticks pasa de 7FFFh.
- **Teclas sueltas en el prompt:** los programas que dejan IRQ1 pendiente vacían el buffer del BIOS al terminar.
