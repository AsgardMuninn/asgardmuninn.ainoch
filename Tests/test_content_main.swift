// main.swift (test CONtentState) — TDD del modo texto libre (CONTENT_SPEC).
// Exit != 0 = falla.

import Foundation

func assert(_ c: Bool, _ m: String) {
    if !c {
        FileHandle.standardError.write("FAIL: \(m)\n".data(using: .utf8)!)
        exit(1)
    }
}

// TEST 1: detecta la opción "Type something." del harness pi.
assert(ContentState.isFreeTextOption("4. Type something."),
       "debe detectar 'Type something.' como texto libre")
assert(ContentState.isFreeTextOption("Type something"),
       "sin punto también")
// Las opciones normales NO son texto libre.
assert(!ContentState.isFreeTextOption("1. GET + PUT context (Recommended)"),
       "opción normal no es texto libre")
assert(!ContentState.isFreeTextOption("3. No persisted context"),
       "opción normal no es texto libre")

// TEST 2: tap sobre free text → entra modo texto (no envía número).
let r1 = ContentState.onOptionTap(optionIndex: 4, optionTitle: "4. Type something.",
                                  textInputActive: false)
assert(r1 == .enterTextMode, "tap en Type something → enterTextMode")
// tap sobre opción normal → envía el índice (comportamiento actual).
let r2 = ContentState.onOptionTap(optionIndex: 1, optionTitle: "1. GET + PUT context",
                                  textInputActive: false)
assert(r2 == .selectOption(1), "tap en opción normal → selectOption(1)")

// TEST 3: submit — texto no vacío se envía; vacío se ignora.
let s1 = ContentState.onTextSubmit("  hola mundo  ")
if case .send(let txt) = s1 { assert(txt == "hola mundo", "trim del texto") }
else { assert(false, "texto no vacío → send") }
let s2 = ContentState.onTextSubmit("   ")
assert(s2 == .ignore, "texto vacío → ignore")
let s3 = ContentState.onTextSubmit("")
assert(s3 == .ignore, "vacio → ignore")

// TEST 4: (REQ 2a) click fuera del campo → sale del modo texto; si no está
// activo, no hace nada.
assert(ContentState.onTapOutside(textInputActive: true),
       "click fuera con modo texto activo → cerrar el input")
assert(!ContentState.onTapOutside(textInputActive: false),
       "click fuera sin modo texto → no hace nada")

// TEST 5: (REQ 2b) la ventana solo es key durante el modo texto.
assert(ContentState.windowCanBecomeKey(textInputActive: true),
       "modo texto activo → ventana puede ser key (para escribir)")
assert(!ContentState.windowCanBecomeKey(textInputActive: false),
       "sin modo texto → ventana NO puede ser key (no roba foco)")

// TEST 6: (KEYBOARD_SPEC v2) ESC contextual — modo texto → back; inicio → dismiss.
assert(ContentState.onEscape(textInputActive: true) == .closeTextMode,
       "ESC en modo texto → closeTextMode (volver atrás)")
assert(ContentState.onEscape(textInputActive: false) == .dismissCurrent,
       "ESC en inicio → dismissCurrent")

print("PASS: content-state 6/6")
