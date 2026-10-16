import AppKit
import CommandKit
import SwiftUI

/// The search field and the results under it.
struct PanelView: View {
    @Bindable var model: SearchModel
    let preferences: Preferences
    let commands: SearchField.Commands
    let choose: (Int) -> Void

    private var size: PanelSize { preferences.size }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: size.fieldFontSize * 0.8, weight: .medium))
                    .foregroundStyle(.secondary)
                SearchField(model: model, fontSize: size.fieldFontSize, commands: commands)
            }
            .padding(.horizontal, 16)
            .frame(height: size.fieldHeight)

            if !model.results.isEmpty {
                Divider().opacity(0.6)
                ResultList(model: model, size: size, visibleRows: preferences.visibleRows, choose: choose)
            }
        }
        .frame(width: size.width, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background {
            if !preferences.translucent {
                RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor))
            }
        }
        .overlay {
            // A hairline edge, as on menus and popovers, so the panel holds its shape over any background.
            RoundedRectangle(cornerRadius: size.cornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
        }
    }
}

private struct ResultList: View {
    let model: SearchModel
    let size: PanelSize
    let visibleRows: Int
    let choose: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(model.results.enumerated()), id: \.element.id) { index, ranked in
                        ResultRow(
                            ranked: ranked, size: size, isSelected: index == model.selection,
                            shortcut: model.showsShortcuts && index < 9 ? "⌘\(index + 1)" : nil
                        )
                        .id(index)
                        .onTapGesture { choose(index) }
                    }
                }
                .padding(size.listPadding)
            }
            .scrollIndicators(.automatic)
            .scrollDisabled(model.results.count <= visibleRows)
            .frame(height: CGFloat(min(model.results.count, visibleRows)) * size.rowHeight + 2 * size.listPadding)
            .onChange(of: model.selection) { _, selection in proxy.scrollTo(selection) }
        }
    }
}

private struct ResultRow: View {
    let ranked: Ranked
    let size: PanelSize
    let isSelected: Bool
    let shortcut: String?

    var body: some View {
        HStack(spacing: 10) {
            ItemIcon(item: ranked.item, size: size.iconSize, isSelected: isSelected)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 16)
            Text(shortcut ?? ranked.item.subtitle)
                .font(.system(size: size.rowFontSize - 1))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.head)
                .layoutPriority(-1)
        }
        .font(.system(size: size.rowFontSize))
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .frame(height: size.rowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: size.cornerRadius - size.listPadding, style: .continuous)
                    .fill(Color.accentColor)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// The characters the query matched, a step bolder than the rest.
    private var title: AttributedString {
        var text = AttributedString(ranked.item.title)
        guard !ranked.highlights.isEmpty else { return text }
        let marked = Set(ranked.highlights)
        var index = text.startIndex
        var offset = 0
        while index < text.endIndex {
            let next = text.characters.index(after: index)
            if marked.contains(offset) { text[index..<next].font = .system(size: size.rowFontSize, weight: .semibold) }
            index = next
            offset += 1
        }
        return text
    }
}

private struct ItemIcon: View {
    let item: Item
    let size: CGFloat
    let isSelected: Bool

    var body: some View {
        Group {
            if let image = Icons.shared.image(for: item) {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: Icons.symbol(for: item.kind))
                    .font(.system(size: size * 0.62, weight: .medium))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Icons from the file system, cached: each one costs a trip to Launch Services the first time.
@MainActor
final class Icons {
    static let shared = Icons()
    private var cache: [String: NSImage] = [:]
    private lazy var settingsIcon = NSWorkspace.shared.icon(forFile: "/System/Applications/System Settings.app")

    func image(for item: Item) -> NSImage? {
        switch item.kind {
        case .application, .file, .folder:
            guard let path = item.fileURL?.path else { return nil }
            if let image = cache[path] { return image }
            let image = NSWorkspace.shared.icon(forFile: path)
            cache[path] = image
            return image
        case .settings: return settingsIcon
        case .command: return NSApp.applicationIconImage
        case .calculation, .link, .webSearch: return nil
        }
    }

    static func symbol(for kind: Kind) -> String {
        switch kind {
        case .calculation: "equal"
        case .link: "globe"
        default: "magnifyingglass"
        }
    }
}

/// An AppKit text field, because it gives the arrow, Return, and Escape keys to its delegate before
/// acting on them, which SwiftUI's TextField doesn't.
struct SearchField: NSViewRepresentable {
    @Bindable var model: SearchModel
    let fontSize: CGFloat
    let commands: Commands

    struct Commands {
        var move: (Int) -> Void
        var submit: () -> Void
        var cancel: () -> Void
        var made: (NSTextField) -> Void
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderString = "Search"
        field.delegate = context.coordinator
        field.setAccessibilityLabel("Search")
        commands.made(field)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        if field.font != font { field.font = font }
        if field.stringValue != model.query { field.stringValue = model.query }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchField

        init(parent: SearchField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.model.query = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.commands.move(-1)
            case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.insertTab(_:)): parent.commands.move(1)
            case #selector(NSResponder.insertBacktab(_:)): parent.commands.move(-1)
            case #selector(NSResponder.insertNewline(_:)): parent.commands.submit()
            case #selector(NSResponder.cancelOperation(_:)): parent.commands.cancel()
            default: return false
            }
            return true
        }
    }
}
