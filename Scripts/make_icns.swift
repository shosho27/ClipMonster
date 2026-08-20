import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: make_icns.swift <iconset-directory> <output.icns>\n", stderr)
    exit(2)
}

let iconsetURL = URL(fileURLWithPath: arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: arguments[2])
let entries: [(type: String, file: String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_64x64.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_1024x1024.png")
]

func bigEndianData(_ value: UInt32) -> Data {
    var bigEndian = value.bigEndian
    return withUnsafeBytes(of: &bigEndian) { Data($0) }
}

do {
    var chunks = Data()
    for entry in entries {
        let png = try Data(contentsOf: iconsetURL.appendingPathComponent(entry.file))
        chunks.append(contentsOf: entry.type.utf8)
        chunks.append(bigEndianData(UInt32(png.count + 8)))
        chunks.append(png)
    }

    var icon = Data("icns".utf8)
    icon.append(bigEndianData(UInt32(chunks.count + 8)))
    icon.append(chunks)
    try icon.write(to: outputURL, options: .atomic)
} catch {
    fputs("Could not create ICNS: \(error.localizedDescription)\n", stderr)
    exit(1)
}
