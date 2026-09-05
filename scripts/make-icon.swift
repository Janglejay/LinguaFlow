import AppKit

guard (2...3).contains(CommandLine.arguments.count) else {
    fputs("usage: make-icon.swift <output.tiff> [glyph]\n", stderr)
    exit(2)
}

let glyph = CommandLine.arguments.count == 3 ? CommandLine.arguments[2] : "译"
let size = NSSize(width: 16, height: 16)
let image = NSImage(size: size)
image.lockFocus()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: glyph.count > 1 ? 7 : 10, weight: .semibold),
    .foregroundColor: NSColor.black,
    .paragraphStyle: paragraph,
]
(glyph as NSString).draw(
    in: NSRect(x: 2, y: 2, width: 12, height: 12),
    withAttributes: attributes
)

image.unlockFocus()

guard let data = image.tiffRepresentation else {
    fputs("unable to render icon\n", stderr)
    exit(1)
}
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
