// SoundSpec.swift — LÓGICA PURA de sonido/haptics (SOUND_SPEC.md).
// Genera WAV PCM16 mono 44.1kHz programáticamente (sin assets) y define el
// mapa de eventos → feedback. Sin AppKit: testeable con swiftc.

import Foundation

/// Tipo de haptic (SOUND_SPEC): se mapea a NSHapticFeedbackManager.FeedbackPattern
/// en la capa AppKit. Se mantiene como enum puro para poder testear.
enum HapticKind {
    case levelChange    // NSHapticFeedbackManager.FeedbackPattern.levelChange
    case generic        // .generic
}

/// Eventos de UI que producen feedback (Hashable para cachear).
enum FeedbackEvent: Hashable {
    case expand
    case collapse
    case selectOption
    case submitText
    case dismiss
    case newQuestion   // STACK_SPEC req 1: llegó una pregunta nueva (discreto)
}

enum SoundSpec {
    static let sampleRate = 44100

    /// WAV PCM16 mono RIFF válido, con chirrido (f0→f1) y decaimiento exp.
    /// amplitude ≤ 0.25 (sutil, Raycast/Arc style).
    static func makeWav(f0: Double, f1: Double, duration: Double,
                        amplitude: Double = 0.2) -> Data {
        let n = Int(duration * Double(sampleRate))
        var pcm = [UInt8]()
        pcm.reserveCapacity(n * 2)
        var phase: Double = 0
        var freq: Double = f0
        for i in 0..<n {
            let t = Double(i) / Double(sampleRate)
            let progress = t / duration
            freq = f0 + (f1 - f0) * progress          // chirp lineal
            phase += 2 * .pi * freq / Double(sampleRate)
            let env = exp(-4.0 * progress)            // decaimiento exp
            let s = amplitude * env * sin(phase)
            let v = Int16(max(-1, min(1, s)) * 32767)
            pcm.append(UInt8(truncatingIfNeeded: v & 0xFF))
            pcm.append(UInt8(truncatingIfNeeded: (v >> 8) & 0xFF))
        }
        return makeRiffHeader(dataSize: n * 2) + Data(pcm)
    }

    /// Header RIFF/WAVE PCM16 mono 44.1k.
    static func makeRiffHeader(dataSize: Int) -> Data {
        var d = Data()
        d.append(Data("RIFF".utf8))
        d.append(leU32(UInt32(36 + dataSize)))
        d.append(Data("WAVE".utf8))
        d.append(Data("fmt ".utf8))
        d.append(leU32(16))                       // fmt chunk size
        d.append(leU16(1))                        // PCM
        d.append(leU16(1))                        // mono
        d.append(leU32(UInt32(sampleRate)))
        d.append(leU32(UInt32(sampleRate * 2)))   // byteRate
        d.append(leU16(2))                        // blockAlign
        d.append(leU16(16))                       // bits
        d.append(Data("data".utf8))
        d.append(leU32(UInt32(dataSize)))
        return d
    }

    /// Mapa de eventos → feedback (SOUND_SPEC tabla).
    static func makeFeedback(_ e: FeedbackEvent) -> (wav: Data, haptic: HapticKind) {
        switch e {
        case .expand:       return (makeWav(f0: 780, f1: 1150, duration: 0.070), .levelChange)
        case .collapse:     return (makeWav(f0: 1150, f1: 780, duration: 0.070), .levelChange)
        case .selectOption: return (makeWav(f0: 1350, f1: 1350, duration: 0.030, amplitude: 0.15), .generic)
        case .submitText:   return (makeWav(f0: 1600, f1: 1600, duration: 0.055, amplitude: 0.18), .generic)
        case .dismiss:      return (makeWav(f0: 500, f1: 400, duration: 0.060, amplitude: 0.16), .levelChange)
        case .newQuestion:  return (makeWav(f0: 900, f1: 1320, duration: 0.070, amplitude: 0.16), .generic)
        }
    }

    // Helpers LE
    private static func leU16(_ v: UInt16) -> Data {
        var d = Data(); d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)); return d
    }
    private static func leU32(_ v: UInt32) -> Data {
        var d = Data(); d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF))
        d.append(UInt8((v >> 16) & 0xFF)); d.append(UInt8((v >> 24) & 0xFF)); return d
    }
}

/// SOUND_SPEC v7: gate anti-ráfaga. Los eventos DISCRETOS que NO inicia el
/// usuario (p.ej. `.newQuestion`, disparado por el poll de eventos) pueden
/// llegar en ráfaga — varias preguntas nuevas en pocos segundos. Reproducir
/// todas = campanada solapada (ruido, "spam"), que Apple HIG desaconseja
/// ("avoid overusing haptics"). Este gate es lógica PURA (sin AppKit) y
/// decide si un evento merece sonar; las acciones deliberadas del usuario
/// (.selectOption/.submitText/.dismiss) NUNCA se suprimen.
struct FeedbackThrottle {
    /// Separación mínima entre dos pings del MISMO evento (s). 500ms: por
    /// debajo de eso dos pings de 70ms se perciben como un solo "doble ring"
    /// confuso, no como dos avisos.
    static let minGap: Double = 0.5
    /// Ventana deslizante de ráfaga (s).
    static let window: Double = 3.0
    /// Techo de pings por ventana para eventos de ráfaga.
    static let maxInWindow: Int = 2
    /// Eventos limitados (no iniciados por el usuario).
    static let burstLimited: Set<FeedbackEvent> = [.newQuestion]

    private var played: [Double] = []   // timestamps de pings permitidos

    /// `t` = reloj monótono del llamador (`ProcessInfo.systemUptime`).
    mutating func shouldPlay(_ event: FeedbackEvent, at t: Double) -> Bool {
        guard Self.burstLimited.contains(event) else { return true }
        played.removeAll { t - $0 >= Self.window }      // podar fuera de ventana
        if let last = played.last, t - last < Self.minGap { return false }
        if played.count >= Self.maxInWindow { return false }
        played.append(t)
        return true
    }
}

/// SOUND_SPEC v3: cache de generación ÚNICA. Pre-genera cada WAV una sola vez
/// (fuera del hot path) para que el primer play no congele la UI (el init del
/// audio engine + síntesis NO corre en el momento del click).
final class FeedbackCache {
    private var wavs: [FeedbackEvent: Data] = [:]
    private var haptics: [FeedbackEvent: HapticKind] = [:]
    private(set) var synthesisCount = 0     // nº de síntesis reales (para test)

    /// Pre-genera (si aún no existe) el feedback para un evento.
    func ensure(_ event: FeedbackEvent) {
        if wavs[event] == nil {
            let f = SoundSpec.makeFeedback(event)
            wavs[event] = f.wav
            haptics[event] = f.haptic
            synthesisCount += 1
        }
    }

    /// Devuelve el feedback CACHEADO para el evento (nunca re-sintetiza).
    func feedback(for event: FeedbackEvent) -> (wav: Data, haptic: HapticKind)? {
        guard let w = wavs[event] else { return nil }
        return (w, haptics[event] ?? .generic)
    }
}
