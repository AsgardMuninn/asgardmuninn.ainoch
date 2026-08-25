// IslandGeometry.swift — función PURA de interpolación de la transición.
// Cumple la TRANSITION_SPEC.md: centro fijo en el notch, top fijo,
// crecimiento top→bottom. Sin AppKit, testeable.

import CoreGraphics

enum IslandTransition {
    // Constantes de la spec (1512x982, notch = 32px)
    static let screenW: CGFloat = 1512
    static let screenH: CGFloat = 982
    static let notchCenterX: CGFloat = screenW / 2     // 756
    static let compactW: CGFloat = 312
    static let compactH: CGFloat = 32
    static let expandedW: CGFloat = 560
    static let expandedH: CGFloat = 380

    /// Frame de la isla para un progreso t ∈ [0,1] (0=compact, 1=expanded).
    /// Invariantes SPEC:
    ///  - centerX = notchCenterX siempre (no baila de lado a lado)
    ///  - top (y+h) = screenH siempre (no aparece desde abajo; crece hacia abajo)
    static func islandFrame(t: CGFloat) -> (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        let tt = min(max(t, 0), 1)
        let w = compactW + (expandedW - compactW) * tt
        let h = compactH + (expandedH - compactH) * tt
        let x = notchCenterX - w / 2
        let y = screenH - h          // top = y + h = screenH (constante)
        return (x, y, w, h)
    }

    /// El contenido de la isla. Invariante 1: el borde superior NO baja nunca.
    static func topY(y: CGFloat, h: CGFloat) -> CGFloat { y + h }

    /// Invariante 3 (top→bottom): el top nunca baja más que un epsilon.
    static func isTopStable(_ f: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat)) -> Bool {
        abs(topY(y: f.y, h: f.h) - screenH) < 0.001
    }

    /// Frame HOST-LOCAL (coordenadas del hosting view, origen top-LEFT):
    /// el top queda PINZADO al borde superior del hosting (yTop = 0) para que
    /// la animación de crecimiento arranque desde el notch, no desde el centro.
    static func hostingLocalFrame(hostW: CGFloat, hostH: CGFloat, t: CGFloat)
        -> (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        let tt = min(max(t, 0), 1)
        let w = compactW + (expandedW - compactW) * tt
        let h = compactH + (expandedH - compactH) * tt
        let x = (hostW - w) / 2     // centrado horizontal en el hosting
        return (x, 0, w, h)         // y=0 → top pegado al borde superior
    }

    /// Hit-test puro (SOLUCIÓN FINAL req 6): devuelve si el cursor está dentro
    /// del rect de la isla (coords de pantalla, AppKit bottom-left).
    static func isInsideIsland(cursor: (x: CGFloat, y: CGFloat),
                               islandRect: (minX: CGFloat, minY: CGFloat,
                                            maxX: CGFloat, maxY: CGFloat)) -> Bool {
        return islandRect.minX <= cursor.x && cursor.x <= islandRect.maxX
            && islandRect.minY <= cursor.y && cursor.y <= islandRect.maxY
    }

    /// Rect de la isla COMPACTA en coords de pantalla (reposo colapsado): el
    /// mini-rect centrado bajo el notch. Usado por el mouse monitor.
    static func compactIslandRect(screenW: CGFloat, screenH: CGFloat)
        -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        let x = (screenW - compactW) / 2        // 600 en 1512
        let top = screenH                        // 982
        return (x, top - compactH, x + compactW, top)
    }

    /// Altura del notch físico (zona superior que tapa la pantalla).
    static let notchHeight: CGFloat = 32   // safeAreaInsets.top real

    /// Posición de la VENTANA en coords de pantalla (AppKit bottom-left).
    /// REQ 9: la isla visual queda SIEMPRE pegada al tope físico (top = screenH)
    /// → cubre la franja del notch, sin recorte con menu bar transparente.
    /// El título visible bajo el notch (req 7) lo logra el inset del contenido
    /// (expandedHeaderTop/expandedContentInsetTop), no bajando la ventana.
    static func screenFrame(isExpanded: Bool, screenW: CGFloat, screenH: CGFloat)
        -> (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        let w: CGFloat = isExpanded ? expandedW : compactW
        let h: CGFloat = isExpanded ? expandedH : compactH
        let x = (screenW - w) / 2
        let y = screenH - h                  // top = screenH siempre
        return (x, y, w, h)
    }

    /// Rect del hit-test EXPANDIDO (coincide con screenFrame expandido salvo
    /// el borde superior): maxY = screenH para incluir la franja del notch
    /// (req 8 anti-parpadeo — el cursor sobre la pill no queda fuera al
    /// expandir). La pill (compact) es subconjunto de este rect.
    static func expandedIslandRect(screenW: CGFloat, screenH: CGFloat)
        -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
        let f = screenFrame(isExpanded: true, screenW: screenW, screenH: screenH)
        return (f.x, f.y, f.x + f.w, screenH)   // maxY = screenH (cubre notch)
    }

    /// REQ 9b: la ISLA visual queda PEGADA al tope físico (top = screenH).
    /// El título baja SOLO notchHeight para quedar pegado bajo el notch (sin
    /// franja muerta de margen). El usuario: "como ahora tiene padding arriba
    /// ya podemos quitar el margin".
    static let expandedContentInsetTop: CGFloat = 0    // se quitó el 16 sobrante

    /// Top del header (contenido): = screenH - notchHeight → toca el borde
    /// inferior del notch (950 en 982), visible y sin margen extra.
    static func expandedHeaderTop(screenH: CGFloat) -> CGFloat {
        return screenH - notchHeight
    }
}
