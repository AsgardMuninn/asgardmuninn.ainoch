// main.swift (test KeyboardSpec) — TDD de navegación por teclado (KEYBOARD_SPEC).
// Exit != 0 = falla.

import Foundation

func assert(_ c: Bool, _ m: String) {
    if !c {
        FileHandle.standardError.write("FAIL: \(m)\n".data(using: .utf8)!)
        exit(1)
    }
}

// TEST 1: colapsado → ninguna tecla hace nada (no roba foco).
assert(KeyboardSpec.resolveKey(char: "1", keyCode: 18, isExpanded: false, isTextInputActive: false) == .none,
       "colapsado + número → none")
assert(KeyboardSpec.resolveKey(char: "", keyCode: 53, isExpanded: false, isTextInputActive: false) == .none,
       "colapsado + esc → none")

// TEST 2: modo texto activo → ninguna tecla interfiere (escribir).
assert(KeyboardSpec.resolveKey(char: "1", keyCode: 18, isExpanded: true, isTextInputActive: true) == .none,
       "modo texto + número → none (no interferir)")
assert(KeyboardSpec.resolveKey(char: "", keyCode: 124, isExpanded: true, isTextInputActive: true) == .none,
       "modo texto + flecha → none")

// TEST 3: números 1-9 → seleccionar opción.
assert(KeyboardSpec.resolveKey(char: "1", keyCode: 18, isExpanded: true, isTextInputActive: false) == .selectOption(1),
       "1 → selectOption(1)")
assert(KeyboardSpec.resolveKey(char: "4", keyCode: 21, isExpanded: true, isTextInputActive: false) == .selectOption(4),
       "4 → selectOption(4)")
assert(KeyboardSpec.resolveKey(char: "9", keyCode: 25, isExpanded: true, isTextInputActive: false) == .selectOption(9),
       "9 → selectOption(9)")
assert(KeyboardSpec.resolveKey(char: "0", keyCode: 29, isExpanded: true, isTextInputActive: false) == .none,
       "0 → none (fuera de rango)")

// TEST 4: flechas ← / → navegan el stack.
assert(KeyboardSpec.resolveKey(char: "left", keyCode: 123, isExpanded: true, isTextInputActive: false) == .prevQuestion,
       "left → prevQuestion")
assert(KeyboardSpec.resolveKey(char: "", keyCode: 124, isExpanded: true, isTextInputActive: false) == .nextQuestion,
       "keyCode 124 → nextQuestion")
assert(KeyboardSpec.resolveKey(char: "right", keyCode: 124, isExpanded: true, isTextInputActive: false) == .nextQuestion,
       "right → nextQuestion")

// TEST 5: ESC (keyCode 53) → collapse SIEMPRE (v6b). En modo texto el branch
// .collapse decide cerrar el input (closeTextMode); al inicio hace dismiss.
// Antes (bug v6b): ESC en modo texto caía en .none y nunca cerraba el input.
assert(KeyboardSpec.resolveKey(char: "", keyCode: 53, isExpanded: true, isTextInputActive: false) == .collapse,
       "esc → collapse")
assert(KeyboardSpec.resolveKey(char: "", keyCode: 53, isExpanded: true, isTextInputActive: true) == .collapse,
       "esc en modo texto → collapse (para cerrar el input)")

// TEST 6: otra tecla → none.
assert(KeyboardSpec.resolveKey(char: "a", keyCode: 0, isExpanded: true, isTextInputActive: false) == .none,
       "letra → none")

// TEST 7: flechas VERTICALES → highlight de opciones (patrón Raycast).
assert(KeyboardSpec.resolveKey(char: "", keyCode: 126, isExpanded: true, isTextInputActive: false) == .highlightUp,
       "keyCode 126 (↑) → highlightUp")
assert(KeyboardSpec.resolveKey(char: "", keyCode: 125, isExpanded: true, isTextInputActive: false) == .highlightDown,
       "keyCode 125 (↓) → highlightDown")
assert(KeyboardSpec.resolveKey(char: "↓", keyCode: 0, isExpanded: true, isTextInputActive: false) == .highlightDown,
       "char ↓ → highlightDown")
// Enter confirma la opción highlighteada
assert(KeyboardSpec.resolveKey(char: "\r", keyCode: 36, isExpanded: true, isTextInputActive: false) == .highlightEnter,
       "Enter → highlightEnter")

// TEST 8: movimiento del highlight — clamps y arranque.
assert(KeyboardSpec.moveHighlightDown(nil, count: 3) == 1, "nil ↓ → opción 1")
assert(KeyboardSpec.moveHighlightDown(1, count: 3) == 2, "1 ↓ → 2")
assert(KeyboardSpec.moveHighlightDown(3, count: 3) == 3, "3 ↓ → 3 (clamp)")
assert(KeyboardSpec.moveHighlightUp(nil) == 1, "nil ↑ → opción 1")
assert(KeyboardSpec.moveHighlightUp(2) == 1, "2 ↑ → 1")
assert(KeyboardSpec.moveHighlightUp(1) == 1, "1 ↑ → 1 (clamp)")

// TEST 9: (KEYBOARD_SPEC v7) atajo Cmd+A en modo texto → select all del field
// editor. La decisión es PURA e independiente del layout: usa el CHAR lógico
// (charactersIgnoringModifiers), NO el keyCode físico 0 (que solo es 'A' en
// teclados ANSI — se rompe en Dvorak/ISO con otras teclas en esa posición).
assert(KeyboardSpec.isCmdASelectAll(char: "a", commandDown: true, isTextInputActive: true),
       "Cmd+A en modo texto → select all")
assert(KeyboardSpec.isCmdASelectAll(char: "A", commandDown: true, isTextInputActive: true),
       "Cmd+Shift+A → select all igual (la A lógica no distingue mayúscula)")
assert(!KeyboardSpec.isCmdASelectAll(char: "a", commandDown: false, isTextInputActive: true),
       "sin Cmd → no select all (la tecla pasa al campo)")
assert(!KeyboardSpec.isCmdASelectAll(char: "a", commandDown: true, isTextInputActive: false),
       "sin modo texto → no select all (no roba teclas)")
assert(!KeyboardSpec.isCmdASelectAll(char: "é", commandDown: true, isTextInputActive: true),
       "Cmd+é (char distinto) → no select all")
assert(!KeyboardSpec.isCmdASelectAll(char: "", commandDown: true, isTextInputActive: true),
       "Cmd sola (char vacío) → no select all")
assert(!KeyboardSpec.isCmdASelectAll(char: "1", commandDown: true, isTextInputActive: true),
       "Cmd+1 → no select all")

print("PASS: keyboard-spec 9/9")
