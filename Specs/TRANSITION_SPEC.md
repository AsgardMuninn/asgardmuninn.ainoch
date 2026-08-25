# SPEC — Transición del notch (compact ↔ expanded)

**Problema observado (2026-08-24):** "baila de un lado a otro apareciendo desde abajo".

**Causa raíz:** la transición hoy interpola entre DOS contenedores distintas
(compact = HStack de 2 pills con hueco; expanded = isla sólida) vía
`matchedGeometryEffect`, y además la NSPanel se redimensiona (`setFrame`) a la
vez que la forma SwiftUI anima → dos fuentes de movimiento desincronizadas y un
ancla de interpolación que barre el notch de lado a lado.

**Principio correcto (Dynamic Island / Live Activities HIG):**
una sola pieza que **emerge del notch hacia abajo**. El notch es el origen
inmóvil; la isla crece únicamente en dirección vertical hacia abajo. Nada de lo
que tenga posición en la pantalla se mueve horizontalmente.

## Invariantes (lo que la transición NUNCA debe romper)

1. **El top de la isla está fijo** en el borde superior de la pantalla
   (`top = screenH`). La isla crece hacia abajo; su borde superior NO baja.
2. **El centro horizontal está fijo** en el centro del notch
   (`centerX = notchCenterX`). La isla se ensancha simétricamente; su centro NO
   se desplaza. → Sin "bailar de lado a lado".
3. **Top-to-bottom, no left-to-right**: en cualquier instante de la transición,
   la Y del borde superior = screenH (invariante 1). El bottom baja a medida que
   `h` crece. Nunca aparece desde abajo (no hay fase donde `top < screenH - epsilon`).
4. **Un solo dueño de la animación**: solo la FORMA SwiftUI se anima. La NSPanel
   se reposiciona SIN animación propia (`setFrame animate:false`) para no pelear.

## Interpolación determinista (función pura `islandFrame(progress:)`)

Sea `t` = progreso (0 = compact, 1 = expanded):

```
w(t) = lerp(312, 560, t)          // ancho de la isla (compact → expanded)
h(t) = lerp( 32, 380, t)          // alto de la isla
x(t) = notchCenterX - w(t) / 2    // centro horizontal SIEMPRE en el notch
top  = screenH                    // CONSTANTE (invariante 1)
y(t) = top - h(t)                 // bottom baja con h, top no se mueve
```

**Aplicar esto a UN solo contenedor `island`** (no a dos branches): el frame de
la isla usa `islandFrame(model.isExpanded ? 1 : 0)`, y tanto compact como
expanded son CONTENIDO DENTRO de esa isla (recortado al clipShape), no contenedores
hermanos que se intercambian. El matchedGeometryEffect se elimina.

## Especificación de tamaños (verificada en hardware real)

| Estado | window (NSPanel) | isla (forma negra) | top |
|---|---|---|---|
| compact  | x=600, y=950, 312x32 | 312x32 | screenH=982 |
| expanded | x=476, y=602, 560x380 | 560x380 | screenH=982 |

Ambos: `centerX = 756`, `top = 982`.

## Clickeable (requisito del usuario)

La NSPanel se redimensiona al estado visible (`windowW/H = shapeW/H`) de modo
que sólo la caja de la isla intercepta clicks. El resto del desktop queda
libre. Sin embargo, el cambio de tamaño de la ventana NO se anima (`animate:false`),
porque la única animación es la forma SwiftUI (invariante 4).

## Criterio de aceptación (visual)

1. Al hacer hover sobre las pills compactas, la isla baja desde el notch
   creciendo en alto, manteniendo su centro fijo. NO se ve movimiento horizontal.
2. Al salir, colapsa hacia arriba (el bottom sube), top fijo.
3. En ningún frame la isla "aparece desde abajo" ni su top baja.
4. La menu bar a los lados del notch es clickeable en todo momento.
5. **La animación de crecimiento ARRANCA desde el notch** (borde superior de la
   ventana), no desde el centro de la ventana. El ancla del crecimiento es el
   TOP del hosting view (no debe quedar centrado verticalmente).

## Implementación del ancla (requisito 5)

El borde superior se pinza con el frame `hostingLocalFrame` cuyo top queda en
`y=0` (pego al borde superior del hosting). **El hosting view NO es de tamaño
fijo**: su tamaño es el de la ISLA en el estado actual (312x32 colapsado /
560x380 expanded). Si el hosting fuera SIEMPRE 560x380, la ventana colapsada no
podría achicarse (el requisito clickeable del usuario se rompe).

```
hostW/hostH  = tamaños de la isla en el estado (colapsado 312x32)     ✓
x(t)         = (hostW - w(t)) / 2   // centrado; si hostW == w → x = 0
yTop         = 0                    // PINZADO al borde superior del hosting
```

Cuando `isExpanded` cambia, el hosting (y la ventana) adoptan el tamaño del
nuevo estado y la isla se estira desde el notch hacia abajo. Verificado en
`hostingLocalFrame(hostW:hostH:t:)` (test_island_main.swift, test 7).

## Criterio de aceptación — estado COLAPSADO en reposo (requisito 6)

El usuario reportó: "rompiste el estado colapsado descansando, es demasiado
ancho". **CAUSA RAÍZ**: el hosting/`Color.clear` quedó fijo en 560x380 → la
ventana colapsada no puede reducirse a 312x32.

**REQUISITO**: en reposo colapsado, la ventana/hosting DEBE medir 312x32
(exactamente lo que cubre la isla compacta), de modo que:
- La isla compacta queda centrada y NO se ve un ancho muerto alrededor.
- El área a los lados del notch sigue clickeable.
- `hostW == islandW` en ambos estados → la isla LLENA el hosting (x=0).

## SOLUCIÓN FINAL (requisito 6, aprobada) — click-through dinámico

**Decisión:** revertir el hosting por-estado (rompía la transición). En su
lugar, NSPanel **fija en 560x380** (mantiene el ancla del notch) con
`ignoresMouseEvents` **dinámico**:

- Cursor FUERA de la isla → `ignoresMouseEvents = true` → clicks pasan al
  desktop (menu bar / apps de abajo). La ventana 560 no bloquea nada.
- Cursor SOBRE la isla → `ignoresMouseEvents = false` → hover/clicks en las
  pills (expandir, seleccionar opción, Descartar) funcionan.

El hover NO depende de `onHover` de SwiftUI (la ventana click-through no lo
recibe). En su lugar un **global mouse monitor**
(`NSEvent.addGlobalMonitorForEvents(.mouseMoved)`) actualiza `model.isHovering`
según si el cursor cae dentro del rect de la isla (función pura `isInsideIsland`,
testeable). El debounce existente colapsa con ese `isHovering` corregido.

### Geometría del hit-test (función pura `isInsideIsland`)

Dado el rect de la isla en coordenadas de pantalla y la posición del cursor,
devuelve si el cursor está encima (misma escala — AppKit bottom-left):

```
isInsideIsland(cursor: (x, y), islandRect: (minX, minY, maxX, maxY))
    = minX <= cursor.x <= maxX  &&  minY <= cursor.y <= maxY
```

En reposo colapsado: `islandRect` = compact centrado en el notch
`(600, 950, 912, 982)`. El cursor fuera de ese mini-rect → click-through total
(no bloquea el resto de la pantalla).

## Criterio de aceptación — título visible en EXPANDIDO (requisito 7)

El usuario reportó: "cuando está expandido debería bajar bajo el notch para que
se pueda ver el título".

**CAUSA RAÍZ**: la isla expandida se ancla al tope físico de la pantalla
(top = screenH = 982), pero el notch físico ocupa los 32px superiores
(`safeAreaInsets.top = 32`, zona 950..982). El header ("pi blocked • …") queda
DETRÁS del notch → invisible.

**REQUISITO**: en estado expandido, la ventana/isla se desplaza HACIA ABAJO un
offset = notchHeight, de modo que el header quede bajo el notch (zona visible).
En colapsado, la posición actual NO cambia (las pills siguen tocando el notch,
que es el diseño aprobado).

```
screenY (AppKit, bottom-left) = screenH - offsetTop - h
offsetTop = isExpanded ? notchHeight (32) : 0
→ colapsado: top = 982 (como hoy)   expandido: top = 950 (bajo el notch)
```

El header (padding top 16 sobre el top de la isla) queda en ~934..950 →
visible bajo el notch. La NSPanel se reposiciona con `setFrame animate:false`
(SIN tocar el hosting/overlay → la transición no se rompe). El mouse monitor
usa la MISMA geometría para el hit-test expandido.

Verificado en `screenFrame(isExpanded:)` (test_island_main.swift, test 9).

## Criterio de aceptación — sin parpadeo en el borde expandido/colapsado (req 8)

El usuario reportó: "a veces cuando el cursor está en el borde entre el
expandido y el colapsado la animación parpadea".

**CAUSA RAÍZ**: el hover usa dos rects distintos según el estado:
- Colapsado: rect de la pill en la franja superior (x 600..912, y 950..982).
- Expandido: rect de la isla que NO cubre la franja superior (maxY = 950,
  porque la isla bajó bajo el notch). La franja 950..982 queda "de nadie".

Cursor en esa franja (p.ej. y=966, x=756): colapsado → DENTRO → expande;
expandido → FUERA → colapsa → **loop = parpadeo**.

**REQUISITO**: el rect de hover EXPANDIDO debe incluir la franja del notch
(maxY = screenH), de modo que el cursor que estaba en la pill NO quede fuera al
expandir → transición estable sin parpadeo. La pill (rect compact) es un
subconjunto del rect expandido; hover = `inCompact || (isExpanded && inExpanded)`.

```
expandedIslandRect.maxY = screenH   // cubre la franja del notch (anti-parpadeo)
```

Verificado en `expandedIslandRect` (test_island_main.swift, test 10).

## Criterio de aceptación — sin borde raro con menu bar transparente (req 9)

El usuario reportó: "se ve bien sobre otras apps fullscreen pero cuando el menu
bar es transparente el borde se ve raro cuando está ampliado".

**CAUSA RAÍZ**: el requisito 7 bajó la VENTANA/isla entera 32px bajo el notch.
Con menu bar SÓLIDA la franja del notch se funde; con menu bar TRANSPARENTE la
franja (950..982) muestra el wallpaper de atrás y el **borde superior recto de
la isla negra queda recortado contra él** → se ve raro.

**REQUISITO**: la ISLA visual debe quedar PEGADA al tope físico (cubre la
franja del notch — sin recorte con menu bar transparente), pero el CONTENIDO
(header/título) debe desplazarse hacia abajo un `notchHeight` para seguir
visible bajo el notch (se mantiene el objetivo del req 7).

```
isla visual:     top = screenH (pegada, como colapsado)   — SIN borde raro
contenido:       header empieza en top - 16 - notchHeight → bajo el notch
```

Esto separa el "contenedor que ancla la transición" (que vuelve a pegarse al
tope) del "contenido desplazado" (que baja para ser visible). El requisito 7
(título visible) se preserva SIN el artefacto del borde.

Verificado en `expandedVisibleTop` / `expandedHeaderTop` (test 11) y en que
`screenFrame(isExpanded:)` vuelve a `top = screenH`.

## Ajuste final (req 9b, confirma el usuario)

El usuario: "como ahora tiene padding arriba ya podemos quitar el margin".

**Significado:** con la isla pegada al tope (req 9), el header quedó con
`padding .top = 16 + notchHeight (48)` → deja una franja negra muerta de 16px
entre el notch y el título. Basta bajar el título SOLO `notchHeight (32)` para
que quede pegado bajo el notch, sin margen extra.

```
expandedContentInsetTop = 0   (se quita el 16 de margen sobrante)
header top = screenH - notchHeight          // 982 - 32 = 950 → = notch bottom
```

El título toca justo el borde inferior del notch (950), visible y sin franja
muerta. `expandedHeaderTop(screenH:) = screenH - notchHeight`.

## Corrección req 9c — la VENTANA expandida NO baja (confirmado por el usuario)

El usuario: "expandido no debe estar bajo el notch sino al mismo nivel. El
título será legible gracias al padding que tiene".

**CAUSA RAÍZ del bug**: `place(isExpanded:)` quedó con un residuo del req 7 —
aunque `screenFrame(isExpanded:)` ya pegaba la isla al tope (top=screenH), el
método `place` aplicaba OTRA VEZ `expandedOffset = notchHeight` en su propio
cálculo (`y = topBase - expandedOffset - h`), bajando la ventana 32px bajo el
notch. Configuración duplicada: la geometría decía "pegada" pero el runtime la
bajaba.

**REQUISITO (estado final)**: la VENTANA/isla expandida SIEMPRE pega al tope
físico (top = screenH = al MISMO nivel del notch). El título baja por su propio
padding (notchHeight dentro de la vista expanded). NO existe offset en la
posición de la ventana:

```
place(isExpanded) → y = screenH - 380   (top=screenH siempre, ambos estados)
titleTop = screenH - notchHeight         (baja por el padding del contenido)
```

`screenFrame(isExpanded:)` ya implementa esto (top=screenH en ambos) → **place
debe usar exactamente screenFrame, sin recalcular con offset propio.**
