// main.swift (test StackLogic) — TDD del stack múltiple (STACK_SPEC).
// Exit != 0 = falla.

import Foundation

func assert(_ c: Bool, _ m: String) {
    if !c {
        FileHandle.standardError.write("FAIL: \(m)\n".data(using: .utf8)!)
        exit(1)
    }
}

// TEST 1: navegación — bordes y movimientos.
assert(StackLogic.stackTotal(3) == 3, "total 3")
assert(StackLogic.stackCanPrev(0) == false, "no puede ir atrás en 0")
assert(StackLogic.stackCanPrev(1) == true, "sí puede atrás en 1")
assert(StackLogic.stackCanNext(2, 3) == false, "no puede seguir en última")
assert(StackLogic.stackCanNext(1, 3) == true, "sí puede seguir en 1")
assert(StackLogic.stackPrev(0) == 0, "prev de 0 → 0 (clamp)")
assert(StackLogic.stackPrev(2) == 1, "prev de 2 → 1")
assert(StackLogic.stackNext(2, 3) == 2, "next de última → se queda (clamp)")
assert(StackLogic.stackNext(1, 3) == 2, "next de 1 → 2")

// TEST 2: label "n de N".
assert(StackLogic.stackLabel(0, 3) == "1 de 3", "label idx0/3")
assert(StackLogic.stackLabel(2, 3) == "3 de 3", "label idx2/3")
assert(StackLogic.stackLabel(0, 0) == "", "label vacío si no hay stack")
assert(StackLogic.stackLabel(99, 3) == "3 de 3", "label clampa alto")

// TEST 3: safeGuard tras remoción — clamp, nunca sale del rango.
assert(StackLogic.safeGuard(2, n: 3) == 2, "clamp normal 2/3")
assert(StackLogic.safeGuard(3, n: 3) == 2, "tras remover última → 2/3 (clamp)")
assert(StackLogic.safeGuard(2, n: 2) == 1, "tras remover → n-1")
assert(StackLogic.safeGuard(0, n: 1) == 0, "queda 1 item → idx 0")
assert(StackLogic.safeGuard(0, n: 0) == 0, "stack vacío → 0 (seguro)")

// TEST 4: detección de pregunta nueva — dedupe, + carga inicial silenciosa.
let prev = Set(["paneA", "paneB"])
let same = Set(["paneA", "paneB"])
let oneNew = Set(["paneA", "paneC"])
let twoNew = Set(["paneC", "paneD"])
assert(!StackLogic.hasNewQuestion(previous: prev, current: same, isInitialLoad: false),
       "mismo set → no es nueva")
assert(StackLogic.hasNewQuestion(previous: prev, current: oneNew, isInitialLoad: false),
       "un nuevo → nueva")
assert(StackLogic.hasNewQuestion(previous: prev, current: twoNew, isInitialLoad: false),
       "dos nuevos → nueva")
assert(!StackLogic.hasNewQuestion(previous: [], current: oneNew, isInitialLoad: true),
       "carga inicial → silencio (no suena al arrancar)")
assert(!StackLogic.hasNewQuestion(previous: prev, current: oneNew, isInitialLoad: true),
       "carga inicial → silencio incluso con nuevos")

// TEST 5: (STACK_SPEC v2) dismiss MUEVE al final, no borra.
// Con 3 ítems en el índice 0: tras reordenar [A,B,C]→[B,C,A], la siguiente
// pregunta (B) queda en el índice 0 → el índice se queda en 0.
assert(StackLogic.dismissIndexAfterMoveToEnd(0, count: 3) == 0,
       "dismiss 0/3 → índice 0 (siguiente ocupa el 0)")
// Dismiss en el índice 1: [A,B,C]→[A,C,B], la siguiente (C) queda en 1.
assert(StackLogic.dismissIndexAfterMoveToEnd(1, count: 3) == 1,
       "dismiss 1/3 → índice 1 (siguiente ocupa el 1)")
// Dismiss en la última (2/3): clamp a count-2 = 1 (muestra la penúltima).
assert(StackLogic.dismissIndexAfterMoveToEnd(2, count: 3) == 1,
       "dismiss 2/3 → índice 1 (clamp)")
// Un solo ítem → 0.
assert(StackLogic.dismissIndexAfterMoveToEnd(0, count: 1) == 0,
       "dismiss 0/1 → 0")
// moveToEnd reordena: [A,B,C], mover en 0 → [B,C,A].
var arr = ["A", "B", "C"]
StackLogic.moveToEnd(&arr, at: 0)
assert(arr == ["B", "C", "A"], "mover en 0 → [B,C,A] (\(arr))")
StackLogic.moveToEnd(&arr, at: 2)   // el último se queda (mover al final = no-op)
assert(arr == ["B", "C", "A"], "mover última → igual")

print("PASS: stack-logic 5/5")
