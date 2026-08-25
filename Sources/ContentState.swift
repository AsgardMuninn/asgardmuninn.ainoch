// ContentState.swift — lógica PURA del modo texto libre (CONTENT_SPEC).
// Sin AppKit, testeable. Define cuándo una opción es "Type something" y cómo
// transiciona el estado al hacer tap/submit/cancel.

import Foundation

enum ContentState {
    /// ¿Es la opción de texto libre? (la "4. Type something." del harness pi)
    static func isFreeTextOption(_ title: String) -> Bool {
        let t = title.lowercased()
        return t.contains("type") || t.contains("something")
    }

    /// Transición de tap sobre una opción (CONTENT_SPEC requisito 2).
    /// - free text → activa modo texto (no envía número).
    /// - opción normal → envía el índice (comportamiento actual).
    static func onOptionTap(optionIndex: Int, optionTitle: String,
                            textInputActive: Bool) -> TapOutcome {
        if isFreeTextOption(optionTitle) {
            return .enterTextMode
        }
        return .selectOption(optionIndex)
    }

    /// Submit del texto (requisito 4): texto no vacío → acción de enviar.
    static func onTextSubmit(_ text: String) -> SubmitOutcome {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .ignore }
        return .send(trimmed)
    }

    /// REQ 2a: click FUERA del campo de texto → salir del modo texto (cancel
    /// implícito, sin enviar). Si no está en modo texto, no hace nada.
    static func onTapOutside(textInputActive: Bool) -> Bool {
        return textInputActive            // true → cerrar el modo texto
    }

    /// REQ 2b: la ventana solo debe poder ser key cuando hay modo texto activo.
    /// (el NSPanel no roba el foco al desktop salvo que se esté escribiendo).
    static func windowCanBecomeKey(textInputActive: Bool) -> Bool {
        return textInputActive
    }

    /// KEYBOARD_SPEC v2: ESC contextual. Si hay un nivel interno (modo texto),
    /// volver atrás (cerrar el input); si estás en el inicio (raíz), dismiss
    /// la pregunta actual.
    static func onEscape(textInputActive: Bool) -> EscapeOutcome {
        return textInputActive ? .closeTextMode : .dismissCurrent
    }
}

enum EscapeOutcome: Equatable {
    case closeTextMode     // back: cerrar el input, volver a opciones
    case dismissCurrent    // inicio: dismiss de la pregunta actual
}

enum TapOutcome: Equatable {
    case enterTextMode          // activar el input, no enviar nada
    case selectOption(Int)      // enviar el número de la opción
}

enum SubmitOutcome: Equatable {
    case send(String)           // enviar texto al pane
    case ignore                 // vacío → no hacer nada
}
