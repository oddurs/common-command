import CoreGraphics

/// The panel's dimensions: a capsule search field and, under it, a card of results. Every size is a little
/// smaller than Spotlight's: one line of type and a short list, not a window.
public enum PanelSize: String, CaseIterable, Sendable, Identifiable {
    case small, medium, large

    public var id: String { rawValue }

    public var width: CGFloat {
        switch self {
        case .small: 480
        case .medium: 560
        case .large: 640
        }
    }

    public var fieldHeight: CGFloat {
        switch self {
        case .small: 44
        case .medium: 50
        case .large: 56
        }
    }

    public var fieldFontSize: CGFloat {
        switch self {
        case .small: 18
        case .medium: 20
        case .large: 22
        }
    }

    public var rowHeight: CGFloat {
        switch self {
        case .small: 30
        case .medium: 34
        case .large: 38
        }
    }

    public var rowFontSize: CGFloat {
        switch self {
        case .small: 13
        case .medium: 14
        case .large: 15
        }
    }

    public var headerHeight: CGFloat { rowHeight * 0.75 }
    public var headerFontSize: CGFloat { rowFontSize - 3 }
    public var iconSize: CGFloat { rowHeight - 10 }
    /// The field is a capsule, as on macOS 26.
    public var fieldRadius: CGFloat { fieldHeight / 2 }
    public var cardRadius: CGFloat { rowHeight * 0.6 }
    public var rowRadius: CGFloat { cardRadius - cardPadding }
    /// Space inside the card, so the selection's rounded corners sit inside the card's.
    public var cardPadding: CGFloat { 7 }
    /// Between the field and the card: two pieces of glass, not one box.
    public var gap: CGFloat { 8 }

    /// The card's height for `rows` results under `headers` section headers, scrolling past `visible` rows.
    public func cardHeight(rows: Int, headers: Int, visible: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        let content = CGFloat(rows) * rowHeight + CGFloat(headers) * headerHeight
        // Room for the visible rows and a couple of headers; past that the list scrolls.
        let cap = CGFloat(max(visible, 1)) * rowHeight + 2 * headerHeight
        return min(content, cap) + 2 * cardPadding
    }

    /// The whole panel: the field alone, or the field, the gap, and the card.
    public func height(rows: Int, headers: Int, visible: Int) -> CGFloat {
        guard rows > 0 else { return fieldHeight }
        return fieldHeight + gap + cardHeight(rows: rows, headers: headers, visible: visible)
    }
}
