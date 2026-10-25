import AppKit
import SwiftUI

/// A read-only text view that appends only the new lines of a log (a game can print thousands),
/// and follows the end unless scrolled up.
struct LogTextView: NSViewRepresentable {
    let jobID: UUID
    let log: LogBuffer

    final class Coordinator {
        var jobID: UUID?
        var shown = 0
        var dropped = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = true
            text.isRichText = false
            text.font = LogStyle.font
            text.textContainerInset = NSSize(width: 8, height: 6)
            text.backgroundColor = .textBackgroundColor
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView, let storage = text.textStorage else {
            return
        }
        let state = context.coordinator
        let reload =
            state.jobID != jobID
            || state.shown < log.dropped
            || state.shown > log.total
            || log.dropped - state.dropped > log.limit / 4  // lines dropped from the buffer: drop them here too
        if reload {
            storage.setAttributedString(NSAttributedString())
            state.jobID = jobID
            state.dropped = log.dropped
            state.shown = log.dropped
        }
        let start = state.shown - log.dropped
        guard start < log.lines.count else { return }

        let follow = reload || isAtEnd(scroll)
        let chunk = NSMutableAttributedString()
        for line in log.lines[start...] {
            let separator = storage.length + chunk.length == 0 ? "" : "\n"
            chunk.append(
                NSAttributedString(
                    string: separator + line, attributes: LogStyle.attributes(for: line)))
        }
        storage.beginEditing()
        storage.append(chunk)
        storage.endEditing()
        state.shown = log.total
        if follow { text.scrollToEndOfDocument(nil) }
    }

    private func isAtEnd(_ scroll: NSScrollView) -> Bool {
        guard let document = scroll.documentView else { return true }
        return scroll.contentView.bounds.maxY >= document.frame.height - 30
    }
}

@MainActor
enum LogStyle {
    static let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    /// build_ipa_from_nsp.py marks problems with [RED] and stage ends with ✓ / ✗.
    static func attributes(for line: String) -> [NSAttributedString.Key: Any] {
        let color: NSColor =
            if line.contains("[RED]") || line.contains("✗") || line.hasPrefix("nxplay: failed")
                || line.hasPrefix("Traceback")
            {
                .systemRed
            } else if line.contains("✓") || line.hasPrefix("nxplay: done") {
                .systemGreen
            } else if line.hasPrefix("$ ") || line.hasPrefix("nxplay:") {
                .secondaryLabelColor
            } else {
                .labelColor
            }
        return [.font: font, .foregroundColor: color]
    }
}
