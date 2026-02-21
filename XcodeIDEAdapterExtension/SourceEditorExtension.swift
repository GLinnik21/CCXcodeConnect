import AppKit
import XcodeKit

class SourceEditorExtension: NSObject, XCSourceEditorExtension {
    func extensionDidFinishLaunching() {
        if let url = URL(string: "xcode-ide-adapter://activate") {
            NSWorkspace.shared.open(url)
        }
    }
}
