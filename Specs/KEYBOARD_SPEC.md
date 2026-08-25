# KEYBOARD_SPEC — Navegación con teclado

**Solicitud del usuario:** "implementemos navegación con teclado".

## Objetivo

Cuando la isla está expandida, el usuario puede operarla **solo con el teclado**:
navegar el stack, seleccionar una opción, descartar. Igual que Raycast/Arc:
el panel flotante acepta teclas SIN arrebatarle la app activa al usuario.

## ROBO DE FOCO (la parte delicada)

El NSPanel es `nonactivatingPanel` (estilo borderless). Con `canBecomeKey
dinámico` (CONTENT_SPEC 2b) + `makeKey()` al expandir, el panel se vuelve key y
**recibe las teclas sin desactivar la app del usuario** (los paneles nonactivating
toman el key SOY el primer responder sin robar la app activa). Así:
- Expandida → las teclas van a la isla (navegar/seleccionar).
- Colapsado → el panel no es key → el teclado sigue yendo a la app del usuario.
- Modo texto → el TextField es el primer responder (las acciones globales del
  teclado se IGNORAN para no interferir mientras se escribe).

## Mapa de teclas (cuando isExpanded && !textInputActive)

| Tecla | Acción |
|---|---|
| `1`–`9` | Seleccionar opción N (selectOption) |
| `↑` / `↓` | Mover el HIGHLIGHT entre las opciones (patrón Raycast) |
| `←` / `→` | Pregunta anterior / siguiente en el stack (sin descartar) |
| `Esc` | **Back/dismiss contextual** (ver abajo) |
| `Enter` | Confirmar la opción resaltada: `selectOption(n)` para una opción normal, **abrir el input de texto si es "Type something"** |
| (cualquier otra) | Ignorar |

## ESC = back contextual (corrección v2, del usuario)

El usuario pidió: "Escape debería permitirme volver atrás o hacer dismiss si
estoy en el inicio."

- Modo texto ACTIVO (nivel interno) → ESC **cierra el input y vuelve a las
  opciones** (back).
- Sin modo texto (nivel raíz, viendo la pregunta) → ESC **dismiss** la pregunta
  actual (se mueve al final del stack, ver STACK_SPEC v2). "Estoy en el inicio"
  = nivel raíz sin estados internos abiertos.

```
onEscape(textInputActive) →
   textInputActive ? .closeTextMode   // back: volver a las opciones
   :                .dismissCurrent   // inicio: dismiss de la pregunta actual
```

## Enter en "Type something" abre el input (corrección del usuario)

"Cuando le doy enter a type something no se abre el text box."

El `Enter` del highlight NO debe enviar el número si la opción es de texto
libre: debe activar el modo texto (igual que el click sobre "Type something").
Se reusa `ContentState.onOptionTap` con el título de la opción resaltada →
`.enterTextMode` abre el input; `.selectOption(n)` envía el número.


## Highlight vertical de opciones (navegación ↑↓)

### Comportamiento (patrón Raycast / menuterminal)

- Las flechas `↑`/`↓` mueven un **highlight** de selección entre las opciones de
  la pregunta actual (índice 1..N).
- La opción highlighteada se resalta visualmente (fondo más claro + borde), de
  forma DISTINTA al hover del mouse (que es un realce sutil) — el highlight de
  teclado es el "cursor de selección".
- `Enter` confirma la opción highlighteada (selectOption(n)).
- Las flechas `↑`/`↓` (y Enter) son **iguales a las numéricas**: operan la
  selección; no navegan el stack.
- Si el usuario hace hover/clicks con el mouse, el highlight de teclado se
  mantiene (es independiente; el click selecciona siempre).
- El highlight se resetea a la opción 1 al cambiar de pregunta (navegar stack).

### Lógica pura testeable

```
selectedOption: Int?   // 1..N, nil = nada highlighteado (default)

moveHighlightUp(current, count)      → current>1 ? current-1 : 1
moveHighlightDown(current, count)    → current<count ? current+1 : count
highlightEnter(current)              → selectOption(current)
```

### Vista

`OptionRowView` recibe `isHighlighted` (además de `isHovered`): fondo más
claro / borde cuando highlighteado. El highlight se dibuja desde el modelo
(`keyboardSelection`).

Notas:
- Las teclas numéricas mapean a `selectOption(n)` (misma acción que el click).
- `←`/`→` navegan el stack (StackLogic.stackPrev/Next) — consistente con los
  botones ◀ ▶ ya existentes.
- `Esc` colapsa (no descarta): en compacto el usuario ve el contador y puede
  re-expandir. (Descartar sigue siendo el botón "Descartar" o el dismiss.)

## Lógica pura (testeable)

```
enum KeyAction { case selectOption(Int), prevQuestion, nextQuestion,
                 collapse, none }

resolveKey(char, isExpanded, isTextInputActive) -> KeyAction
  - !isExpanded            → .none            (colapsado: no roba teclas)
  - isTextInputActive      → .none            (escribiendo: no interferir)
  - "1".."9"               → .selectOption(n)
  - "←"/left               → .prevQuestion
  - "→"/right              → .nextQuestion
  - ESC                    → .collapse
  - otra                   → .none
```

## Implementación (AppDelegate)

- `NSEvent.addLocalMonitorForEvents(matching: .keyDown)`.
- Al expandir: `win.makeKey()` (el panel ya es key-capable solo cuando
  `textInputActive`, extender a cuando expandido → ajustar `canBecomeKey`).
- `canBecomeKey` = `isExpanded || textInputActive` (key-capable mientras la
  isla está abierta, suficiente para recibir teclas; al colapsar vuelve a no
  robar).
- El monitor NO consume el evento salvo que lo resuelva a una acción real
  (retorna nil / deja pasar). En selectOption se consume para que la tecla
  numérica no llegue a la app subyacente.
- Al colapsar: `win.resignKey()` para liberar.
