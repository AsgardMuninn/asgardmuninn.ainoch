// test_island.swift — TDD de la transición según TRANSITION_SPEC.md.
// Verifica los 3 invariantes en múltiples puntos del progreso.
// Exit != 0 = falla (RED).

import Foundation
import CoreGraphics

func assert(_ c: Bool, _ m: String) {
    if !c {
        FileHandle.standardError.write("FAIL: \(m)\n".data(using: .utf8)!)
        exit(1)
    }
}

let T = IslandTransition.self

// TEST 1: en los extremos, el frame es el compact y el expanded exactos.
let c0 = T.islandFrame(t: 0)
assert(c0.w == 312 && c0.h == 32, "t=0 → compact 312x32")
assert(c0.x + c0.w / 2 == T.notchCenterX, "t=0 → centro en el notch")
let c1 = T.islandFrame(t: 1)
assert(c1.w == 560 && c1.h == 380, "t=1 → expanded 560x380")
assert(c1.x + c1.w / 2 == T.notchCenterX, "t=1 → centro en el notch")

// TEST 2: INVARIANTE 1 — el TOP está fijo en screenH durante TODA la transición.
for i in 0...20 {
    let t = CGFloat(i) / 20.0
    let f = T.islandFrame(t: t)
    assert(T.isTopStable(f), "t=\(t) → top debe ser screenH (no aparece desde abajo)")
}

// TEST 3: INVARIANTE 2 — el CENTRO horizontal NUNCA se mueve (no baila).
for i in 0...20 {
    let t = CGFloat(i) / 20.0
    let f = T.islandFrame(t: t)
    assert(abs((f.x + f.w / 2) - T.notchCenterX) < 0.001,
           "t=\(t) → centro horizontal en el notch")
}

// TEST 4: INVARIANTE 3 — top→bottom: la Y del borde superior es constante;
// solo la altura cambia. El bottom (y) baja al crecer h.
let f0 = T.islandFrame(t: 0)
let f1t = T.islandFrame(t: 1)
assert(f0.y > f1t.y, "compact bottom (y=950) > expanded bottom (y=602) → crece hacia abajo")
assert(T.topY(y: f0.y, h: f0.h) == T.topY(y: f1t.y, h: f1t.h),
       "los dos tops son iguales (screenH)")

// TEST 5: monotónica — w y h crecen con t (sin saltos).
var prevH: CGFloat = -1
var prevGrew = true
for i in 0...20 {
    let t = CGFloat(i) / 20.0
    let f = T.islandFrame(t: t)
    assert(f.h >= prevH, "h debe crecer/mantener (monotónica), t=\(t)")
    prevH = f.h
}

// TEST 6: (REQUISITO 5) la isla está HOST-LOCAL anclada al TOP del hosting
// (y=0 en todos los puntos) — la animación ARRANCA desde el notch, no del centro.
let hostW: CGFloat = 560, hostH: CGFloat = 380
for i in 0...20 {
    let t = CGFloat(i) / 20.0
    let f = T.hostingLocalFrame(hostW: hostW, hostH: hostH, t: t)
    assert(f.y == 0, "t=\(t) → isla pinzada al top del hosting (y=0)")
    assert(abs(f.x + f.w / 2 - hostW / 2) < 0.001,
           "t=\(t) → centrado horizontal en el hosting")
}
// El top de la isla host-local SIEMPRE coincide con el top del hosting.
let hfCompact = T.hostingLocalFrame(hostW: hostW, hostH: hostH, t: 0)
let hfExpanded = T.hostingLocalFrame(hostW: hostW, hostH: hostH, t: 1)
assert(hfCompact.y == hfExpanded.y, "el top host-local no cambia (notch fijo)")

// TEST 7: (REQUISITO 6) el hosting es del tamaño del ESTADO → la isla LLENA el
// hosting (x=0). En reposo colapsado la ventana mide 312x32, no 560 ancho.
let cHost = T.hostingLocalFrame(hostW: 312, hostH: 32, t: 0)
assert(cHost.w == 312 && cHost.h == 32, "colapsado: hosting 312x32")
assert(cHost.x == 0, "colapsado: isla llena el hosting (x=0, sin ancho muerto)")
assert(cHost.y == 0, "colapsado: y=0 (top anclado)")
// La ventana colapsada NO puede ser más ancha que 312: el área del notch a los
// lados queda clickeable (requisito del usuario).
assert(cHost.w < 560, "colapsado: NUNCA debe quedar en 560 de ancho (bug regresivo)")
let eHost = T.hostingLocalFrame(hostW: 560, hostH: 380, t: 1)
assert(eHost.w == 560 && eHost.x == 0, "expanded: hosting 560x380, isla llena")

// TEST 8: (SOLUCIÓN FINAL req 6) hit-test isInsideIsland — cursor dentro del
// rect compact → true; fuera → false. Es lo que decide click-through dinámico.
let cRect = T.compactIslandRect(screenW: 1512, screenH: 982)
assert(cRect.minX == 600 && cRect.maxY == 982, "rect compact: (600, 950, 912, 982)")
// Centro de la pill compacta → dentro
assert(T.isInsideIsland(cursor: (756, 966), islandRect: cRect),
       "cursor sobre la pill → dentro (hover expande)")
// Fuera: a la izquierda del notch (menu bar clickeable) → fuera
assert(!T.isInsideIsland(cursor: (400, 966), islandRect: cRect),
       "cursor a la izquierda del notch → fuera (click-through)")
// Fuera: abajo del rect compact (desktop) → fuera → no bloquea
assert(!T.isInsideIsland(cursor: (600, 500), islandRect: cRect),
       "cursor abajo → fuera (click-through, no bloquea desktop)")
// Borde exacto (top) → dentro (inclusivo)
assert(T.isInsideIsland(cursor: (700, 982), islandRect: cRect),
       "borde superior → dentro (inclusivo)")

// TEST 9+11: (REQ 7 + 9) título visible bajo el notch SIN borde raro.
// La isla queda PEGADA al tope (top=982, cubre la franja → sin recorte con
// menu bar transparente); el título se baja por el inset del CONTENIDO.
let fCompactR9 = T.screenFrame(isExpanded: false, screenW: 1512, screenH: 982)
let fExpandedR9 = T.screenFrame(isExpanded: true, screenW: 1512, screenH: 982)
// REQ 9: isla expandida PEGADA al tope físico (cubre franja del notch).
assert(fExpandedR9.y + fExpandedR9.h == 982,
       "REQ9: isla expandida top=982 (pegada, sin borde raro)")
assert(fCompactR9.y + fCompactR9.h == 982, "colapsado top=982 (sin cambio)")
// REQ 7: el TÍTULO (contenido) está bajo el notch vía inset del header.
// REQUESTO 9b: sin margen extra — header pegado JUSTO al borde del notch (950).
let hTop = T.expandedHeaderTop(screenH: 982)     // = 982 - 32 = 950
assert(hTop == T.notchHeight * 0 + 950, "header tocando el borde del notch: 950")
assert(hTop >= 982 - T.notchHeight, "header NO detrás del notch (visible)")
// El header queda DENTRO de la isla.
assert(fExpandedR9.h >= T.expandedContentInsetTop + T.notchHeight,
       "la isla es alta para el contenido desplazado")

// TEST 10: (REQUISITO 8) anti-parpadeo — un cursor sobre la pill (franja del
// notch) debe estar DENTRO del hit-test expandido también (maxY = screenH),
// para que al expandir no quede fuera → no parpadee entre estados.
let cR = T.compactIslandRect(screenW: 1512, screenH: 982)
let eR = T.expandedIslandRect(screenW: 1512, screenH: 982)
// Cursor en la franja del notch sobre la pill (y=966, dentro del compact):
assert(T.isInsideIsland(cursor: (756, 966), islandRect: cR),
       "borde: cursor sobre pill (colapsado → dentro)")
assert(T.isInsideIsland(cursor: (756, 966), islandRect: eR),
       "borde: cursor sobre pill (expandiendo → TAMBIÉN dentro) → no parpadea")
// La franja del notch queda cubierta por el rect expandido (maxY=982).
assert(eR.maxY == 982, "expandido maxY = screenH (cubre franja del notch)")
// Cursor a un lado (fuera de la pill y de la isla) → fuera en ambos → estable.
assert(!T.isInsideIsland(cursor: (400, 966), islandRect: cR), "lado: fuera")
assert(!T.isInsideIsland(cursor: (400, 966), islandRect: eR), "lado: fuera")

print("PASS: island-transition 11/11")
