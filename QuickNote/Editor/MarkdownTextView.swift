import AppKit

/// A plain-text view that shows its Markdown styled as you type. The text itself never changes:
/// once a style is complete its marks collapse to nothing, and bullets and to-do boxes are drawn
/// over theirs. The caret steps over hidden marks as if they weren't there.
final class MarkdownTextView: NSTextView {
    private(set) var lines: [MarkdownLine] = []
    private(set) var spans: [InlineSpan] = []
    private var baseFontSize: CGFloat = 16
    /// Every mark currently hidden, which the caret is kept out of. Emptied while an edit is in
    /// flight, when these ranges are stale.
    private var hiddenMarks: [NSRange] = []

    private static let lineSpacing: CGFloat = 3

    /// A text view in a scroll view, set up for plain-text Markdown.
    static func makeScrollable(fontSize: CGFloat) -> (NSScrollView, MarkdownTextView) {
        let storage = NSTextStorage()
        let layout = MarkdownLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let textView = MarkdownTextView(frame: .zero, textContainer: container)
        textView.baseFontSize = fontSize
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 0, height: 2)
        // These would rewrite the marks themselves (-- into a dash, quotes, …).
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.typingAttributes = textView.baseAttributes

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        return (scrollView, textView)
    }

    // MARK: Styling

    private var baseFont: NSFont { .systemFont(ofSize: baseFontSize) }

    private var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = Self.lineSpacing
        return [.font: baseFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
    }

    private static let hidden: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 0.01),
        .foregroundColor: NSColor.clear,
    ]

    /// Re-reads the Markdown and styles all of it. Call after every change to the text.
    func restyle() {
        guard let storage = textStorage else { return }
        lines = MarkdownParser.lines(in: string)
        spans = MarkdownParser.spans(in: string, lines: lines)
        var decorations: [MarkdownLayoutManager.Decoration] = []
        var hidden: [NSRange] = []

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: NSRange(location: 0, length: storage.length))

        for line in lines {
            switch line.kind {
            case .title:
                storage.addAttribute(.font, value: NSFont.systemFont(ofSize: round(baseFontSize * 1.35), weight: .bold), range: line.range)
            case .todo(done: true):
                storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: NSColor.secondaryLabelColor], range: line.contentRange)
            default:
                break
            }
            guard line.markRange.length > 0 else { continue }
            hidden.append(line.markRange)
            switch line.kind {
            case .title:
                storage.addAttributes(Self.hidden, range: line.markRange)
            case .bullet:
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: line.markRange)
                decorations.append(.init(range: line.markRange, kind: .bullet))
            case .todo(let done):
                storage.addAttribute(.foregroundColor, value: NSColor.clear, range: line.markRange)
                decorations.append(.init(range: line.markRange, kind: .box(done: done)))
            case .text:
                break
            }
        }

        for span in spans {
            switch span.style {
            case .bold: addTrait(.boldFontMask, in: span.contentRange, of: storage)
            case .italic: addTrait(.italicFontMask, in: span.contentRange, of: storage)
            case .strike: storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: span.contentRange)
            case .highlight: storage.addAttribute(.backgroundColor, value: NSColor.systemYellow.withAlphaComponent(0.45), range: span.contentRange)
            }
            for mark in [span.openMark, span.closeMark] {
                storage.addAttributes(Self.hidden, range: mark)
                hidden.append(mark)
            }
        }
        storage.endEditing()

        (layoutManager as? MarkdownLayoutManager)?.decorations = decorations
        hiddenMarks = hidden
        typingAttributes = baseAttributes
        needsDisplay = true
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        hiddenMarks = []
        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    // Every edit (typing, paste, undo, the formatting commands) re-reads the Markdown, so commands
    // that follow each other always see current ranges.
    override func didChangeText() {
        restyle()
        super.didChangeText()
    }

    /// Keeps the caret out of hidden marks: one that lands inside a mark moves past it, in the
    /// direction it was going, so arrow keys step over marks in a single press.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        var ranges = ranges
        if ranges.count == 1, let caret = ranges.first?.rangeValue, caret.length == 0,
           let mark = hiddenMarks.first(where: { caret.location > $0.location && caret.location < NSMaxRange($0) }) {
            let movingForward = caret.location >= selectedRange().location
            ranges = [NSValue(range: NSRange(location: movingForward ? NSMaxRange(mark) : mark.location, length: 0))]
        }
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
    }

    /// Backspace right after a bullet, to-do or title mark turns the line back into plain text.
    override func deleteBackward(_ sender: Any?) {
        let caret = selectedRange()
        if caret.length == 0,
           let line = lines.first(where: { $0.markRange.length > 0 && NSMaxRange($0.markRange) == caret.location }) {
            replace(line.markRange, with: "")
            return
        }
        super.deleteBackward(sender)
    }

    private func addTrait(_ trait: NSFontTraitMask, in range: NSRange, of storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let font = value as? NSFont else { return }
            storage.addAttribute(.font, value: NSFontManager.shared.convert(font, toHaveTrait: trait), range: run)
        }
    }

    // The toolbar only shows while the editor has focus: tell it when that changes.
    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { focusChanged() }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { focusChanged() }
        return resigned
    }

    private func focusChanged() {
        delegate?.textViewDidChangeSelection?(Notification(name: NSTextView.didChangeSelectionNotification, object: self))
    }

    // MARK: Formatting commands

    /// Whether the selection is inside text with this style.
    func isActive(_ style: InlineStyle) -> Bool {
        let selection = selectedRange()
        return spans.contains { $0.style == style && contains($0.range, selection) }
    }

    /// The kind of the line the selection starts on.
    var currentLineKind: LineKind {
        let location = selectedRange().location
        return lines.last { $0.range.location <= location }?.kind ?? .text
    }

    /// Wraps the selection in the style's marks, or removes them if it already has the style.
    func toggle(_ style: InlineStyle) {
        let selection = selectedRange()
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        if let span = spans.last(where: { $0.style == style && contains($0.range, selection) }) {
            replace(span.closeMark, with: "")
            replace(span.openMark, with: "")
            setSelectedRange(NSRange(location: span.openMark.location, length: span.contentRange.length))
            return
        }
        let target = trimmed(selection)
        let mark = style.mark
        let markLength = (mark as NSString).length
        replace(NSRange(location: NSMaxRange(target), length: 0), with: mark)
        replace(NSRange(location: target.location, length: 0), with: mark)
        setSelectedRange(NSRange(location: target.location + markLength, length: target.length))
    }

    /// Makes every selected line this kind, or plain text again if they all already are.
    func toggleLineKind(_ kind: LineKind) {
        let selection = (string as NSString).lineRange(for: selectedRange())
        let affected = lines.filter { NSLocationInRange($0.range.location, selection) || $0.range.location == selection.location }
        guard !affected.isEmpty else { return }
        let removing = affected.allSatisfy { $0.kind.isSameKind(as: kind) }
        undoManager?.beginUndoGrouping()
        defer { undoManager?.endUndoGrouping() }
        for line in affected.reversed() {
            replace(line.markRange, with: removing ? "" : kind.prefix)
        }
    }

    /// Ticks or unticks the to-do on this line.
    private func toggleTodo(_ line: MarkdownLine) {
        guard case .todo(let done) = line.kind else { return }
        let mark = (string as NSString).substring(with: line.markRange) as NSString
        let box = mark.range(of: done ? "x" : " ", options: done ? [.caseInsensitive] : [], range: NSRange(location: mark.range(of: "[").location, length: 2))
        guard box.location != NSNotFound else { return }
        replace(NSRange(location: line.markRange.location + box.location, length: 1), with: done ? " " : "x")
    }

    private func replace(_ range: NSRange, with text: String) {
        guard shouldChangeText(in: range, replacementString: text) else { return }
        textStorage?.replaceCharacters(in: range, with: text)
        didChangeText()
    }

    private func trimmed(_ range: NSRange) -> NSRange {
        let string = self.string as NSString
        var start = range.location, end = NSMaxRange(range)
        let space = CharacterSet.whitespacesAndNewlines
        while start < end, let scalar = UnicodeScalar(string.character(at: start)), space.contains(scalar) { start += 1 }
        while end > start, let scalar = UnicodeScalar(string.character(at: end - 1)), space.contains(scalar) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    private func contains(_ outer: NSRange, _ inner: NSRange) -> Bool {
        inner.location >= outer.location && NSMaxRange(inner) <= NSMaxRange(outer)
    }

    // MARK: Keyboard and mouse

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        switch (flags, key) {
        case ([.command], "b"): toggle(.bold)
        case ([.command], "i"): toggle(.italic)
        case ([.command, .shift], "x"): toggle(.strike)
        case ([.command, .shift], "h"): toggle(.highlight)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    // MARK: Attachments

    /// Offered every paste and drop first; returns true if it attached what's on the pasteboard.
    /// Otherwise the text view handles it as usual (a plain text view would insert a file's path).
    var onAttach: ((NSPasteboard) -> Bool)?

    private static let attachmentTypes: [NSPasteboard.PasteboardType] = [.fileURL, .png, .tiff]

    override func paste(_ sender: Any?) {
        if onAttach?(.general) == true { return }
        super.paste(sender)
    }

    override var acceptableDragTypes: [NSPasteboard.PasteboardType] {
        super.acceptableDragTypes + Self.attachmentTypes
    }

    override func dragOperation(for dragInfo: any NSDraggingInfo, type: NSPasteboard.PasteboardType) -> NSDragOperation {
        onAttach != nil && Self.attachmentTypes.contains(type) ? .copy : super.dragOperation(for: dragInfo, type: type)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        if onAttach?(sender.draggingPasteboard) == true { return true }
        return super.performDragOperation(sender)
    }

    /// A click on a drawn to-do box ticks it, without moving the caret.
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let line = todoBox(at: point) {
            toggleTodo(line)
            return
        }
        super.mouseDown(with: event)
    }

    private func todoBox(at point: NSPoint) -> MarkdownLine? {
        guard let layout = layoutManager as? MarkdownLayoutManager, let container = textContainer else { return nil }
        for decoration in layout.decorations {
            guard case .box = decoration.kind else { continue }
            let glyphs = layout.glyphRange(forCharacterRange: decoration.range, actualCharacterRange: nil)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
            if rect.contains(point) {
                return lines.first { $0.markRange == decoration.range }
            }
        }
        return nil
    }
}

/// Draws a bullet over each hidden `- ` and a checkbox over each hidden `[ ]`.
final class MarkdownLayoutManager: NSLayoutManager {
    struct Decoration {
        enum Kind { case bullet, box(done: Bool) }
        var range: NSRange
        var kind: Kind
    }

    var decorations: [Decoration] = []

    override func drawGlyphs(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawGlyphs(forGlyphRange: glyphsToShow, at: origin)
        guard let container = textContainers.first else { return }
        for decoration in decorations {
            let glyphs = glyphRange(forCharacterRange: decoration.range, actualCharacterRange: nil)
            guard NSIntersectionRange(glyphs, glyphsToShow).length > 0, glyphs.length > 0 else { continue }
            let marks = boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: origin.x, dy: origin.y)
            let line = lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil).offsetBy(dx: origin.x, dy: origin.y)
            let font = (textStorage?.attribute(.font, at: decoration.range.location, effectiveRange: nil) as? NSFont) ?? .systemFont(ofSize: 16)
            // Centre on the text's x-height band rather than the whole line, which includes the spacing below.
            let midY = line.minY + (font.ascender - font.descender) / 2 + 1
            switch decoration.kind {
            case .bullet:
                let size = round(font.pointSize * 0.34)
                NSColor.labelColor.setFill()
                NSBezierPath(ovalIn: NSRect(x: marks.minX + 2, y: midY - size / 2, width: size, height: size)).fill()
            case .box(let done):
                let size = round(font.pointSize * 0.88)
                let box = NSRect(x: marks.minX + 1, y: midY - size / 2, width: size, height: size)
                let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.75, dy: 0.75), xRadius: 4, yRadius: 4)
                if done {
                    NSColor.controlAccentColor.setFill()
                    path.fill()
                    let tick = NSBezierPath()
                    tick.move(to: NSPoint(x: box.minX + size * 0.26, y: box.midY))
                    tick.line(to: NSPoint(x: box.minX + size * 0.44, y: box.minY + size * 0.7))
                    tick.line(to: NSPoint(x: box.minX + size * 0.76, y: box.minY + size * 0.3))
                    tick.lineWidth = 1.8
                    tick.lineCapStyle = .round
                    tick.lineJoinStyle = .round
                    NSColor.white.setStroke()
                    tick.stroke()
                } else {
                    NSColor.secondaryLabelColor.setStroke()
                    path.lineWidth = 1.5
                    path.stroke()
                }
            }
        }
    }
}
