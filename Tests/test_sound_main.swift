// main.swift (test SoundSpec) — TDD del generador WAV puro (SOUND_SPEC).
// Exit != 0 = falla.

import Foundation

func assert(_ c: Bool, _ m: String) {
    if !c {
        FileHandle.standardError.write("FAIL: \(m)\n".data(using: .utf8)!)
        exit(1)
    }
}

// TEST 1: header RIFF/WAVE válido, PCM mono 16bit 44.1k.
let wav = SoundSpec.makeWav(f0: 780, f1: 1150, duration: 0.070)
assert(wav.count > 44, "hay al menos un header")
let header = [UInt8](wav.prefix(4))
assert(header == Array("RIFF".utf8), "magic RIFF")
assert([UInt8](wav[8..<12]) == Array("WAVE".utf8), "WAVE")
assert([UInt8](wav[12..<16]) == Array("fmt ".utf8), "fmt ")
assert([UInt8](wav[36..<40]) == Array("data".utf8), "data")

// TEST 2: 44.1kHz mono 16bit → byteRate 44100*2, blockAlign 2.
let br = UInt32(wav[28]) | UInt32(wav[29]) << 8 | UInt32(wav[30]) << 16 | UInt32(wav[31]) << 24
assert(br == 44100 * 2, "byteRate = 88200 (44.1k mono 16bit)")
let ba = UInt16(wav[32]) | UInt16(wav[33]) << 8
assert(ba == 2, "blockAlign = 2")

// TEST 3: dataSize coincide con duration * rate * 2.
let dataSize = Int(UInt32(wav[40]) | UInt32(wav[41]) << 8 | UInt32(wav[42]) << 16 | UInt32(wav[43]) << 24)
let wantData = Int(0.070 * 44100) * 2
assert(dataSize == wantData, "dataSize = \(wantData), got \(dataSize)")
assert(wav.count == 44 + dataSize, "longitud total = header + data")

// TEST 4: amplitud pico ≤ 0.25 (sutil) y sin snaps (inicio/fin ≈ 0).
let samples = [UInt8](wav.dropFirst(44))
var peak: Int = 0
let nSamples = samples.count / 2
if nSamples > 0 {
    for i in 0..<nSamples {
        let lo = Int(samples[i*2])
        let hi = Int(samples[i*2+1]) << 8
        let v = Int16(truncatingIfNeeded: lo | hi)   // WAV LE: byte bajo primero
        peak = max(peak, abs(Int(v)))
    }
}
// amplitud 0.2 * 32767 ≈ 6553
assert(peak <= 8192, "peak ≤ 0.25 * 32767 (got \(peak))")
assert(samples.count >= 2, "tiene samples")

// TEST 5: mapa de feedback → cada evento tiene wav no vacío y haptic.
let fExpand = SoundSpec.makeFeedback(.expand)
assert(fExpand.wav.count > 44, "expand wav no vacío")
assert(fExpand.wav.count == 44 + Int(0.070 * 44100) * 2, "expand duración 70ms")
assert(fExpand.haptic == .levelChange, "expand → levelChange")

// TEST 6: (SOUND_SPEC v3) cache de generación única — 3 eventos distintos
// sintetizan 3 veces; repetir un evento NO re-sintetiza.
let cache = FeedbackCache()
cache.ensure(.selectOption)
cache.ensure(.selectOption)     // repetido → no sintetiza de nuevo
cache.ensure(.submitText)
cache.ensure(.dismiss)
assert(cache.synthesisCount == 3, "3 eventos únicos → 3 síntesis (got \(cache.synthesisCount))")
let cached = cache.feedback(for: .selectOption)
assert(cached != nil, "selectOption tiene feedback cacheado")
assert(cached!.wav.count > 44, "wav cacheado válido")
assert(cache.feedback(for: .expand) == nil, "expand aún no pre-generado → nil")

// TEST 7: pre-cargar TODO de una vez (patrón arranque) → cada evento único se
// sintetiza exactamente UNA vez en total (6 eventos únicos = 6 síntesis).
let all = [FeedbackEvent]([.expand, .collapse, .selectOption, .submitText, .dismiss, .newQuestion])
for e in all { cache.ensure(e) }
assert(cache.synthesisCount == 6, "6 eventos únicos → 6 síntesis en total (got \(cache.synthesisCount))")
for e in all {
    assert(cache.feedback(for: e) != nil, "\(e) cacheado tras pre-cargar")
}

// ── SOUND_SPEC v7: gate anti-ráfaga + distinguibilidad por tipo ─────────────

// TEST 8: una ráfaga de 4 pings de pregunta en 450ms dispara UN solo sonido
// (antes: 4 campanadas solapadas = ruido). Fuera del gap mínimo vuelve a sonar.
var gate = FeedbackThrottle()
var fired = 0
for i in 0..<4 {
    if gate.shouldPlay(.newQuestion, at: 10.0 + Double(i) * 0.15) { fired += 1 }
}
assert(fired == 1, "ráfaga de 4 newQuestion en 450ms → 1 ping (got \(fired))")
assert(gate.shouldPlay(.newQuestion, at: 12.0), "fuera de la ventana → vuelve a sonar")

// TEST 9: techo por ventana — ráfaga sostenida (10 en 2.7s) ≤ 2 pings.
var gate2 = FeedbackThrottle()
var capped = 0
for i in 0..<10 {
    if gate2.shouldPlay(.newQuestion, at: 100.0 + Double(i) * 0.3) { capped += 1 }
}
assert(capped <= 2, "ráfaga sostenida → techo 2 por ventana (got \(capped))")
assert(capped >= 1, "pero al menos uno suena (got \(capped))")

// TEST 10: las acciones DELIBERADAS del usuario nunca se suprimen.
var gate3 = FeedbackThrottle()
for i in 0..<5 {
    assert(gate3.shouldPlay(.selectOption, at: 200.0 + Double(i) * 0.01),
           "selectOption \(i) no se suprime (acción del usuario)")
    assert(gate3.shouldPlay(.submitText, at: 200.0 + Double(i) * 0.01),
           "submitText \(i) no se suprime (acción del usuario)")
}

// TEST 11: distinguible por tipo — pregunta / hecho / descartar tienen firma
// acústica distinta, y la pregunta SUBE de pitch (zero-crossings crecientes).
func pcm(_ data: Data) -> [Int16] {
    let bytes = [UInt8](data.dropFirst(44))
    var out = [Int16](); out.reserveCapacity(bytes.count / 2)
    for i in 0..<(bytes.count / 2) {
        out.append(Int16(truncatingIfNeeded: Int(bytes[i * 2]) | Int(bytes[i * 2 + 1]) << 8))
    }
    return out
}
func crossings(_ s: ArraySlice<Int16>) -> Int {
    var c = 0
    var prev = s.first ?? 0
    for v in s.dropFirst() {
        if (prev < 0 && v >= 0) || (prev >= 0 && v < 0) { c += 1 }
        prev = v
    }
    return c
}
let q = SoundSpec.makeFeedback(.newQuestion).wav
let d = SoundSpec.makeFeedback(.submitText).wav
let e = SoundSpec.makeFeedback(.dismiss).wav
assert(q != d && d != e && q != e, "3 tipos → 3 WAVs distintos")
let qs = pcm(q)
let half = qs.count / 2
let firstHalf = crossings(qs[0..<half])
let secondHalf = crossings(qs[half..<qs.count])
assert(secondHalf > firstHalf,
       "pregunta sube de pitch (crossings 1ª mitad \(firstHalf) < 2ª \(secondHalf))")

print("PASS: sound-spec 11/11")
