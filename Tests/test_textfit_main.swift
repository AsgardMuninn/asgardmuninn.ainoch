// test_textfit_main.swift — TDD del presupuesto de texto de opciones (TEXTFIT_SPEC).
// Exit != 0 = falla.

import Foundation
import CoreGraphics

func assert(_ c: Bool, _ m: String) {
    if !c {
        FileHandle.standardError.write("FAIL: \(m)\n".data(using: .utf8)!)
        exit(1)
    }
}

let H = IslandTransition.expandedH

// TEST 1: el caso que hoy desborda (3 opciones, pregunta de 3 líneas) entra
// con 1 línea de descripción y filas normales.
let p1 = OptionTextFit.plan(optionCount: 3, questionLines: 3)
assert(p1.descLineLimit == 1, "3 opciones + 3 líneas de pregunta → 1 línea de desc (\(p1.descLineLimit))")
assert(p1.rowVPad == 10, "con 3 opciones las filas siguen normales (10), no compactas")

// TEST 2: con espacio de sobra no se recorta de más (máximo actual = 3).
let p2 = OptionTextFit.plan(optionCount: 2, questionLines: 1)
assert(p2.descLineLimit == 3, "2 opciones + 1 línea → 3 líneas de desc (tope actual)")

// TEST 3: muchas opciones → filas compactas y sin descripción, pero los
// títulos siempre visibles.
let p3 = OptionTextFit.plan(optionCount: 5, questionLines: 3)
assert(p3.rowVPad == 6, "5 opciones → filas compactas (6)")
assert(p3.descLineLimit == 0, "5 opciones → sin descripción (0), título siempre visible")

// TEST 4 (invariante): NUNCA se excede expandedH para 1...6 opciones y
// 1...3 líneas de pregunta.
for n in 1...6 {
    for q in 1...3 {
        let plan = OptionTextFit.plan(optionCount: n, questionLines: q)
        let total = OptionTextFit.totalHeight(optionCount: n, questionLines: q, plan: plan)
        assert(total <= H + 0.001,
               "overflow: n=\(n) q=\(q) plan=\(plan) total=\(total) > \(H)")
    }
}

// TEST 5: monotonía — más opciones nunca permiten más líneas de descripción.
var prev = Int.max
for n in 1...6 {
    let d = OptionTextFit.plan(optionCount: n, questionLines: 2).descLineLimit
    assert(d <= prev, "descLineLimit debe ser no creciente con n (\(n): \(d) > \(prev))")
    prev = d
}

// TEST 6: estimación de líneas de pregunta (46 chars/línea, tope 3).
assert(OptionTextFit.questionLines("¿Seguimos?") == 1, "pregunta corta → 1 línea")
assert(OptionTextFit.questionLines(String(repeating: "a", count: 60)) == 2, "60 chars → 2 líneas")
assert(OptionTextFit.questionLines(String(repeating: "a", count: 500)) == 3, "pregunta larga → tope 3")
assert(OptionTextFit.questionLines("") == 1, "pregunta vacía → 1 línea (nunca 0)")
// Los saltos de línea explícitos cuentan como líneas reales.
assert(OptionTextFit.questionLines("uno\ndos\ntres") == 3, "3 líneas explícitas → 3")
assert(OptionTextFit.questionLines("uno\ndos\ntres\ncuatro") == 3, "4 explícitas → tope 3")

print("PASS: text-fit 6/6")
