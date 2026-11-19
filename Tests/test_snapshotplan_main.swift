// test_snapshotplan_main.swift — SNAPSHOT_SPEC v1 (lógica pura del tool de evidencia).
// Corre con: swiftc Sources/SnapshotPlan.swift Tests/test_snapshotplan_main.swift -o /tmp/t && /tmp/t

import Foundation

var failures = 0
var checks = 0

func check(_ name: String, _ cond: Bool, _ detail: String = "") {
    checks += 1
    if cond {
        print("PASS \(name)")
    } else {
        failures += 1
        print("FAIL \(name) \(detail)")
    }
}

// 1. Defaults: scale 2 (@2x, retina), ampliado, sin highlight.
do {
    let r = SnapshotPlan.parse(["--events", "e.json", "--out", "outdir"])
    switch r {
    case .success(let o):
        check("default.events", o.input == "e.json", "\(o.input)")
        check("default.out", o.outDir == "outdir", "\(o.outDir)")
        check("default.scale", o.scale == 2, "\(o.scale)")
        check("default.expanded", o.expanded == true)
        check("default.highlight", o.highlight == nil)
        check("default.outputs", o.outputs == ["compact@2x.png", "expanded@2x.png"],
              "\(o.outputs)")
    case .failure(let e):
        check("default.parse", false, "\(e)")
    }
}

// 2. Falta --events → error tipado (no crash, no default silencioso).
do {
    switch SnapshotPlan.parse(["--out", "outdir"]) {
    case .success: check("missing.events", false, "se aceptó sin --events")
    case .failure(let e): check("missing.events", e == .missingInput, "\(e)")
    }
}

// 3. Falta --out → error tipado.
do {
    switch SnapshotPlan.parse(["--events", "e.json"]) {
    case .success: check("missing.out", false, "se aceptó sin --out")
    case .failure(let e): check("missing.out", e == .missingOutput, "\(e)")
    }
}

// 4. --scale fuera de rango 1...4 → error.
do {
    let lo = SnapshotPlan.parse(["--events", "e", "--out", "o", "--scale", "0"])
    let hi = SnapshotPlan.parse(["--events", "e", "--out", "o", "--scale", "9"])
    let ok = SnapshotPlan.parse(["--events", "e", "--out", "o", "--scale", "3"])
    check("scale.lo", lo == .failure(.badScale))
    check("scale.hi", hi == .failure(.badScale))
    if case .success(let o) = ok {
        check("scale.ok", o.scale == 3)
        check("scale.names", o.outputs.first == "compact@3x.png", "\(o.outputs)")
    } else {
        check("scale.ok", false)
    }
}

// 5. --no-expanded renderiza solo el estado compacto.
do {
    switch SnapshotPlan.parse(["--events", "e", "--out", "o", "--no-expanded"]) {
    case .success(let o):
        check("noexpanded.flag", o.expanded == false)
        check("noexpanded.names", o.outputs == ["compact@2x.png"], "\(o.outputs)")
    case .failure(let e): check("noexpanded.parse", false, "\(e)")
    }
}

// 6. --highlight >= 1 añade el estado resaltado; <= 0 es error.
do {
    switch SnapshotPlan.parse(["--events", "e", "--out", "o", "--highlight", "3"]) {
    case .success(let o):
        check("highlight.ok", o.highlight == 3)
        check("highlight.names", o.outputs == ["compact@2x.png", "expanded@2x.png",
                                               "expanded-highlight3@2x.png"],
              "\(o.outputs)")
    case .failure(let e): check("highlight.parse", false, "\(e)")
    }
    check("highlight.zero", SnapshotPlan.parse(["--events", "e", "--out", "o",
                                                "--highlight", "0"]) == .failure(.badHighlight))
}

// 7. Flag desconocido → error (nunca ignorar en silencio).
do {
    check("unknown.flag", SnapshotPlan.parse(["--events", "e", "--out", "o", "--bogus"]) == .failure(.unknownFlag("--bogus")))
}

print("\n\(checks - failures)/\(checks) PASS")
if failures > 0 { exit(1) }
