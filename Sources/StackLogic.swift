// StackLogic.swift — lógica PURA del stack de múltiples preguntas (STACK_SPEC).
// Sin AppKit: navegación, label y detección de pregunta nueva — testeable.

import Foundation

enum StackLogic {
    static func stackTotal(_ n: Int) -> Int { max(0, n) }

    static func stackCanPrev(_ i: Int) -> Bool { i > 0 }
    static func stackCanNext(_ i: Int, _ n: Int) -> Bool { i < n - 1 }

    static func stackPrev(_ i: Int) -> Int { max(0, i - 1) }
    static func stackNext(_ i: Int, _ n: Int) -> Int { min(max(0, n - 1), i + 1) }

    static func stackLabel(_ i: Int, _ n: Int) -> String {
        guard n > 0 else { return "" }
        let idx = clamp(i, 0, n - 1)
        return "\(idx + 1) de \(n)"
    }

    /// Clamp del índice tras remover el ítem en `i`: no sale del rango.
    static func safeGuard(_ i: Int, n: Int) -> Int { clamp(i, 0, max(0, n - 1)) }

    /// STACK_SPEC v2: dismiss mueve al FINAL (no borra). Devuelve el nuevo
    /// índice tras mover el ítem en `i` al final del stack. El índice actual
    /// avanza a la siguiente pregunta (clamp), o 0 si el stack queda vacío.
    static func dismissIndexAfterMoveToEnd(_ i: Int, count: Int) -> Int {
        guard count > 1 else { return 0 }     // 0 o 1 ítems → índice 0
        return min(i, count - 2)              // apunta al siguiente (clamp)
    }

    /// STACK_SPEC v2: mueve el ítem en `i` al final (sin borrar).
    static func moveToEnd<T>(_ arr: inout [T], at i: Int) {
        guard arr.indices.contains(i) else { return }
        let item = arr.remove(at: i)
        arr.append(item)
    }

    /// Detección de pregunta NUEVA (Requisito 1): `previous` era el conjunto
    /// anterior, `current` es el nuevo. Devuelve true si aparece al menos un
    /// evento que no estaba antes. `isInitialLoad` silencia la primera carga.
    static func hasNewQuestion(previous: Set<String>, current: Set<String>,
                               isInitialLoad: Bool) -> Bool {
        if isInitialLoad { return false }
        return !current.isSubset(of: previous)   // hay al menos uno nuevo
    }

    static func clamp(_ v: Int, _ lo: Int, _ hi: Int) -> Int {
        min(max(v, lo), hi)
    }
}
