// views.swift — AI Notch v2 (SwiftUI-base, patrón canónico de Dynamic Island)
//
// Arquitectura:
//  - NotchShape: SwiftUI Shape con "ears" cóncavas arriba (imita la muesca) y
//    esquinas convexas redondeadas abajo.
//  - NotchModel: estado observable (eventos de herdr + estado compact/expanded).
//  - NotchContentView: la vista que vive dentro del NSPanel, rellena con negro
//    y recortada con NotchShape. Compact = pill (pregunta en 1 línea);
//    Expanded = pregunta + opciones + botón Descartar al fondo.
//  - NotchWindow: NSPanel borderless/transparente a CGShieldingWindowLevel,
//    posicionado con screen.frame (NO visibleFrame) → pegado a la menu bar.
//  - NotchAppDelegate: crea la ventana, hace poll del reader y actualiza el modelo.

import AppKit
import Combine
import SwiftUI

// MARK: - Modelo

struct NotchEvent: Decodable {
    let agent: String?
    let pane_id: String?
    let status: String?
    let question: String?
    let context: NotchContext?
    struct NotchContext: Decodable {
        let cwd: String?
        let terminal_title: String?
    }
}

struct NotchResponse: Decodable {
    let events: [NotchEvent]?
}

// MARK: - NotchShape (Dynamic Island canónico)

struct NotchShape: Shape {
    var topCornerRadius: CGFloat = 10   // "ears" cóncavas que imitan la muesca
    var bottomCornerRadius: CGFloat = 18  // píldora abajo

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let tr = min(topCornerRadius, rect.width / 2)
        let br = min(bottomCornerRadius, rect.width / 2)

        // Empieza arriba-izquierda.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // Ear superior-izquierda: curva cóncava (imita el notch físico)
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr, y: rect.minY + tr),
                       control: CGPoint(x: rect.minX + tr, y: rect.minY))
        // Borde izquierdo hacia abajo
        p.addLine(to: CGPoint(x: rect.minX + tr, y: rect.maxY - br))
        // Esquina inferior-izquierda convexa (píldora)
        p.addQuadCurve(to: CGPoint(x: rect.minX + tr + br, y: rect.maxY),
                       control: CGPoint(x: rect.minX + tr, y: rect.maxY))
        // Borde inferior
        p.addLine(to: CGPoint(x: rect.maxX - tr - br, y: rect.maxY))
        // Esquina inferior-derecha convexa
        p.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.maxY - br),
                       control: CGPoint(x: rect.maxX - tr, y: rect.maxY))
        // Borde derecho hacia arriba
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY + tr))
        // Ear superior-derecha: curva cóncava
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Parseo (pregunta → opciones), sin lógica de presentación

struct ParsedQuestion {
    let header: String
    let question: String
    var options: [(title: String, desc: String)] = []
    let pane: String
}

func parseQuestion(_ ev: NotchEvent) -> ParsedQuestion? {
    guard let q = ev.question, !q.isEmpty else { return nil }
    var qLines: [String] = []
    var opts: [(String, String)] = []
    for line in q.components(separatedBy: "\n") {
        let t = line.replacingOccurrences(of: "┃", with: "")
            .replacingOccurrences(of: "│", with: "")
            .trimmingCharacters(in: .whitespaces)
        if t.isEmpty { continue }
        if t.hasPrefix("↑") || t.hasPrefix("↓") || t == "enter submit" || t == "esc dismiss" { continue }
        if t.contains("Enter to select") || t.contains("navigate") || t.contains("esc to cancel") || t.contains("Ctrl+]") { continue }
        // FIX (doble glifo): herdr manda '❯' (U+276F) o '❱' (U+2771) como
        // cursor — recortar AMBOS para que "❯ 1."/"❱ 1." se detecten como opción.
        let stripped = t.trimmingCharacters(in: CharacterSet(charactersIn: "\u{276F} \u{2771} "))
        if let first = stripped.first, first.isNumber,
           (stripped.contains(".") || stripped.contains(")")) {
            opts.append((stripped, ""))
        } else if !opts.isEmpty {
            var last = opts.removeLast()
            last.1 = last.1.isEmpty ? t : last.1 + " " + t
            opts.append(last)
        } else {
            qLines.append(t)
        }
    }
    let header = "\(ev.agent ?? "agent")  \(ev.status ?? "blocked")  •  \(ev.context?.terminal_title ?? ev.pane_id ?? "")"
    return ParsedQuestion(header: header,
                          question: qLines.joined(separator: " "),
                          options: opts,
                          pane: ev.pane_id ?? "")
}

// MARK: - Estado observable

@MainActor
final class NotchModel: ObservableObject {
    @Published var events: [NotchEvent] = []
    @Published var isExpanded = false
    @Published var isHovering = false
    @Published var hoverKeys = Set<String>()   // pane ids con hover
    @Published var textInputActive = false     // CONTENT_SPEC: modo texto libre
    @Published var textInputValue = ""
    @Published var stackIndex = 0              // STACK_SPEC: índice actual del stack
    @Published var keyboardSelection: Int? = nil  // KEYBOARD_SPEC: highlight ↑↓

    // STACK_SPEC req 1: tras la primera carga (silencio), permite el ping de
    // preguntas nuevas.
    var canSignalNewQuestion = false

    var current: ParsedQuestion? {
        guard events.indices.contains(stackIndex) else { return nil }
        return parseQuestion(events[stackIndex])
    }
    var stackCount: Int { max(0, events.count) }
}

// MARK: - Vista principal

struct NotchContentView: View {
    @ObservedObject var model: NotchModel
    var onSelect: (Int) -> Void
    var onDismiss: () -> Void
    var onFocusPane: () -> Void
    var onSubmitText: (String) -> Void

    @FocusState private var textFieldFocused: Bool   // REQ 2b: foco del input

    // Geometría (TRANSITION_SPEC.md, testeada en test_island_main.swift):
    // la isla es UN contenedor cuyo frame viene de islandFrame(t) — centro
    // SIEMPRE en el notch, top SIEMPRE en screenH (crece hacia abajo).
    var notchGap: CGFloat = 120         // hueco central (el notch físico)
    var sidePillW: CGFloat = 96
    var compactH: CGFloat = 32          // NO sobresale del notch (test 2/4)

    private var islaT: CGFloat { model.isExpanded ? 1 : 0 }
    // Frame HOST-LOCAL (requisito 5): la isla queda PINZADA al TOP del hosting
    // (y=0) → la animación arranca DESDE EL NOTCH. El hosting ancla es 560x380
    // (el frame animado se estira al ritmo de la transición desde ahí).
    private var hostFrame: (x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) {
        IslandTransition.hostingLocalFrame(hostW: 560, hostH: 380, t: islaT)
    }

    var body: some View {
        // Contenedor del hosting (560x380) con overlay(alignment:.top): pinza el
        // borde superior de la isla al TOP del hosting → crece hacia abajo.
        Color.clear
            .frame(width: 560, height: 380)
            .overlay(alignment: .top) {
                island
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.78),
                       value: model.isExpanded)
            // v6b: el TextField toma el foco real al ABRIR el input, tanto por
            // click como por Enter (openTextMode). Sin esto, Cmd+A/flechas no
            // aplicaban al abrir con teclado.
            .onChange(of: model.textInputActive) { active in
                if active { textFieldFocused = true }
            }
    }

    // La ISLA: UN solo contenedor que crece según hostFrame (top-anchored).
    // La forma negra y el contenido comparten frame/clipShape → el contenido
    // "emerge" con la forma, sin branches de tamaño ni matchedGeometryEffect.
    private var island: some View {
        ZStack(alignment: .top) {
            NotchShape()
                .fill(Color.black)
                .frame(width: hostFrame.w, height: hostFrame.h, alignment: .top)
                .clipShape(NotchShape())

            if let parsed = model.current {
                if model.isExpanded {
                    expanded(parsed)
                        .transition(.opacity)
                } else {
                    compact(parsed)
                }
            }
        }
        .frame(width: hostFrame.w, height: hostFrame.h, alignment: .top)
        .clipShape(NotchShape())
        .contentShape(Rectangle())
        // REQ 2a: click FUERA del campo de texto → volver a las opciones.
        // (El TextField y los botones consumen su propio tap; el resto del
        // fondo de la isla dispara este gesto.)
        .onTapGesture {
            if ContentState.onTapOutside(textInputActive: model.textInputActive) {
                withAnimation(.easeInOut(duration: 0.22)) {
                    model.textInputActive = false
                    model.textInputValue = ""
                }
                textFieldFocused = false
            }
        }
    }

    // Estado compacto (HIG): dos pills a los LADOS del notch.
    // Izquierda: agente con el dot. Derecha: conteo pendientes. El notch
    // físico (hueco central) queda visible → no tapa info útil.
    private func compact(_ parsed: ParsedQuestion) -> some View {
        HStack(spacing: 0) {
            // Pill izquierda: agente
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1, green: 0.42, blue: 0.42)).frame(width: 7, height: 7)
                Text(agentShort(parsed.header))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
            }
            .frame(width: sidePillW, height: compactH)

            // Hueco central = el notch físico (transparente, no tapa nada)
            Spacer()
                .frame(width: notchGap, height: compactH)

            // Pill derecha: conteo de preguntas pendientes
            HStack(spacing: 4) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.85))
                Text("\(model.stackCount)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: sidePillW, height: compactH)
        }
        .frame(width: hostFrame.w, height: compactH)
        .background(Color.clear)
        // Hover lo maneja el mouse monitor GLOBAL (isInsideIsland, test 8):
        // con ignoresMouseEvents dinámico el onHover de SwiftUI no llega.
        .contentShape(Rectangle())
        .onTapGesture { model.isExpanded = true }
    }

    /// Extrae el nombre del agente del header ("pi  blocked  •  ..." → "pi").
    private func agentShort(_ header: String) -> String {
        header.split(separator: " ").first.map(String.init) ?? "agent"
    }

    // Estado expandido: header (+ navegación stack) + pregunta + opciones +
    // Descartar al fondo
    private func expanded(_ parsed: ParsedQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: agente + estado + "n de N" + navegación ◀ ▶ (STACK_SPEC req 2)
            HStack(spacing: 8) {
                Text(parsed.header)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 1, green: 0.42, blue: 0.42))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if model.stackCount > 1 {
                    // Navegación del stack sin descartar (STACK_SPEC)
                    Button(action: {
                        model.stackIndex = StackLogic.stackPrev(model.stackIndex)
                        model.keyboardSelection = nil     // reset del highlight
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(StackLogic.stackCanPrev(model.stackIndex) ? 0.9 : 0.35))
                    }
                    .buttonStyle(.plain)
                    .disabled(!StackLogic.stackCanPrev(model.stackIndex))

                    Text(StackLogic.stackLabel(model.stackIndex, model.stackCount))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.7))

                    Button(action: {
                        model.stackIndex = StackLogic.stackNext(model.stackIndex, model.stackCount)
                        model.keyboardSelection = nil     // reset del highlight
                    }) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(StackLogic.stackCanNext(model.stackIndex, model.stackCount) ? 0.9 : 0.35))
                    }
                    .buttonStyle(.plain)
                    .disabled(!StackLogic.stackCanNext(model.stackIndex, model.stackCount))
                }
            }
            .padding(.horizontal, 22)
            // REQ 7+9+9b: la isla queda pegada al tope (sin borde raro con
            // menu bar transparente) y el título baja notchHeight para
            // quedar pegado JUSTO bajo el notch (sin margen extra).
            .padding(.top, IslandTransition.notchHeight)

            // Pregunta (tocable → focus pane)
            Text(parsed.question)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(3)
                .padding(.horizontal, 22)
                .padding(.top, 8)
                .contentShape(Rectangle())
                .onTapGesture { onFocusPane() }

            // Opciones ↔ Input de texto (CONTENT_SPEC): el MISMO contenedor se
            // transforma fluidamente (con withAnimation + .transition) — no salta
            // entre dos layouts. Al tocar "Type something" las opciones se ocultan y
            // un campo de texto expande en su lugar.
            VStack(spacing: 8) {
                if model.textInputActive {
                    // SOUND_SPEC v5: estado del texto LOCAL a la sub-vista →
                    // teclear no re-renderiza toda la isla (antes: lag por @Published).
                    FreeTextInput(focused: $textFieldFocused) { submitted in
                        submitFreeText(submitted)
                    }
                } else {
                    ForEach(Array(parsed.options.enumerated()), id: \.offset) { i, opt in
                        OptionRowView(
                            index: i + 1,
                            title: opt.title,
                            desc: opt.desc,
                            isHovered: model.hoverKeys.contains(parsed.pane + "#\(i + 1)"),
                            // KEYBOARD_SPEC: highlight de teclado (↑↓)
                            isHighlighted: model.keyboardSelection == i + 1
                        ) {
                            model.hoverKeys.insert(parsed.pane + "#\(i + 1)")
                        } onExit: {
                            model.hoverKeys.remove(parsed.pane + "#\(i + 1)")
                        } onClick: {
                            // CONTENT_SPEC: "Type something" → modo texto; sino → opción
                            let outcome = ContentState.onOptionTap(
                                optionIndex: i + 1, optionTitle: opt.title,
                                textInputActive: model.textInputActive)
                            switch outcome {
                            case .enterTextMode:
                                withAnimation(.easeInOut(duration: 0.22)) {
                                    model.textInputValue = ""
                                    model.textInputActive = true
                                }
                                textFieldFocused = true    // REQ 2b: foco al abrir
                            case .selectOption(let n):
                                onSelect(n)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)

            Spacer(minLength: 4)

            // Botón Descartar — abajo del todo (no ícono)
            Button(action: onDismiss) {
                Text("Descartar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.18))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.bottom, 16)
        }
        .frame(width: hostFrame.w, height: hostFrame.h, alignment: .top)
        // Hover lo maneja el mouse monitor global (isInsideIsland).
    }

    private func truncate(_ s: String, to n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n)) + "…"
    }

    /// CONTENT_SPEC requisito 4: submit del texto libre. Recibe el texto desde
    /// FreeTextInput (estado local). Solo envía si no está vacío; cierra el modo.
    private func submitFreeText(_ text: String) {
        let outcome = ContentState.onTextSubmit(text)
        switch outcome {
        case .send(let txt):
            onSubmitText(txt)
            withAnimation(.easeOut(duration: 0.2)) {
                model.textInputActive = false
            }
        case .ignore:
            break   // vacío → no hacer nada (CONTENT_SPEC)
        }
    }
}

// MARK: - Fila de opción con hover feedback

struct OptionRowView: View {
    let index: Int
    let title: String
    let desc: String
    let isHovered: Bool
    let isHighlighted: Bool    // KEYBOARD_SPEC: highlight ↑↓ (patrón Raycast)
    let onEnter: () -> Void
    let onExit: () -> Void
    let onClick: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            if !desc.isEmpty {
                Text(desc)
                    .font(.system(size: 11.5))
                    .foregroundColor(Color.white.opacity(0.78))
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(isHighlighted ? 0.55 : 0),
                        lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { h in
            if h { onEnter() } else { onExit() }
        }
        .onTapGesture { onClick() }
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .animation(.easeOut(duration: 0.12), value: isHighlighted)
    }

    // KEYBOARD_SPEC: highlight de teclado = fondo más claro (0.38) que el hover
    // (0.24) y con borde visible — se distingue del realce sutil del mouse.
    private var backgroundColor: Color {
        if isHighlighted { return Color.white.opacity(0.38) }
        return Color.white.opacity(isHovered ? 0.24 : 0.15)
    }
}

// MARK: - Input de texto libre (SOUND_SPEC v5: aislado del re-render de la isla)

/// El TextField vive en su propia vista con @State LOCAL: teclear solo
/// re-renderiza esta vista, no toda la isla (antes, @Published textInputValue
/// en el modelo re-renderizaba TODO con cada carácter → lag al escribir).
/// El texto se sincroniza al modelo SOLO al submit.
struct FreeTextInput: View {
    var focused: FocusState<Bool>.Binding
    var onSubmit: (String) -> Void
    @State private var text = ""

    var body: some View {
        TextField("Escribí tu respuesta libre…", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .focused(focused)
            .onSubmit { onSubmit(text) }
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }
}

// MARK: - Ventana notch (NSPanel)

final class NotchWindow: NSPanel {
    // KEYBOARD_SPEC + CONTENT_SPEC 2b: la ventana acepta el teclado (can be key)
    // cuando la isla está expandida (navegación) o en modo texto (escribir).
    // El resto del tiempo NO roba el foco al desktop.
    weak var model: NotchModel?
    override var canBecomeKey: Bool {
        model?.isExpanded == true || model?.textInputActive == true
    }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = false
        ignoresMouseEvents = false   // necesitamos clicks
        isFloatingPanel = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
        appearance = NSAppearance(named: .darkAqua)
    }

    required init?(coder: NSCoder) { fatalError() }

    // Posiciona la ventana AL MISMO NIVEL del notch (req 9c): la NSPanel (560x380,
    // req 6) pega SIEMPRE al tope físico (top = screenH), en ambos estados. El
    // título baja por su propio padding (notchHeight) dentro de la vista expanded.
    // Sin offset en la posición — se usa exactamente screenFrame(isExpanded:).
    func place(isExpanded: Bool) {
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        guard let screen = NSScreen.main else { return }
        let w: CGFloat = 560                     // window fija (req 6)
        let h: CGFloat = 380
        let x = (screen.frame.width - w) / 2
        let y = screen.frame.height - h          // top = screenH (al nivel del notch)
        _ = isExpanded
        setFrame(CGRect(x: x, y: y, width: w, height: h), display: false)
    }
}

// MARK: - AppDelegate

@MainActor
final class NotchAppDelegate: NSObject, NSApplicationDelegate {
private var window: NotchWindow?
private let model = NotchModel()
private var timer: Timer?
private var cancellables = Set<AnyCancellable>()
private var keyboardMon: Any?   // KEYBOARD_SPEC: local monitor keyDown (retenido)
// SOUND_SPEC v3: cache de sonidos pre-generado (evita el congelamiento del
// primer play — la síntesis + init de NSSound NO corren en el hot path).
private let feedback = FeedbackCache()
private var sounds: [FeedbackEvent: NSSound] = [:]   // NSSound pre-construidos

static let herdrBin: String = {
    // Ruta del CLI herdr — configurable vía env HERDR_BIN, fallback a shim mise.
    if let env = ProcessInfo.processInfo.environment["HERDR_BIN"], !env.isEmpty {
        return env
    }
    let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
    return "\(home)/.local/share/mise/shims/herdr"
}()
let readerURL: URL = {
    // Reader fuente de eventos — configurable vía env AINOCH_READER_URL.
    if let s = ProcessInfo.processInfo.environment["AINOCH_READER_URL"], let u = URL(string: s) {
        return u
    }
    return URL(string: "http://127.0.0.1:8900/event.json")!
}()

func applicationDidFinishLaunching(_ notification: Notification) {
    // SOUND_SPEC v4: pre-generar TODOS los sonidos al arranque (fuera del hot
    // path del click): síntesis + construcción del NSSound + PRE-WARM del
    // hardware (play+stop inmed.) — el primer play de cada sonido ya no
    // adquiere el device de audio (eso causaba lag/freeze en la app).
    for e in [FeedbackEvent.expand, .collapse, .selectOption, .submitText, .dismiss, .newQuestion] {
        feedback.ensure(e)
        if let w = feedback.feedback(for: e)?.wav, let snd = NSSound(data: w) {
            // Pre-warm silencioso (SOUND_SPEC v4): play+stop con volumen 0
            // adquiere hardware + puebla buffers sin que se ESCUCHE nada.
            snd.volume = 0
            snd.play()
            snd.stop()
            snd.volume = 0.8
            sounds[e] = snd
        }
    }
    let win = NotchWindow()
    win.model = model    // REQ 2b: canBecomeKey dinámico según el modo texto
    let hosting = NSHostingView(rootView:
        NotchContentView(model: model, onSelect: { [weak self] n in
            self?.selectOption(n)
        }, onDismiss: { [weak self] in
            self?.dismiss()
        }, onFocusPane: { [weak self] in
            self?.focusPane()
        }, onSubmitText: { [weak self] txt in
            self?.sendFreeText(txt)
        })
    )
    // El hosting SIGUE a la ventana (autoresizing).
    hosting.autoresizingMask = [.width, .height]
    hosting.frame = NSRect(x: 0, y: 0, width: 560, height: 380)
    win.contentView = hosting
    // SOLUCIÓN FINAL (req 6): NSPanel 560x380 → mantiene el ancla de la
    // transición; el desktop no se bloquea por ignoresMouseEvents dinámico.
    // Requisito 7: la posición depende del estado (expandido baja bajo notch).
    win.place(isExpanded: false)
    win.orderFrontRegardless()
    self.window = win

    // Reposicionar la ventana al cambiar de estado (requisito 7): expandido
    // baja bajo el notch; colapsado vuelve al tope. Sin animación AppKit.
    // SOUND_SPEC v2: NO se reproduce feedback aquí (hover = continuo → silencio,
    // best practices Apple HIG "discrete events" / "avoid overusing").
    // KEYBOARD_SPEC: al expandir, la ventana se hace key (recibe teclas sin
    // activar la app — panel nonactivating); al colapsar libera el teclado.
    model.$isExpanded
        .receive(on: RunLoop.main)
        .sink { [weak self] expanded in
            guard let self = self, let win = self.window else { return }
            win.place(isExpanded: expanded)
            if expanded {
                win.makeKey()
            } else {
                win.resignKey()
            }
        }
        .store(in: &cancellables)

    // REQ 2b: al activar el modo texto, la window necesita ser key para que el
    // TextField reciba el teclado (canBecomeKey dinámico + activate + focus).
    model.$textInputActive
        .receive(on: RunLoop.main)
        .sink { [weak self] active in
            guard let self = self, let win = self.window else { return }
            let t0 = CFAbsoluteTimeGetCurrent()
            if active {
                // SOUND_SPEC v5+v6: foco INMEDIATO y barato (panel key +
                // firstResponder). El NSApp.activate (que habilita Cmd+A,
                // flechas y ESC en el campo) se DIFIERE con async → sale del
                // hot path, no bloquea al abrir, y la app se activa al tick.
                win.makeKey()
                win.makeFirstResponder(win.contentView)
                DispatchQueue.main.async {
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            NSLog("AINOCH TIMING activeSink=%d cost=%.4fms",
                  active ? 1 : 0, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
        }
        .store(in: &cancellables)

    // KEYBOARD_SPEC: local monitor de teclado — resuelve cada KeyDown a una
    // acción (navegar stack / seleccionar / colapsar) SOLO cuando la isla está
    // expandida y no se está escribiendo. Consume el evento si aplica; de lo
    // contrario lo deja pasar (return event).
    keyboardMon = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self = self else { return event }
        let t0 = CFAbsoluteTimeGetCurrent()
        // v6c + v7 (KEYBOARD_SPEC): Cmd+A en modo texto → selectAll del field
        // editor (la app es .accessory sin menú Edit; el key equivalent no se
        // enruta por el sistema). La decisión es PURA (KeyboardSpec.isCmdASelectAll)
        // y usa el char lógico (charactersIgnoringModifiers) en vez del keyCode
        // físico 0 → no depende del layout de teclado (ANSI/ISO/Dvorak).
        if KeyboardSpec.isCmdASelectAll(
            char: event.charactersIgnoringModifiers ?? "",
            commandDown: event.modifierFlags.contains(.command),
            isTextInputActive: self.model.textInputActive) {
            if let editor = self.window?.fieldEditor(false, for: self.window?.contentView) as? NSTextView {
                editor.selectAll(nil)
            }
            NSLog("AINOCH TIMING keyDown cmd+A cost=%.4fms",
                  (CFAbsoluteTimeGetCurrent() - t0) * 1000)
            return nil
        }
        let action = KeyboardSpec.resolveKey(
            char: event.charactersIgnoringModifiers ?? "",
            keyCode: event.keyCode,
            isExpanded: self.model.isExpanded,
            isTextInputActive: self.model.textInputActive)
        NSLog("AINOCH TIMING keyDown act=%@ cost=%.4fms",
              "\(action)", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
        switch action {
        case .selectOption(let n):
            self.selectOption(n)
            return nil                       // consumir: la tecla no sigue
        case .highlightUp:
            self.model.keyboardSelection = KeyboardSpec.moveHighlightUp(self.model.keyboardSelection)
            return nil
        case .highlightDown:
            let n = self.model.current?.options.count ?? 1
            self.model.keyboardSelection = KeyboardSpec.moveHighlightDown(self.model.keyboardSelection, count: n)
            return nil
        case .highlightEnter:
            // KEYBOARD_SPEC v2: Enter en "Type something" ABRE el input (no
            // envía número). Se reusa onOptionTap con la opción resaltada.
            if let sel = self.model.keyboardSelection,
               let parsed = self.model.current,
               parsed.options.indices.contains(sel - 1) {
                let outcome = ContentState.onOptionTap(
                    optionIndex: sel,
                    optionTitle: parsed.options[sel - 1].title,
                    textInputActive: false)
                switch outcome {
                case .enterTextMode: self.openTextMode()
                case .selectOption(let n): self.selectOption(n)
                }
            }
            return nil
        case .prevQuestion:
            self.model.stackIndex = StackLogic.stackPrev(self.model.stackIndex)
            self.model.keyboardSelection = nil          // reset al cambiar pregunta
            return nil
        case .nextQuestion:
            self.model.stackIndex = StackLogic.stackNext(self.model.stackIndex, self.model.stackCount)
            self.model.keyboardSelection = nil          // reset al cambiar pregunta
            return nil
        case .collapse:
            // KEYBOARD_SPEC v2: ESC contextual — back (modo texto) o dismiss (inicio).
            if ContentState.onEscape(textInputActive: self.model.textInputActive) == .closeTextMode {
                self.model.textInputActive = false
                self.model.textInputValue = ""
            } else {
                self.dismiss()
            }
            return nil
        case .none:
            return event                     // dejar pasar
        }
    }

    // Mouse monitor GLOBAL: detecta si el cursor está sobre la isla (con la
    // ventana click-through, el onHover de SwiftUI NO llega). Usa el hit-test
    // puro isInsideIsland (test 8). Actualiza isHovering + ignoresMouseEvents.
    NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] _ in
        guard let self = self, let screen = NSScreen.main else { return }
        let p = NSEvent.mouseLocation               // coords AppKit bottom-left
        let hovering: Bool
        if self.model.isExpanded {
            // Expandido: rect con offset bajo el notch (requisito 7) — mismo
            // rect que la ventana => hit-test y display coherentes.
            let rect = IslandTransition.expandedIslandRect(
                screenW: screen.frame.width, screenH: screen.frame.height)
            hovering = IslandTransition.isInsideIsland(cursor: (p.x, p.y), islandRect: rect)
        } else {
            let rect = IslandTransition.compactIslandRect(
                screenW: screen.frame.width, screenH: screen.frame.height)
            hovering = IslandTransition.isInsideIsland(cursor: (p.x, p.y), islandRect: rect)
        }
        self.model.isHovering = hovering
        self.window?.ignoresMouseEvents = !hovering      // fuera → click-through
        if hovering && self.model.current != nil {
            self.model.isExpanded = true
        }
    }

    // Colapso: solo si el mouse de verdad dejó el rect de la isla.
    Timer.scheduledTimer(withTimeInterval: 0.45, repeats: true) { [weak self] _ in
        guard let self = self else { return }
        if self.model.isExpanded && !self.model.isHovering {
            self.model.isExpanded = false
        }
    }

    timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
        Task { await self?.poll() }
    }
    Task { await self.poll() }
}

    nonisolated private func fetchEvents() -> [NotchEvent]? {
        guard let data = try? Data(contentsOf: readerURL) else { return nil }
        let resp = try? JSONDecoder().decode(NotchResponse.self, from: data)
        return resp?.events
    }

    private func poll() async {
        let fetched = fetchEvents() ?? []
        await MainActor.run {
            // STACK_SPEC req 1: detectar pregunta NUEVA (dedupe por pane/agente)
            // y reproducir el ping (discreto, una vez). Carga inicial = silencio.
            var prevKeys = Set<String>()
            for ev in model.events { prevKeys.insert(ev.pane_id ?? ev.agent ?? "") }
            var newKeys = Set<String>()
            for ev in fetched { newKeys.insert(ev.pane_id ?? ev.agent ?? "") }
            let hadNew = StackLogic.hasNewQuestion(previous: prevKeys,
                                                   current: newKeys,
                                                   isInitialLoad: !model.canSignalNewQuestion)
            model.events = fetched
            model.canSignalNewQuestion = true

            // Ajustar stackIndex si quedó fuera de rango tras cambios en el stack.
            model.stackIndex = StackLogic.safeGuard(model.stackIndex, n: model.events.count)

            if hadNew && model.events.count > 0 {
                playFeedback(.newQuestion)
            }

            if model.current == nil {
                model.isExpanded = false
                window?.orderOut(nil)
            } else {
                window?.orderFrontRegardless()
            }
        }
    }

    // Acciones
    // KEYBOARD_SPEC v2: abre el input de texto (reusa el patrón del click).
    private func openTextMode() {
        let t0 = CFAbsoluteTimeGetCurrent()
        withAnimation(.easeInOut(duration: 0.22)) {
            model.textInputValue = ""
            model.textInputActive = true
        }
        window?.makeKey()                      // nonactivating → sin activate caro
        NSLog("AINOCH TIMING openTextMode=%.4fms",
              (CFAbsoluteTimeGetCurrent() - t0) * 1000)
        // El $textInputActive sink (observador) enfoca el campo.
    }

    // SOUND_SPEC v3+v5: solo TOCA el NSSound pre-construido. El haptic usa
    // performanceTime .default (SE agenda al próximo screen update, NO bloquea
    // el main thread como .now — medido 67ms → objetivo <5ms).
    private func playFeedback(_ event: FeedbackEvent) {
        let t0 = CFAbsoluteTimeGetCurrent()
        sounds[event]?.play()
        let pattern: NSHapticFeedbackManager.FeedbackPattern =
            (feedback.feedback(for: event)?.haptic ?? .generic) == .levelChange ? .levelChange : .generic
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
        NSLog("AINOCH TIMING play=%@ cost=%.4fms",
              "\(event)", (CFAbsoluteTimeGetCurrent() - t0) * 1000)
    }

    private func selectOption(_ n: Int) {
        guard let p = model.current else { return }
        runHerdr(["agent", "send-keys", p.pane, String(n), "enter"])
        playFeedback(.selectOption)
        NSLog("AINOCH: select=%d pane=%@", n, p.pane)
    }

    private func dismiss() {
        guard model.events.indices.contains(model.stackIndex) else { return }
        let pane = model.events[model.stackIndex].pane_id ?? ""
        // STACK_SPEC v2: el dismiss NO borra — MUEVE la pregunta al final del
        // stack (no se pierde; se vuelve a ella con →). El índice avanza.
        StackLogic.moveToEnd(&model.events, at: model.stackIndex)
        model.stackIndex = StackLogic.dismissIndexAfterMoveToEnd(model.stackIndex, count: model.events.count)
        model.keyboardSelection = nil
        playFeedback(.dismiss)
        NSLog("AINOCH: dismiss pane=%@ (restan %d)", pane, model.events.count)
    }

    // CONTENT_SPEC requisito 4: envía la respuesta libre al pane vía
    // `herdr agent prompt <pane> <text>` (llama a pi), luego descarta el evento.
    private func sendFreeText(_ text: String) {
        guard let p = model.current else { return }
        runHerdr(["agent", "prompt", p.pane, text])
        playFeedback(.submitText)
        NSLog("AINOCH: freeText pane=%@ len=%d", p.pane, text.count)
        model.events.remove(at: model.stackIndex)
        model.stackIndex = StackLogic.safeGuard(model.stackIndex, n: model.events.count)
        if model.current == nil { model.isExpanded = false }
    }

    private func focusPane() {
        guard let p = model.current else { return }
        runHerdr(["agent", "focus", p.pane])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            for app in NSWorkspace.shared.runningApplications
            where (app.localizedName?.lowercased().contains("ghostty") ?? false)
               || (app.localizedName?.lowercased().contains("herdr") ?? false) {
                app.activate(options: [.activateAllWindows])
                break
            }
        }
    }

    private func runHerdr(_ args: [String]) {
        let t = Process()
        t.executableURL = URL(fileURLWithPath: Self.herdrBin)
        t.arguments = args
        try? t.run()
    }
}
