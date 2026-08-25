# SOUND_SPEC — Sonido y haptics (estilo Raycast / The Browser Company)

**Goal del usuario:** "meterle un sonido y haptics buenos como hace the browser
company o raycast". Los sonidos UI de Arc/Raycast son **cortos, sutiles y
confirmatorios** — nunca estridentes, ~30-90ms, decaimiento exponencial, tonos
de media-alta frecuencia (500-1600Hz), con un **haptic** simultáneo en el
trackpad (Force Touch).

## Principios

1. **Sutileza**: volumen bajo (~0.2), duración ≤ 90ms, decaimiento exponencial
   (ataque rápido, sin clicks duros).
2. **Confirmación, no decoración**: cada transición de estado significativa
   tiene un sonido/haptic único y legible por el usuario.
3. **Sin assets externos**: los WAV se generan **programáticamente** (función
   pura, testeable) → sin recursos, sin bundle.
4. **No romper nada**: todo lo de TRANSITION_SPEC / CONTENT_SPEC queda intacto.

## Mapa de feedback (estado → sonido + haptic)

| Evento | Sonido (función pura) | Haptic |
|---|---|---|
| Expandir isla | `chirp(f0:780→f1:1150, 70ms)` subida suave | `.levelChange` |
| Colapsar isla | `chirp(f0:1150→f1:780, 70ms)` bajada | `.levelChange` |
| Seleccionar opción | `tick(1350Hz, 30ms)` clic corto | `.generic` |
| Enviar texto libre | `confirm(1600Hz, 55ms)` dos tonos | `.generic` |
| Descartar / cancelar | `thud(500Hz, 60ms)` grave corto | `.levelChange` |

Haptics: `NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)`.
Solo se siente en trackpads Force Touch — en otros input degrada silencioso
(comportamiento de macOS, no un error).

## Función pura WAV (testeable)

```
makeWav(f0: CGFloat, f1: CGFloat, duration: CGFloat, amplitude: CGFloat = 0.2)
  -> Data   // WAV PCM16 mono 44100Hz, RIFF válido, decaimiento exp

makeFeedback(event: FeedbackEvent) -> (wavData: Data, hapticKind: HapticKind)
```

### Invariantes WAV (test)
- Header "RIFF" + "WAVE" + "fmt "(PCM) + "data"
- mono (1 canal), 44100 Hz, 16 bits → byteRate = 44100 * 2
- dataSize = duration * 44100 * 2
- amplitud pico ≤ 0.25 (sutil)
- primer/último sample ≈ 0 (sin snaps; ataque/decaimiento suave)

## Implementación (sin AppKit en la lógica)

- `SoundSpec.swift`: lógica pura (generación WAV + mapa de feedback) — testeable
  con swiftc (Foundation + CoreGraphics para CGFloat).
- `views.swift`: el AppDelegate reproduce `NSSound(data:)` del WAV resultante y
  ejecuta el haptic en los hooks de transición (expandir / colapsar / seleccionar
  / submit / dismiss). `NSSound(data:)` toca WAV PCM16 sin assets.

## Corrección v2 — feedback SOLO en eventos discretos (best practices Apple HIG)

**Problema reportado**: "while I move the cursor on the window it sounds and
vibrates. That is not a good ux."

**Causa raíz**: `playFeedback(.expand/.collapse)` se disparaba desde el observer
de `isExpanded`, que cambia continuamente con el mouse monitor (hover →
expand/collapse → hover...). Vibraba/sonaba en CADA movimiento del cursor.

**Principios aplicados (Apple HIG "Playing haptics")**:
- **"In most apps, prefer playing short haptics that complement DISCRETE events."
  ** → el feedback solo se reproduce en acciones únicas del usuario, nunca en
  estados derivados del hover/mouse.
- **"Avoid overusing haptics"** → no reproducir en cada transición de hover.
- **"Build a clear, causal relationship between each haptic and the action"**
  → sonido = consecuencia de una acción concreta que el usuario inició.

**Nuevo mapa (v2)**:

| Evento | Tipo | Feedback |
|---|---|---|
| Seleccionar una opción | DISCRETO (click en opción) | tick + haptic generic |
| Enviar texto libre | DISCRETO (Enter) | confirm + haptic generic |
| Descartar | DISCRETO (botón) | thud + haptic levelChange |
| Expandir / colapsar (hover) | CONTINUO — NO | **silencio** (sin sonido ni haptic) |

**Regla**: `NSHapticFeedbackManager` y `NSSound` se llaman EXCLUSIVAMENTE desde
acciones del usuario con un único disparo (selectOption, sendFreeText, dismiss).
El mouse monitor y el observer de `isExpanded` NO reproducen nada.

## Corrección v3 — sin congelamiento en el primer sonido (cache pre-cargado)

**Problema reportado**: "la primera vez que hay un sonido la ui se congela un
momento."

**Causa raíz**: `playFeedback` generaba el WAV (sintetiza samples) y creaba
`NSSound(data:)` **en el momento del primer click** — el init del audio engine
con WAV grande bloquea el main thread → la UI se congela esa primera vez.

**Solución (best practice de audio)**: pre-generar y cachear todos los sonidos
ANTES de que se necesiten. El play posterior es solo tocar un `NSSound` ya
creado (sin síntesis ni init en el hot path).

**Requisito**:
- `SoundLibrary` pre-construye los 5 NSSound (expand/select/submit/dismiss/
  newQuestion) una única vez en el arranque (fuera del hot path).
- `playFeedback(event)` solo TOCA el sonido cached + el haptic. Nada pesado en
  el main thread al reproducir.
- La generación pura del WAV queda testeable (SoundSpec.makeWav) y se ejecuta
  una sola vez por evento.

### Lógica pura testeable (cache de generación única)

```
FeedbackCache.store(events: [FeedbackEvent])   // pre-genera UNA vez cada WAV
FeedbackCache.sound(for: event) -> (wav: Data, haptic: HapticKind)
  // segunda llamada NO vuelve a sintetizar (identidad/contador)
```

## Optimización v4 — sin lag residual en los sonidos (best practices Apple)

**Problema reportado**: "Creo que los sonidos hicieron que la aplicación fuera
más lenta en general. Optimiza."

**Investigación** (Apple dev forums #98401, TypeWhisper#1026, SO#43004731):
- NSSound.play() es asíncrono, pero la **adquisición del hardware de audio +
  buffering ocurre en el PRIMER play() de cada sonido** — I/O en el hot path
  → lag/freeze perceptible la primera vez de cada sonido.
- Best practice: AVARÁUDIO pre-carga buffers y hardware ANTES del hot path
  (`prepareToPlay()`); en macOS, para NSSound la técnica equivalente es
  **pre-calentar al arranque**: un `play()` + `stop()` inmediato durante el
  `applicationDidFinishLaunching` adquiere el device y puebla buffers FUERA del
  hot path.

**Cambio (solo en el arranque)**: tras construir cada NSSound, pre-calentar
una vez:
```
snd.play(); snd.stop()     // adquiere hardware + buffers, fuera del click
```
Los `play()` posteriores solo re-disparan un buffer ya residente → sin lag.
NO cambia el comportamiento de reproducción (v3 intacta).

## Optimización v5 — tres cuellos medidos con timing (datos reales)

Instrumentación (logs `AINOCH TIMING`) tras las acciones reales del usuario:

| Acción | Costo medido | Causa |
|---|---|---|
| Abrir input (`activeSink`) | ~106ms | `NSApp.activate(ignoringOtherApps: true)` trae la app al frente agresivamente (caro) |
| Sonido `play=dismiss` | ~67ms / 16ms | `NSHapticFeedbackManager.perform(.now)` BLOQUEA el main thread hasta ejecutarse |
| Typear (monitor) | ~0.02ms/tecla | barato en nuestro lado |

**Fixes (basados en datos + best practices):**

1. **Abrir input**: el panel es `nonactivating` — no necesita `activate(ignoringOtherApps: true)`
   (que es lo caro). Cambiar a `_ = active; DispatchQueue.main.async { NSApp.activate(
   ignoringOtherApps: true) }` difiere el cost fuera del sink crítico, o mejor
   `makeKeyAndOrderFront` puro (nonactivating ya da el teclado sin robar la app).
2. **Haptic**: Apple documenta `performanceTime: .now` = "as soon as possible"
   (bloquear hasta el próximo screen update). `.default` = en el PRÓXIMO update
   de pantalla, SIN bloquear. Usar `.default`.
3. **Typear**: el `@Published textInputValue` re-renderiza TODA la isla con cada
   carácter. Aislar el TextField en una sub-vista con `@State` local (se sincroniza
   al modelo SOLO al submit → re-render del campo, no de la isla).

Re-medir tras los cambios: `activeSink` y `play` deben caer a <5ms.

## Optimización v6 — foco del input sin perder atajos (feedback usuario)

Tras v5, al abrir el input: "no funciona ni cmd a ni las flechas de arriba
abajo. Tampoco el escape."

**Causa**: quité `NSApp.activate` por completo → el panel es key pero la APP no
está activa → los atajos de nivel app (Cmd+A = menú Edit, flechas/ESC dentro del
campo) no se resuelven.

**Fix (equilibrio correcto)**:
- Foco INMEDIATO y barato al abrir: `makeKey()` + `makeFirstResponder` (el
  campo recibe el cursor al instante; sin activate caro en el hot path).
- `NSApp.activate(ignoringOtherApps: true)` DIFERIDO con `DispatchQueue.main.async`
  → la app se activa al próximo tick (habilita Cmd+A, flechas, ESC) SIN bloquear
  el runloop al abrir.

El costo del activate se mueve fuera del camino crítico → sin stutter + atajos OK.

## Fix v6c — Cmd+A dentro del input (feedback usuario)

"escape works but cmd a do not."

**Causa**: Cmd+A se resuelve por el MENÚ Edit (Select All). La app es
`.accessory` SIN menú principal → el key equivalent de Cmd+A no está enrutado
por el sistema para el campo (ESC sí funciona porque lo capturamos por
keyCode). Cmd+A no llega a nuestro resolveKey (no es una tecla "limpia").

**Fix**: en el monitor de keyDown, ANTES de resolver, si hay modo texto activo
y `modifierFlags.contains(.command)` con keyCode 0 (A) → `selectAll(nil)` sobre
el field editor real del campo y consumir el evento.

```
if textInputActive && cmd && keyCode==0:
   editor = window.fieldEditor(false, for: contentView)  // NSTextView
   editor.selectAll(nil)
   return nil
```

## Fix v6b — ESC/atajos dentro del input de texto (feedback usuario)

Tras v6, en el input "no funcionan los atajos... tampoco el escape".

**Causa (2 bugs en `KeyboardSpec.resolveKey`)**:
1. El `guard !isTextInputActive else { return .none }` estaba ANTES del chequeo
   de ESC (keyCode 53) → en modo texto ESC caía en `.none` y el monitor nunca
   llegaba al branch `.collapse` que cierra el input (`.closeTextMode`).
2. El foco del TextField solo se activaba en el click (textFieldFocused=true),
   no al abrir por Enter (`openTextMode`) → Cmd+A/flechas no aplicaban porque el
   campo no era first responder real al abrir por teclado.

**Fix**:
1. **ESC SIEMPRE se resuelve** (incluso en modo texto): `keyCode == 53 →
   .collapse`, y el branch `.collapse` ya hace `.closeTextMode` si hay modo
   texto activo (KEYBOARD_SPEC v2). En modo texto las demás teclas (Cmd+A,
   flechas, caracteres) devuelven `.none` → se dejan pasar al TextField.
2. En la vista: `.onChange(of: model.textInputActive)` activa `textFieldFocused`
   cuando se abre el input (cubre Enter Y click) → el campo es first responder
   real → Cmd+A y flechas funcionan.
