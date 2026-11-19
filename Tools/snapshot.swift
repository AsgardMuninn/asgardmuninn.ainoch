// snapshot.swift — SNAPSHOT_SPEC v1: evidencia visual determinista del layout
// real de la isla, SIN abrir la app ni tocar producción.
//
// Renderiza NotchContentView con ImageRenderer (offscreen) desde un event.json
// y escribe PNGs: compact@Nx.png, expanded@Nx.png y (opcional) el estado con
// highlight de teclado. Es la fuente de evidencia para cada cambio de UI.
//
// Build en macOS:
//   swiftc -O Sources/views.swift Sources/IslandGeometry.swift \
//     Sources/ContentState.swift Sources/SoundSpec.swift Sources/StackLogic.swift \
//     Sources/TextFit.swift Sources/KeyboardSpec.swift Sources/SnapshotPlan.swift \
//     Tools/snapshot.swift -o ainoch-snapshot
// Uso:
//   ./ainoch-snapshot --events Tools/demo_event.json --out docs/pr-evidence/x

import AppKit
import SwiftUI

@main
struct SnapshotTool {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        switch SnapshotPlan.parse(args) {
        case .failure(let err):
            FileHandle.standardError.write(Data("snapshot: \(err)\n\(SnapshotPlan.usage)\n".utf8))
            exit(2)
        case .success(let opts):
            MainActor.assumeIsolated { run(opts) }
        }
    }

    @MainActor
    private static func run(_ opts: SnapshotOptions) {
        _ = NSApplication.shared          // ImageRenderer necesita el stack de AppKit
        guard let data = FileManager.default.contents(atPath: opts.input) else {
            FileHandle.standardError.write(Data("snapshot: no puedo leer \(opts.input)\n".utf8))
            exit(2)
        }
        let response: NotchResponse
        do {
            response = try JSONDecoder().decode(NotchResponse.self, from: data)
        } catch {
            FileHandle.standardError.write(Data("snapshot: JSON inválido: \(error)\n".utf8))
            exit(2)
        }
        guard let events = response.events, !events.isEmpty else {
            FileHandle.standardError.write(Data("snapshot: el JSON no trae eventos\n".utf8))
            exit(2)
        }

        try? FileManager.default.createDirectory(atPath: opts.outDir,
                                                 withIntermediateDirectories: true)

        // Estados a renderizar, en el mismo orden que opts.outputs.
        var plans: [(name: String, expanded: Bool, highlight: Int?)] = []
        var names = opts.outputs.makeIterator()
        if let n = names.next() { plans.append((n, false, nil)) }
        if opts.expanded, let n = names.next() { plans.append((n, true, nil)) }
        if opts.expanded, let n = names.next() { plans.append((n, true, opts.highlight)) }

        for plan in plans {
            let model = NotchModel()
            model.events = events
            model.isExpanded = plan.expanded
            model.keyboardSelection = plan.highlight
            guard let png = render(model, scale: opts.scale) else {
                FileHandle.standardError.write(Data("snapshot: render vacío (\(plan.name))\n".utf8))
                exit(3)
            }
            let path = (opts.outDir as NSString).appendingPathComponent(plan.name)
            do {
                try png.write(to: URL(fileURLWithPath: path))
            } catch {
                FileHandle.standardError.write(Data("snapshot: no pude escribir \(path): \(error)\n".utf8))
                exit(3)
            }
            print("ok \(path) \(png.count) bytes")
        }
    }

    /// Render offscreen 560x380 (el hosting real) sobre un fondo neutro de
    /// escritorio, para que el recorte del notch se vea tal cual en pantalla.
    @MainActor
    private static func render(_ model: NotchModel, scale: Int) -> Data? {
        let view = ZStack {
            LinearGradient(colors: [Color(white: 0.18), Color(white: 0.32)],
                           startPoint: .top, endPoint: .bottom)
            NotchContentView(model: model,
                             onSelect: { _ in },
                             onDismiss: {},
                             onFocusPane: {},
                             onSubmitText: { _ in })
        }
        .frame(width: 560, height: 380)

        let renderer = ImageRenderer(content: view)
        renderer.scale = CGFloat(scale)
        renderer.isOpaque = true
        guard let cg = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
