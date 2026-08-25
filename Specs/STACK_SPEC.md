# STACK_SPEC — Múltiples preguntas a la vez + feedback de pregunta nueva

**Solicitudes del usuario:**
1. "También me gustaría [un sonido] cuando llega una nueva pregunta."
2. "No hemos pensado la ux cuando hay varias preguntas a la vez."

## Referencia (Apple HIG, Live Activities)

"When multiple Live Activities are active, the system uses the **minimal**
presentation... one attached to the island, the other detached." → para
múltiples ítems activos el sistema usa un contador/segunda isla y el detalle en
la presentación expandida. Para nuestro caso (harnesses con preguntas en
paralelo) la navegación debe existir DENTRO de la vista expandida.

## Requisito 1 — Feedback cuando llega una pregunta NUEVA (discreto)

**Es un evento discreto legítimo** (una pregunta nueva realmente aparece), no un
estado continuo. Sigue las best practices de haptics (SOUND_SPEC v2: causal,
evita overuse).

- **Detección**: el poll compara el conjunto de eventos con el anterior. Si
  aparece un evento nuevo (pane_id/agente que no estaba), se reproduce
  `makeFeedback(.newQuestion)` una vez.
- **SOUND_SPEC v2** lo agrega al mapa: `newQuestion` = "ping/tick" suave +
  haptic `generic` — qué da la sensación de "llegó algo" sin saturar.

| Evento | Tipo | Feedback |
|---|---|---|
| Nueva pregunta aparece | DISCRETO (realmente nueva) | ping suave + haptic generic |

**Anti-spam**: solo una vez por pregunta nueva real (no en cada poll; se
deduplica por clave del evento). Se ignora la primera carga inicial (el arranque
no debe sonar).

## Requisito 2 — UX de múltiples preguntas (stack)

Modelo: `events: [NotchEvent]` (ya existe). `current = events.first` muestra la
primera. Falta navegación e indicador de progreso.

### Diseño (basado en minimal + expanded del HIG)

- **Compact**: se mantiene el badge de contador (`stackCount`) — "hay N
  pendientes" de un vistazo. (Opción HIG minimal: si N==1 no mostrar badge.)
- **Expanded**:
  - Header muestra progreso: `"pi blocked • 2 de 3"` (índice actual de total).
  - **Navegación ◀ ▶**: botones para moverse por el stack SIN descartar.
    - `Ver anterior` / `Ver siguiente` desplazan `stackIndex` dentro de [0, n-1].
    - No hay wrap: en el borde el botón se deshabilita/atenúa.
  - Responder o descartar la pregunta actual: elimina ese ítem y avanza a la
    siguiente (comportamiento actual con `removeFirst`, salvo que ahora puede
    eliminar en cualquier índice del stack).

### Estado y funciones puras (testeable)

```
stackIndex: Int = 0                // cuál evento se muestra (0 = primera)

func stackTotal(events) -> Int     // events.count
func stackCurrent(events, i) -> Event?  // events[safe: i]
func stackCanPrev(i) -> Bool       // i > 0
func stackCanNext(i, n) -> Bool    // i < n-1
func stackPrev(i) -> Int           // max(0, i-1)
func stackNext(i, n) -> Int        // min(n-1, i+1)
func stackLabel(i, n) -> String    // "\(i+1) de \(n)"
```

`stackIndex` se resetea a 0 cuando el stack se vacía o cambia la pregunta
referencial. Tras responder/descartar en `i`, el índice se ajusta:
`safeGuard(i, afterRemovingAt: i) = min(i, n-1)` (clamp, no sale del rango).

## Verificación

- Test puro de las funciones de stack (navegación, bordes, label, clamp tras
  remoción).
- Test puro de detección de pregunta nueva (nuevo evento → feedback; repetido →
  no; carga inicial → no).
- Runtime: llega una pregunta y suena el ping (una vez); con varias preguntas,
  el header muestra "n de N" y ◀▶ navegan sin descartar; al responder la última
  queda "1 de 1" y luego silencio.

## Corrección v2 — el dismiss NO borra, mueve al final (del usuario)

"Las dismissed no se borran sino que se mueven al final."

**Comportamiento anterior (v1)**: `dismiss()` hacía `events.remove(at:)` — la
pregunta descartada se perdía del stack.

**Requisito**: descartar una pregunta la **mueve al final** del stack (no se
pierde; se puede volver a ella con → o re-aparece tras hacer el ciclo). El
índice actual avanza a la siguiente pregunta.

```
dismissMoveToEnd(events, i) → (nuevoEvents, nuevoIndex)
   item = events[i]              // sacar
   events = events[..<i] + events[i+1..] + [item]   // re-apendar al final
   nuevoIndex = eventos.count > 0 ? min(i, count-1) : 0
```

Función pura testeable:

```
dismissIndexAfterMoveToEnd(currentIndex, count) -> Int
   // si quedan eventos, el índice apunta al siguiente (min(i, count-1))
   // si vacío → 0
```

`safeGuard` y `dismissIndexAfterMoveToEnd` cubren ambos.
