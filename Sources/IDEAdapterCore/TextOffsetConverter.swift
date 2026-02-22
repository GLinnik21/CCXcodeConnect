import Foundation

public enum TextOffsetConverter {
    public static func offsetToLineChar(in text: String, offset: Int) -> (line: Int, character: Int) {
        guard offset > 0 else { return (0, 0) }

        var line = 0
        var charInLine = 0
        var currentOffset = 1

        for char in text {
            if currentOffset >= offset { break }
            if char == "\n" {
                line += 1
                charInLine = 0
            } else {
                charInLine += 1
            }
            currentOffset += 1
        }

        return (line, charInLine)
    }
}
