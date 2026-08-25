// main.swift — ciclo de vida de la app. Top-level code aquí (permite a
// views.swift ser una biblioteca de tipos — arregla el bug de build).

import AppKit

// NSApplication necesita correr en el main thread. En scripts de AppKit con
// main.swift, ya estamos en el main thread al iniciar.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = NotchAppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
