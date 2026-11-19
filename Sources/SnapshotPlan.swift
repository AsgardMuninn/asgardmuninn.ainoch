// SnapshotPlan.swift — SNAPSHOT_SPEC v1: lógica PURA del tool de evidencia
// (Tools/snapshot.swift). Sin AppKit: parsea la CLI y deriva los nombres de
// archivo esperados, así el contrato del tool se testea sin abrir ventanas.

import Foundation

enum SnapshotPlanError: Error, Equatable {
    case missingInput       // falta --events <json>
    case missingOutput      // falta --out <dir>
    case badScale           // --scale fuera de 1...4
    case badHighlight       // --highlight < 1
    case badNumber(String)  // valor no numérico
    case unknownFlag(String)
}

/// Qué renderizar y dónde. `outputs` es determinista (siempre el mismo orden),
/// para que la verificación pueda comparar nombres/hashes entre corridas.
struct SnapshotOptions: Equatable {
    let input: String
    let outDir: String
    let scale: Int
    let expanded: Bool
    let highlight: Int?

    var outputs: [String] {
        var names = ["compact@\(scale)x.png"]
        guard expanded else { return names }
        names.append("expanded@\(scale)x.png")
        if let h = highlight { names.append("expanded-highlight\(h)@\(scale)x.png") }
        return names
    }
}

enum SnapshotPlan {
    static let minScale = 1
    static let maxScale = 4
    static let usage = """
    uso: ainoch-snapshot --events <event.json> --out <dir> [--scale 1..4] \
    [--no-expanded] [--highlight N]
    """

    static func parse(_ args: [String]) -> Result<SnapshotOptions, SnapshotPlanError> {
        var input: String?
        var outDir: String?
        var scale = 2                 // @2x por defecto (retina, igual que la app)
        var expanded = true
        var highlight: Int?

        var i = 0
        while i < args.count {
            let a = args[i]
            switch a {
            case "--events":
                guard i + 1 < args.count else { return .failure(.missingInput) }
                input = args[i + 1]; i += 2
            case "--out":
                guard i + 1 < args.count else { return .failure(.missingOutput) }
                outDir = args[i + 1]; i += 2
            case "--scale":
                guard i + 1 < args.count, let v = Int(args[i + 1]) else {
                    return .failure(.badNumber("--scale"))
                }
                guard (minScale...maxScale).contains(v) else { return .failure(.badScale) }
                scale = v; i += 2
            case "--highlight":
                guard i + 1 < args.count, let v = Int(args[i + 1]) else {
                    return .failure(.badNumber("--highlight"))
                }
                guard v >= 1 else { return .failure(.badHighlight) }
                highlight = v; i += 2
            case "--no-expanded":
                expanded = false; i += 1
            case "--help", "-h":
                return .failure(.unknownFlag(a))
            default:
                return .failure(.unknownFlag(a))
            }
        }

        guard let inp = input, !inp.isEmpty else { return .failure(.missingInput) }
        guard let out = outDir, !out.isEmpty else { return .failure(.missingOutput) }
        return .success(SnapshotOptions(input: inp, outDir: out, scale: scale,
                                        expanded: expanded, highlight: highlight))
    }
}
