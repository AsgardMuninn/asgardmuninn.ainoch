// make_icon.swift — dibuja el ícono de Ainoch con CoreGraphics. Sin assets externos.
// Uso: swiftc -O Tools/make_icon.swift -o /tmp/make_icon && /tmp/make_icon out.png [size]
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func drawIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
        CGColor(colorSpace: cs, components: [r, g, b, 1])!
    }

    // Fondo: squircle oscuro con leve gradiente vertical.
    let inset = s * 0.04
    let bgRect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: s * 0.22, cornerHeight: s * 0.22,
                        transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()
    let grad = CGGradient(colorsSpace: cs,
                          colors: [rgb(0.09, 0.11, 0.16), rgb(0.04, 0.05, 0.08)] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // Notch: píldora negra pegada al borde superior.
    let notchW = s * 0.56, notchH = s * 0.13
    let notchRect = CGRect(x: (s - notchW) / 2, y: s - inset - notchH * 0.55,
                           width: notchW, height: notchH)
    let notchPath = CGPath(roundedRect: notchRect, cornerWidth: notchH / 2,
                           cornerHeight: notchH / 2, transform: nil)
    ctx.addPath(notchPath)
    ctx.setFillColor(rgb(0, 0, 0))
    ctx.fillPath()

    // Cámara: punto frío dentro del notch.
    let dotD = notchH * 0.34
    ctx.setFillColor(rgb(0.16, 0.35, 0.55))
    ctx.fillEllipse(in: CGRect(x: s / 2 - dotD / 2, y: notchRect.midY - dotD / 2,
                               width: dotD, height: dotD))

    // Tres barras de "pregunta" decrecientes: la superior en acento cian.
    let barH = s * 0.062
    let barX = s * 0.22
    let widths: [CGFloat] = [0.56, 0.44, 0.30]
    let colors = [rgb(0.35, 0.85, 0.95), rgb(0.86, 0.89, 0.95), rgb(0.55, 0.59, 0.68)]
    var y = s * 0.60
    for (i, wf) in widths.enumerated() {
        let r = CGRect(x: barX, y: y, width: s * wf, height: barH)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: barH / 2, cornerHeight: barH / 2,
                           transform: nil))
        ctx.setFillColor(colors[i])
        ctx.fillPath()
        y -= barH * 1.85
    }
    return ctx.makeImage()
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write(Data("uso: make_icon <out.png> [size]\n".utf8))
    exit(64)
}
let outPath = args[1]
let size = args.count >= 3 ? (Int(args[2]) ?? 1024) : 1024
guard size >= 16, size <= 4096 else {
    FileHandle.standardError.write(Data("size fuera de rango 16...4096\n".utf8))
    exit(64)
}
guard let img = drawIcon(size: size) else {
    FileHandle.standardError.write(Data("no se pudo dibujar el ícono\n".utf8))
    exit(70)
}
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString,
                                                1, nil) else {
    FileHandle.standardError.write(Data("no se pudo crear \(outPath)\n".utf8))
    exit(73)
}
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else {
    FileHandle.standardError.write(Data("falló la escritura PNG\n".utf8))
    exit(74)
}
print("ok \(outPath) \(size)x\(size)")
