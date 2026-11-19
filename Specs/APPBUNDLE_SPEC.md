# APPBUNDLE_SPEC v1 — Ainoch.app como bundle verificable

Contrato del empaquetado `.app`. El binario suelto (`~/ai-notch/ainoch`) sigue siendo
el artefacto de producción; el bundle es **aditivo** y se valida en una copia scratch.

## Estructura obligatoria

```
Ainoch.app/
  Contents/
    Info.plist
    MacOS/ainoch            # ejecutable, chmod +x
    Resources/AppIcon.icns  # ICNS legible con >= 6 representaciones
```

## Info.plist — claves exigidas

| clave | valor |
|---|---|
| CFBundleIdentifier | `com.ainoch.notch` |
| CFBundleExecutable | `ainoch` |
| CFBundleName | `Ainoch` |
| CFBundlePackageType | `APPL` |
| CFBundleIconFile | `AppIcon` |
| CFBundleShortVersionString | `1.0.0` |
| CFBundleVersion | `1` |
| LSUIElement | `true` (sin ícono en Dock, es una notch app) |
| NSHighResolutionCapable | `true` |
| LSMinimumSystemVersion | `13.0` |

`plutil -lint` debe pasar. Sin claves de hardware, rutas del usuario ni datos internos.

## Ícono

`Resources/AppIcon.icns` se genera **desde código**, sin assets externos:

1. `Tools/make_icon.swift` dibuja un PNG 1024x1024 con CoreGraphics (determinista:
   dos corridas producen el mismo sha256).
2. `sips -z` deriva los 10 tamaños del `.iconset`.
3. `iconutil -c icns` produce el `.icns`.

`iconutil -c iconset` (round-trip) debe recuperar los 10 archivos.

## Firma

`codesign --force --deep --sign -` (ad-hoc). `codesign --verify --strict` debe pasar;
no se requiere Developer ID ni notarización para uso local.

## Verificador

`Tools/verify_app_bundle.sh <ruta/Ainoch.app>` sale 0 solo si:

- estructura completa y ejecutable con bit `x`;
- `plutil -lint` OK y las 10 claves con los valores de la tabla;
- `.icns` legible (`sips -g pixelWidth`) y round-trip de `iconutil` con 10 entradas;
- `codesign --verify --strict` OK.

Salida no-cero = bundle inválido. El verificador es el test del nodo: se corre
**antes** del build (rojo: bundle ausente) y **después** (verde).
