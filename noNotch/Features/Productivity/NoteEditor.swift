import AppKit
import SwiftUI

/// Plain-text editor for the notch. ⌘↩ hands the current line to `onCommandReturn`;
/// lines starting with "✓ " (already turned into tasks) are drawn struck through.
struct NoteEditor: NSViewRepresentable {
    @Binding var text: String
    var onCommandReturn: (String) -> Bool = { _ in false }

    static let taskMarker = "✓ "

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CommandReturnTextView()
        textView.delegate = context.coordinator
        textView.onCommandReturn = { [weak coordinator = context.coordinator] in coordinator?.commandReturn() ?? false }
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 12.5)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.string = text
        context.coordinator.restyle(textView)

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.documentView = textView
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = scroll.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        context.coordinator.restyle(textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NoteEditor
        weak var textView: NSTextView?

        init(_ parent: NoteEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            self.textView = textView
            parent.text = textView.string
            restyle(textView)
        }

        func textDidBeginEditing(_ notification: Notification) {
            textView = notification.object as? NSTextView
        }

        /// Turns the current line into a task and marks it done-in-notes.
        func commandReturn() -> Bool {
            guard let textView else { return false }
            let ns = textView.string as NSString
            let lineRange = ns.lineRange(for: NSRange(location: textView.selectedRange().location, length: 0))
            let raw = ns.substring(with: lineRange)
            let line = raw.trimmingCharacters(in: .newlines)
            let content = line.trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty, !content.hasPrefix(NoteEditor.taskMarker), parent.onCommandReturn(content) else { return false }
            let replacement = NoteEditor.taskMarker + content + (raw.hasSuffix("\n") ? "\n" : "")
            if textView.shouldChangeText(in: lineRange, replacementString: replacement) {
                textView.replaceCharacters(in: lineRange, with: replacement)
                textView.didChangeText()
            }
            return true
        }

        func restyle(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let ns = storage.string as NSString
            let full = NSRange(location: 0, length: ns.length)
            storage.beginEditing()
            storage.setAttributes([.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: NSColor.white], range: full)
            ns.enumerateSubstrings(in: full, options: .byLines) { line, range, _, _ in
                guard line?.hasPrefix(NoteEditor.taskMarker) == true else { return }
                storage.addAttributes([
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .foregroundColor: NSColor.white.withAlphaComponent(0.45),
                ], range: range)
            }
            storage.endEditing()
        }
    }
}

private final class CommandReturnTextView: NSTextView {
    var onCommandReturn: () -> Bool = { false }

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 || event.keyCode == 76
        if isReturn, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, onCommandReturn() {
            return
        }
        super.keyDown(with: event)
    }
}
