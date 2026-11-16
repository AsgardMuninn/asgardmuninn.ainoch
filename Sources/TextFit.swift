// TextFit.swift — lógica PURA del presupuesto de texto de las opciones
// (TEXTFIT_SPEC). La isla expandida tiene altura FIJA (expandedH); esta capa
// decide cuántas líneas de descripción caben y si las filas van compactas,
// ANTES de renderizar. Sin AppKit, testeable.

import Foundation
import CoreGraphics

/// Plan de layout de las filas de opción.
struct OptionLayoutPlan: Equatable {
    /// Líneas de descripción por fila (0 = sin descripción, título siempre visible).
    let descLineLimit: Int
    /// Padding vertical de cada fila (10 normal, 6 compacto).
    let rowVPad: CGFloat
    /// Separación entre filas (8 normal, 4 apretado).
    let rowGap: CGFloat
}

enum OptionTextFit {
    // MARK: Métricas del layout (deben coincidir con views.swift expanded())
    static let topPad: CGFloat = 32            // notchHeight
    static let headerH: CGFloat = 16           // header 12pt semibold
    static let questionTopPad: CGFloat = 8
    static let questionLineH: CGFloat = 20     // 16pt semibold
    static let optionsTopPad: CGFloat = 12
    static let normalRowGap: CGFloat = 8
    static let tightRowGap: CGFloat = 4
    static let titleH: CGFloat = 16            // 13pt semibold
    static let titleDescGap: CGFloat = 2
    static let descLineH: CGFloat = 14.5       // 11.5pt
    static let normalRowVPad: CGFloat = 10
    static let compactRowVPad: CGFloat = 6
    static let spacerMin: CGFloat = 4
    static let dismissH: CGFloat = 40          // botón Descartar
    static let bottomPad: CGFloat = 16
    static let maxDescLines: Int = 3           // tope histórico (CONTENT/UX)
    static let charsPerQuestionLine: Int = 46  // medido a 16pt en 516pt útiles
    static let maxQuestionLines: Int = 3

    /// Líneas que ocupará la pregunta: respeta saltos explícitos del harness y
    /// estima el wrap por ancho; siempre 1..3.
    static func questionLines(_ question: String) -> Int {
        let explicit = question.components(separatedBy: "\n").count
        let wrapped = Int(ceil(Double(question.count) / Double(charsPerQuestionLine)))
        return min(maxQuestionLines, max(1, max(explicit, wrapped)))
    }

    /// Altura total del contenido expandido para un plan dado.
    static func totalHeight(optionCount: Int, questionLines: Int,
                            plan: OptionLayoutPlan) -> CGFloat {
        let n = CGFloat(max(optionCount, 1))
        let q = CGFloat(min(max(questionLines, 1), maxQuestionLines))
        let fixed = topPad + headerH + questionTopPad + q * questionLineH
            + optionsTopPad + plan.rowGap * (n - 1) + spacerMin + dismissH + bottomPad
        let desc = plan.descLineLimit > 0
            ? titleDescGap + CGFloat(plan.descLineLimit) * descLineH
            : 0
        let row = plan.rowVPad * 2 + titleH + desc
        return fixed + n * row
    }

    /// Elige el plan más generoso que ENTRA en expandedH. Cascada:
    /// normal (3→1 líneas) → compacto (3→1) → apretado (3→1) → sin descripción.
    static func plan(optionCount: Int, questionLines: Int,
                     expandedH: CGFloat = IslandTransition.expandedH) -> OptionLayoutPlan {
        let tiers: [(CGFloat, CGFloat)] = [
            (normalRowVPad, normalRowGap),
            (compactRowVPad, normalRowGap),
            (compactRowVPad, tightRowGap),
        ]
        for (vpad, gap) in tiers {
            for lines in stride(from: maxDescLines, through: 1, by: -1) {
                let candidate = OptionLayoutPlan(descLineLimit: lines, rowVPad: vpad,
                                                 rowGap: gap)
                if totalHeight(optionCount: optionCount, questionLines: questionLines,
                               plan: candidate) <= expandedH {
                    return candidate
                }
            }
        }
        // Degenerado (más opciones de las que el harness real manda): mínimo
        // espacio por fila, títulos visibles.
        return OptionLayoutPlan(descLineLimit: 0, rowVPad: compactRowVPad,
                                rowGap: tightRowGap)
    }
}
