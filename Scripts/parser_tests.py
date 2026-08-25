#!/usr/bin/env python3
"""tests_parser.py — TDD para el parser de opciones del notch.

RED: el parser Swift actual NO detecta la opción 1 cuando empieza con "❯".
Este test codifica el comportamiento deseado (que todas las opciones, incluida
la 1 con cursor, se rendericen como opciones y no se confundan con la pregunta).
"""
import re

# --- Código bajo test: replica la lógica del parser Swift (notchnotch.swift) ---

def parse_question(q: str):
    """Devuelve (qLines, opts). Replica la lógica actual del Swift."""
    qLines: list[str] = []
    opts: list[tuple[str, str]] = []
    for line in q.split("\n"):
        t = line.replace("┃", "").replace("│", "")
        t = t.strip()
        if not t:
            continue
        if t.startswith("↑") or t.startswith("↓") or t in ("enter submit", "esc dismiss"):
            continue
        if "Enter to select" in t or "navigate" in t or "esc to cancel" in t or "Ctrl+]" in t:
            continue
        # FIX (doble glifo): quitar el cursor del inicio ANTES de detectar la
        # opción. herdr manda '❯' (U+276F) o '❱' (U+2771) indistintamente —
        # recortar AMBOS para que "❯ 1." / "❱ 1." se reconozcan como opción.
        stripped = t.lstrip("\u276f \u2771 ").strip()
        if stripped and stripped[0].isdigit() and ("." in stripped or ")" in stripped):
            opts.append((stripped, ""))
        elif opts:
            last = opts.pop()
            opts.append((last[0], (last[1] + " " + t).strip() if last[1] else t))
        else:
            qLines.append(t)
    return qLines, opts


# --- Tests ---

SAMPLE = """Context API
How should a pre-provisioned user change their server-authoritative workspace and legal-entity context?
❯ 1. GET + PUT context (Recommended)
     `GET /context` returns the revalidated current pair; `PUT /context` accepts selection intent,
     atomically validates membership/grant, persists it, and returns the canonical context.
  2. GET + POST switch
     `GET /context` returns the pair; `POST /context/switch` validates and persists a requested
     pair. Clearer action semantics, but adds a second endpoint shape.
  3. No persisted context
     Require workspace and legal-entity intent on each API request and validate atomically.
  4. Type something."""


def test_option_1_is_detected():
    """La opción '❯ 1.' debe detectarse como opción, no como pregunta."""
    qLines, opts = parse_question(SAMPLE)
    joined = " ".join(qLines)
    # RED actual: '❯ 1. GET + PUT' cae en la pregunta porque el parser exige
    # que la línea empiece con dígito, y el cursor "❯ " lo impide.
    assert "1. GET + PUT" not in joined, \
        f"RED: opción 1 se coló en la pregunta: {joined[:70]!r}"
    # Comportamiento deseado (el fix):
    # assert any("1. GET + PUT" in o[0] for o in opts), "opción 1 debe ser opción"


def test_desired_option_count():
    """Debe haber 4 opciones detectadas (1,2,3,4)."""
    _, opts = parse_question(SAMPLE)
    assert len(opts) == 4, f"RED: solo {len(opts)} opciones, esperaba 4"


def test_question_not_empty():
    """La pregunta debe ser 'How should...' no contener opciones."""
    qLines, _ = parse_question(SAMPLE)
    q = " ".join(qLines)
    assert "How should a pre-provisioned user" in q, f"RED: pregunta perdida: {q[:60]!r}"


# DOBLE-GLIFO: herdr a veces manda '❱' (U+2771) en vez de '❯' (U+276F).
# Ambos son visualmente iguales; el parser debe recortar los DOS.
SAMPLE_V = SAMPLE.replace("❯", "❱", 1)


def test_option_1_with_alternate_cursor():
    """'❱ 1. ...' (glifo alterno del harness) también debe ser opción."""
    _, opts = parse_question(SAMPLE_V)
    if len(opts) != 4:
        # RED: solo se detectaron {len(opts)} opciones porque '❱ 1.' se quedó
        # pegado al '❱' (lstrip solo quita '❯ ') y first.isdigit() falló.
        raise AssertionError(f"RED: opción 1 con '❱' no detectada (solo {len(opts)} opciones)")
    assert any("1. Additive" in o[0] or "1. GET" in o[0] or o[0].startswith("1.") for o in opts), \
        "opción 1 debe estar entre las detectadas"


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            try:
                fn()
                print(f"PASS: {name}")
            except AssertionError as e:
                failures += 1
                print(f"FAIL: {name} -> {e}")
    print(f"\n{4 - failures}/4 tests pasados (RED: los que fallan son los bugs)")
    raise SystemExit(0 if failures == 0 else 1)
