import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: make-icon.swift <output.tiff>\n", stderr)
    exit(2)
}

let size = NSSize(width: 128, height: 128)
let image = NSImage(size: size)
image.lockFocus()

let background = NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 28, yRadius: 28)
NSColor(calibratedRed: 0.16, green: 0.42, blue: 0.92, alpha: 1).setFill()
background.fill()

let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attributes: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 68, weight: .semibold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
]
("译" as NSString).draw(
    in: NSRect(x: 0, y: 21, width: size.width, height: 86),
    withAttributes: attributes
)

image.unlockFocus()

guard let data = image.tiffRepresentation else {
    fputs("unable to render icon\n", stderr)
    exit(1)
}
try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
