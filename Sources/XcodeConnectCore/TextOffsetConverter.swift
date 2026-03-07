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

    public static func twoOffsetsToLineChars(in text: String, first: Int, second: Int) -> (first: (Int, Int), second: (Int, Int)) {
        var r1 = (0, 0), r2 = (0, 0)
        guard second > 0 else { return (r1, r2) }

        var line = 0, charInLine = 0, currentOffset = 1
        var foundFirst = first <= 0

        for char in text {
            if !foundFirst && currentOffset >= first {
                r1 = (line, charInLine)
                foundFirst = true
            }
            if currentOffset >= second {
                r2 = (line, charInLine)
                return (r1, r2)
            }
            if char == "\n" { line += 1; charInLine = 0 } else { charInLine += 1 }
            currentOffset += 1
        }

        return (r1, r2)
    }
}
