// Renders scripts/icon.svg into the app's icon set (QuickNote/Assets.xcassets/AppIcon.appiconset).
//   swift scripts/make_icon.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let svg = root.appending(path: "scripts/icon.svg")
let iconSet = root.appending(path: "QuickNote/Assets.xcassets/AppIcon.appiconset")

guard let image = NSImage(contentsOf: svg) else {
    fatalError("Couldn't read \(svg.path)")
}

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(pixels: points * scale).write(to: iconSet.appending(path: name))
        entries.append(#"    { "idiom" : "mac", "scale" : "\#(scale)x", "size" : "\#(points)x\#(points)", "filename" : "\#(name)" }"#)
    }
}
let contents = "{\n  \"images\" : [\n" + entries.joined(separator: ",\n") + "\n  ],\n  \"info\" : {\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }\n}\n"
try contents.write(to: iconSet.appending(path: "Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(entries.count) icons to \(iconSet.path)")
