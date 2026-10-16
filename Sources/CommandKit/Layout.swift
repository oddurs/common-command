import CoreGraphics

/// The panel's dimensions. Every size is a little smaller than Spotlight's: one line of type and a short
/// list, not a window.
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
        case .small: 42
        case .medium: 48
        case .large: 54
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

    public var iconSize: CGFloat { rowHeight - 12 }
    public var cornerRadius: CGFloat { fieldHeight / 2.6 }
    /// Space around the list, so the selection's rounded corners don't touch the panel's edge.
    public var listPadding: CGFloat { 6 }

    /// The panel's height with `rows` results, of which at most `visible` show before the list scrolls.
    public func height(rows: Int, visible: Int) -> CGFloat {
        guard rows > 0 else { return fieldHeight }
        return fieldHeight + 1 + CGFloat(min(rows, max(visible, 1))) * rowHeight + 2 * listPadding
    }
}
