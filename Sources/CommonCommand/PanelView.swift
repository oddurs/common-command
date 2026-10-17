import AppKit
import CommandKit
import SwiftUI

/// The search field, in its capsule.
struct FieldView: View {
    @Bindable var model: SearchModel
    let preferences: Preferences
    let commands: SearchField.Commands

    private var size: PanelSize { preferences.size }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: model.scope.symbol)
                .font(.system(size: size.fieldFontSize * 0.82, weight: .medium))
                .foregroundStyle(model.scope == .all ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                .frame(width: size.fieldFontSize * 1.1)
            SearchField(model: model, fontSize: size.fieldFontSize, commands: commands)
            ScopeButtons(model: model, size: size, toggle: commands.toggleScope)
        }
        .padding(.leading, size.fieldHeight * 0.36)
        .padding(.trailing, size.fieldHeight * 0.3)
        .frame(width: size.width, height: size.fieldHeight)
        .surface(radius: size.fieldRadius, solid: !preferences.translucent)
    }
}

/// Apps, Files, and Actions, as in Spotlight on macOS 26: a click or ⌘1–⌘3 narrows the search to one
/// kind, and with nothing typed lists what that kind holds.
private struct ScopeButtons: View {
    let model: SearchModel
    let size: PanelSize
    let toggle: (Scope) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Scope.scoped) { scope in
                let isOn = model.scope == scope
                Button {
                    toggle(scope)
                } label: {
                    Image(systemName: scope.symbol)
                        .font(.system(size: size.fieldFontSize * 0.62, weight: .medium))
                        .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                        .frame(width: size.fieldHeight * 0.62, height: size.fieldHeight * 0.62)
                        .background(Circle().fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.clear)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("\(scope.name) (⌘\(scope.key.map(String.init) ?? ""))")
                .accessibilityLabel(scope.name)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
    }
}

/// The results, in sections, on their own card under the field.
struct CardView: View {
    let model: SearchModel
    let preferences: Preferences
    let choose: (Int) -> Void

    private var size: PanelSize { preferences.size }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    if model.showsNoResults {
                        Text("No Results")
                            .font(.system(size: size.rowFontSize))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: size.rowHeight)
                    }
                    ForEach(Array(sectionStarts.enumerated()), id: \.element.section.id) { _, entry in
                        SectionHeader(title: entry.section.title, size: size)
                        ForEach(Array(entry.section.rows.enumerated()), id: \.element.id) { offset, ranked in
                            let index = entry.start + offset
                            ResultRow(ranked: ranked, size: size, isSelected: index == model.selection)
                                .id(index)
                                .onTapGesture { choose(index) }
                                .onContinuousHover { phase in
                                    if case .active = phase { model.hover(index) }
                                }
                                .dragsFile(ranked.item.fileURL)
                        }
                    }
                }
                .padding(size.cardPadding)
            }
            .scrollIndicators(.automatic)
            .onChange(of: model.selection) { _, selection in proxy.scrollTo(selection) }
        }
        .frame(width: size.width)
        .frame(maxHeight: .infinity)
        .surface(radius: size.cardRadius, solid: !preferences.translucent)
    }

    /// Each section with the overall index of its first row, so rows know their place in the selection.
    private var sectionStarts: [(section: ResultSection, start: Int)] {
        var start = 0
        return model.sections.map { section in
            defer { start += section.rows.count }
            return (section, start)
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let size: PanelSize

    var body: some View {
        Text(title)
            .font(.system(size: size.headerFontSize, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: size.headerHeight, alignment: .bottomLeading)
            .padding(.bottom, 2)
            .frame(height: size.headerHeight)
            .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// The drawn part of a glass shape: a solid fill when translucency is off (the glass sits behind in
    /// AppKit otherwise), and a hairline edge either way, as on menus and popovers.
    func surface(radius: CGFloat, solid: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return
            self
            .background {
                if solid { shape.fill(Color(nsColor: .windowBackgroundColor)) }
            }
            .overlay { shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5) }
    }
}

extension View {
    /// Apps, files, and folders drag out like they do from Finder: into the Dock, a folder, or a document.
    @ViewBuilder func dragsFile(_ url: URL?) -> some View {
        if let url {
            onDrag { NSItemProvider(object: url as NSURL) }
        } else {
            self
        }
    }
}

private struct ResultRow: View {
    let ranked: Ranked
    let size: PanelSize
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            ItemIcon(item: ranked.item, size: size.iconSize, isSelected: isSelected)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 16)
            Text(ranked.item.subtitle)
                .font(.system(size: size.rowFontSize - 2))
                .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                // A path keeps its start and its end: "~/Code/…/src" says more than "…ode/app/src".
                .truncationMode(.middle)
                .layoutPriority(-1)
        }
        .font(.system(size: size.rowFontSize))
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 8)
        .frame(height: size.rowHeight)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: size.rowRadius, style: .continuous)
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
            return cached(path)
        case .settings:
            guard let path = item.iconFile?.path else { return settingsIcon }
            return cached(path)
        case .command: return NSApp.applicationIconImage
        case .action: return item.iconFile.map { cached($0.path) }
        case .calculation, .link, .webSearch: return nil
        }
    }

    private func cached(_ path: String) -> NSImage {
        if let image = cache[path] { return image }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache[path] = image
        return image
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
        /// ⌫ in an empty field leaves the scope; returns whether there was one to leave.
        var leaveScope: () -> Bool
        var toggleScope: (Scope) -> Void
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
        let placeholder = model.scope == .all ? "Search" : "Search \(model.scope.name)"
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
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
            case #selector(NSResponder.deleteBackward(_:)) where textView.string.isEmpty:
                return parent.commands.leaveScope()
            default: return false
            }
            return true
        }
    }
}
