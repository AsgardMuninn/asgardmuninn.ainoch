// KeyboardSpec.swift — lógica PURA de navegación por teclado (KEYBOARD_SPEC).
// Sin AppKit: resuelve qué acción produce cada tecla. Testeable con swiftc.

import Foundation

enum KeyAction: Equatable {
    case selectOption(Int)
    case highlightUp
    case highlightDown
    case highlightEnter
    case prevQuestion
    case nextQuestion
    case collapse
    case none
}

enum KeyboardSpec {
    static func isNumberKey(_ s: String) -> Int? {
        guard let v = Int(s), v >= 1, v <= 9 else { return nil }
        return v
    }

    /// Resuelve la tecla a una acción (KEYBOARD_SPEC tabla).
    /// - `char`: carácter de la tecla ("1", flechas...).
    /// - `keyCode`: código nativo (53 = Escape, 123-126 = flechas).
    static func resolveKey(char: String, keyCode: UInt16,
                           isExpanded: Bool, isTextInputActive: Bool) -> KeyAction {
        guard isExpanded else { return .none }          // colapsado: no roba

        // ESC SIEMPRE se resuelve (v6b): incluso en modo texto → .collapse.
        // El branch .collapse decide: en modo texto cierra el input (back);
        // en el inicio hace dismiss. (Bug v6b: el guard siguiente impedía que
        // ESC llegara al branch → "tampoco funciona el escape").
        if keyCode == 53 { return .collapse }

        guard !isTextInputActive else { return .none }  // escribiendo: el resto
                                                        // de teclas pasan al campo

        // Flechas horizontales: navegar stack (← 123 / → 124)
        switch keyCode {
        case 123: return .prevQuestion
        case 124: return .nextQuestion
        default: break
        }
        // Flechas verticales: highlight de opciones (↑ 126 / ↓ 125)
        switch keyCode {
        case 125: return .highlightDown
        case 126: return .highlightUp
        default: break
        }
        // Fallback por carácter (si el keyCode no llegó)
        switch char {
        case "←", "left":   return .prevQuestion
        case "→", "right":  return .nextQuestion
        case "↑", "up":     return .highlightUp
        case "↓", "down":   return .highlightDown
        default: break
        }

        // Enter/Return (keyCode 36) con highlight activo → confirmar selección
        if keyCode == 36 { return .highlightEnter }

        // Números 1-9 → seleccionar opción
        if let n = isNumberKey(char) { return .selectOption(n) }

        return .none
    }

    /// KEYBOARD_SPEC v7 (limpieza Cmd+A): decide si un KeyDown es el atajo
    /// "select all" sobre el input de texto libre. Solo aplica en modo texto
    /// (el resto de teclas deben pasar al TextField). Se compara el CHAR lógico
    /// (charactersIgnoringModifiers) y no el keyCode físico: el keyCode 0 solo
    /// coincide con 'A' en teclados ANSI y se rompe en otros layouts (Dvorak,
    /// ISO con caracteres extra). La mayúscula (Cmd+Shift+A) también es
    /// select-all — ambas comparten la semántica del atajo.
    static func isCmdASelectAll(char: String, commandDown: Bool, isTextInputActive: Bool) -> Bool {
        guard isTextInputActive, commandDown else { return false }
        return char.lowercased() == "a"
    }

    // --- Highlight vertical (KEYBOARD_SPEC) ---

    /// Mueve el highlight hacia ARRIBA (clamp a 1). current 1..N.
    static func moveHighlightUp(_ current: Int?) -> Int {
        guard let c = current else { return 1 }          // nil → opción 1
        return c > 1 ? c - 1 : 1
    }

    /// Mueve el highlight hacia ABAJO (clamp a count). current 1..N.
    static func moveHighlightDown(_ current: Int?, count: Int) -> Int {
        guard count > 0 else { return 1 }
        guard let c = current else { return 1 }          // nil → opción 1
        return c < count ? c + 1 : count
    }
}
