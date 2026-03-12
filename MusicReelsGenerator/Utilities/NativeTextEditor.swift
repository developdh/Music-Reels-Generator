import SwiftUI
import AppKit

/// NSTextView subclass that directly handles Cmd+V/C/X/A key equivalents,
/// bypassing SwiftUI's broken Edit menu routing.
private class EditableTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command),
              let chars = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }

        switch chars {
        case "v": paste(nil);     return true
        case "c": copy(nil);      return true
        case "x": cut(nil);       return true
        case "a": selectAll(nil); return true
        case "z":
            if event.modifierFlags.contains(.shift) {
                undoManager?.redo()
            } else {
                undoManager?.undo()
            }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

/// NSTextView wrapper that properly supports Cmd+V paste and other standard keyboard shortcuts.
struct NativeTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont = .monospacedSystemFont(ofSize: 13, weight: .regular)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = EditableTextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.string = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}
