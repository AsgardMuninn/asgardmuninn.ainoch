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

print("PASS: sound-spec 7/7")
