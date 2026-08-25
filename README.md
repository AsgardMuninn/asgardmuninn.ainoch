# AI Notch — Dynamic Island for herdr harnesses

A macOS notch app (Dynamic Island pattern) that surfaces blocked questions from
local AI coding harnesses (**herdr**) directly under the display notch. Built
with SwiftUI + a pure-geometry transition layer, fully TDD'd.

Renders an interactive "island" at the top of the screen (like the iPhone
Dynamic Island or Raycast/Arc UI polish): a compact pill that expands on hover,
shows the active harness question + answer options, supports keyboard
navigation, text input, sound + haptic feedback, and a stack of multiple
simultaneous questions.

## Features

- **Dynamic Island pattern** — NSPanel + SwiftUI that expands from the notch
  (top-anchored), never stealing focus from your active app (nonactivating panel).
- **Discrete sound + haptics** (Raycast/Arc style) — WAV synthesized in code
  (no assets), pre-warmed at launch so playback never blocks the UI.
- **Keyboard-first UX** — `↑↓` highlight options, `1-9` select, `←→` navigate
  the question stack, `Enter` confirm (opens text input for "Type something"),
  `Esc` back/dismiss contextually.
- **Stack of questions** — multiple harnesses blocked at once: header shows
  "n of N" with navigation; dismiss moves a question to the end (never loses it).
- **Free text input** — full input with real focus (Cmd+A select all works),
  isolates its own render so typing never re-renders the whole island.
- **Click-through when collapsed** — the window never blocks your desktop.

## Requirements

- macOS 13+ with a notched display
- [herdr](https://github.com/AsgardMuninn/herdr) available in PATH (or set
  `HERDR_BIN` to the binary path)
- A local event reader serving `json` at `http://127.0.0.1:8900/event.json`
  (override with `AINOCH_READER_URL`)

## Build

```bash
swiftc -O Sources/main.swift Sources/views.swift Sources/IslandGeometry.swift \
  Sources/ContentState.swift Sources/SoundSpec.swift Sources/StackLogic.swift \
  Sources/KeyboardSpec.swift -o ainoch
```

Optionally run as a LaunchAgent (see `com.ainoch.notch.plist`).

## Run with a demo reader

```bash
python3 Scripts/demo_reader2.py 8900   # serves 2 fake questions
./ainoch
```

## Event reader contract

The app polls `event.json` expecting:

```json
{ "events": [ { "agent": "pi", "pane_id": "pane:id", "status": "blocked",
  "question": "…❯ 1. Option one\n  2. Option two\n  3. Type something.",
  "context": { "cwd": "…", "terminal_title": "…" } } ] }
```

## Tests

Pure TDD suites (no AppKit) — run with `swiftc <Module>.swift Tests/main.swift`:

| Suite | File | Checks |
|---|---|---|
| island-transition | `Tests/test_island_main.swift` + `IslandGeometry.swift` | geometry, hit-test |
| content-state | `Tests/test_content_main.swift` + `ContentState.swift` | free-text transitions, ESC |
| sound-spec | `Tests/test_sound_main.swift` + `SoundSpec.swift` | WAV gen, feedback cache |
| stack-logic | `Tests/test_stack_main.swift` + `StackLogic.swift` | multi-question stack |
| keyboard-spec | `Tests/test_keyboard_main.swift` + `KeyboardSpec.swift` | key resolution |

Each suite is self-contained; build each with its `Tests/main.swift` renamed to
`main.swift` (Swift requires top-level code in a file named `main.swift`).

## Design

- `TRANSITION_SPEC.md` — the island transition (single view animates its frame
  top-anchored from the notch; no matchedGeometryEffect).
- `SOUND_SPEC.md` — sounds synthsized in code, discrete events only, pre-warmed.
- `STACK_SPEC.md` — multi-question UX (n of N, dismiss moves to end).
- `KEYBOARD_SPEC.md` — keyboard navigation + ESC back/dismiss.
- `CONTENT_SPEC.md` — free-text mode lifecycle.

## License

MIT
