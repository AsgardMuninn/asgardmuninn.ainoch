# SNAPSHOT_SPEC v1 — tool de evidencia visual (`Tools/snapshot.swift`)

Propósito: cada cambio de UI de la isla debe poder demostrarse con una imagen
REAL del layout renderizado, sin abrir la app y sin tocar producción. Este tool
cierra ese loop: `ImageRenderer` offscreen sobre `NotchContentView`, mismo motor
de layout que la app (TextFit, NOTCH shape, OptionRowView).

## Contrato

Entrada: un `event.json` con el mismo formato que consume la app
(`{"events":[{agent,pane_id,status,question,context}]}`).

```
ainoch-snapshot --events <event.json> --out <dir> [--scale 1..4] [--no-expanded] [--highlight N]
```

Salidas (nombres deterministas, mismo orden siempre):

| estado | archivo |
|---|---|
| compacto (pills al lado del notch) | `compact@<N>x.png` |
| expandido | `expanded@<N>x.png` |
| expandido con highlight de teclado | `expanded-highlight<N>@<N>x.png` |

Reglas:

1. Render a 560x380 (el hosting real) sobre un fondo neutro: el recorte del
   notch se ve como en pantalla.
2. `--scale` por defecto 2 (retina). Rango válido 1...4; fuera de rango = error
   de CLI, nunca un default silencioso.
3. Salida determinista: mismo input + mismos flags → mismos bytes (hashes
   iguales entre corridas). Verificado con sha256.
4. Errores de CLI/JSON salen por stderr con exit != 0 (2 = uso/entrada,
   3 = render/escritura). Nunca escribe parcial y sigue.
5. `--highlight N` es 1-based (igual que `model.keyboardSelection`); `0` es error.
6. El parseo vive en `Sources/SnapshotPlan.swift` (puro, sin AppKit) y se testea
   con `Tests/test_snapshotplan_main.swift` — 18 asserts.

## Build

```bash
swiftc -O Sources/views.swift Sources/IslandGeometry.swift Sources/ContentState.swift \
  Sources/SoundSpec.swift Sources/StackLogic.swift Sources/TextFit.swift \
  Sources/KeyboardSpec.swift Sources/SnapshotPlan.swift Tools/snapshot.swift -o ainoch-snapshot
```

## Uso típico

```bash
./ainoch-snapshot --events Tools/demo_event.json \
  --out docs/pr-evidence/<cambio> --highlight 2
```

Adjuntar esos PNGs al PR (y al chat) es la evidencia estándar de cualquier
cambio visual de la isla.
