# TEXTFIT_SPEC — Presupuesto de texto de opciones dentro de la isla expandida

**Problema medido (2026-11-16):** la isla expandida tiene altura FIJA
(`IslandTransition.expandedH = 380`, invariante de TRANSITION_SPEC: crece solo
top→bottom, no puede estirarse). Cada fila de opción renderizaba hasta 3 líneas
de descripción (11.5pt) + 1 de título, sin relación con la altura disponible.

Cálculo del peor caso actual (3 opciones, pregunta de 3 líneas):

```
32 notch + 16 header + 8 top pregunta + 60 pregunta(3x20) + 12 top opciones
+ 16 gaps(2x8) + 3x(20 pad + 16 título + 2 gap + 43.5 desc(3x14.5))
+ 4 spacer + 40 Descartar + 16 bottom  =  434.5pt  >  380pt  → overflow ~54pt
```

Efecto real: SwiftUI comprime/recorta filas de forma arbitraria (la última
opción o el botón Descartar quedan cortados) cuando el harness manda
descripciones largas — que es el caso normal de Claude Code/Codex.

## Requisito

Una función PURA decide, antes de renderizar, cuántas líneas de descripción
permite cada fila y qué padding vertical usan, de modo que el contenido total
NUNCA exceda `expandedH`. El título de la opción siempre se ve (1 línea).

## Modelo

```
plan(optionCount, questionLines) -> OptionLayoutPlan { descLineLimit, rowVPad }
```

Preferencia en cascada (se elige el primer nivel que ENTRA en expandedH):

1. filas normales (`rowVPad = 10`) con desc de 3 → 2 → 1 líneas
2. filas compactas (`rowVPad = 6`) con desc de 3 → 2 → 1 líneas
3. filas compactas sin descripción (`descLineLimit = 0`)

`questionLines` = líneas estimadas de la pregunta: `ceil(chars / 46)` acotado a
1...3 (46 chars/línea medidos a 16pt semibold en 516pt de ancho útil).

## Métricas (deben coincidir con views.swift)

| Bloque | Valor |
|---|---|
| top pad (notch) | 32 |
| header | 16 |
| top pregunta / por línea | 8 / 20 |
| top opciones | 12 |
| gap entre filas | 8 |
| fila: título / gap título-desc | 16 / 2 |
| fila: padding vertical | 20 normal, 12 compacto |
| línea de desc | 14.5 |
| spacer mínimo | 4 |
| Descartar | 40 |
| bottom pad | 16 |

## Verificación

- Test puro: casos medidos (3 opciones/3 líneas de pregunta → 1 línea de desc;
  2 opciones → 3 líneas; 5 opciones → compacto sin desc).
- Test de invariante: para toda combinación `optionCount 1...6`,
  `questionLines 1...3`, la altura total calculada ≤ `expandedH`.
- Build completo + resto de suites verdes.
