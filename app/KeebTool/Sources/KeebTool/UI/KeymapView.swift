import SwiftUI

struct KeymapView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Loc
    @State private var selected: KeyRef?
    @State private var hovered: KeyRef?
    @State private var search = ""

    struct KeyRef: Equatable { let row: Int; let col: Int }

    private var boardSize: CGSize {
        let maxX = KB.keys.map { $0.x + $0.w }.max() ?? 1
        let maxY = KB.keys.map { $0.y + $0.h }.max() ?? 1
        return CGSize(width: CGFloat(maxX) * KeycapView.UNIT + 12, height: CGFloat(maxY) * KeycapView.UNIT + 12)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                toolbar
                if model.dongleMode {
                    dongleBanner
                } else {
                    ScrollView([.horizontal, .vertical]) {
                        board.frame(width: boardSize.width, height: boardSize.height, alignment: .topLeading).padding(6)
                    }
                }
            }
            .padding(14)
            .frame(minWidth: 680, maxWidth: .infinity, maxHeight: .infinity)

            Rectangle().fill(Theme.border).frame(width: 0.5)
            pickerPanel.frame(width: 286)
        }
        .background(Theme.paneVignette)
        .task { await model.loadKeymap() }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Picker("", selection: $model.selectedLayer) {
                ForEach(0..<model.layerCount, id: \.self) { Text("L\($0)").tag($0) }
            }
            .labelsHidden().pickerStyle(.segmented).frame(width: 220)
            Button { Task { await model.loadKeymap() } } label: { Image(systemName: "arrow.clockwise") }
            Button { Task { await model.resetKeymap() } } label: { Image(systemName: "arrow.uturn.backward") }
                .help(loc.t("keymap.resetTooltip"))
            if model.loading { ProgressView().controlSize(.small) }
            Spacer()
        }
        .tint(Theme.accent)
    }

    private var dongleBanner: some View {
        VStack(spacing: 10) {
            Image(systemName: "cable.connector").font(.system(size: 36)).foregroundStyle(Theme.accent2)
            Text(loc.t("keymap.dongleTitle")).font(.headline).foregroundStyle(Theme.textPrimary)
            Text(loc.t("keymap.dongleBody"))
                .font(.callout).foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center).frame(maxWidth: 430)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var board: some View {
        ZStack(alignment: .topLeading) {
            ForEach(KB.keys) { key in
                let ref = KeyRef(row: key.row, col: key.col)
                let kc = model.keycode(model.selectedLayer, key.row, key.col)
                Button { selected = ref } label: {
                    KeycapView(label: Keycodes.label(for: kc), symbol: nil, w: CGFloat(key.w), h: CGFloat(key.h), state: stateFor(ref, kc))
                        .equatable()
                }
                .buttonStyle(.plain)
                .offset(x: CGFloat(key.x) * KeycapView.UNIT, y: CGFloat(key.y) * KeycapView.UNIT)
                .onHover { inside in
                    if inside { hovered = ref } else if hovered == ref { hovered = nil }
                }
                .help("\(key.label) · matrix \(key.row),\(key.col)")
            }
        }
    }

    private func stateFor(_ ref: KeyRef, _ kc: UInt16) -> KeyVisualState {
        if selected == ref { return .selected }
        if hovered == ref { return .hover }
        if (0xE0...0xE7).contains(kc) || LayerKC.decode(kc) != nil { return .modifier }
        return .rest
    }

    // MARK: Picker

    private var pickerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sel = selected {
                Text(keyLabel(sel)).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Text("L\(model.selectedLayer) · \(sel.row),\(sel.col) · \(loc.t("keymap.now")) \(Keycodes.label(for: model.keycode(model.selectedLayer, sel.row, sel.col)))")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(loc.t("keymap.selectKey")).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            }
            TextField(loc.t("common.search"), text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if search.isEmpty { layerKeys }
                    ForEach(Keycodes.groups, id: \.self) { group in
                        let items = filtered(group)
                        if !items.isEmpty {
                            Text(group.uppercased()).font(.system(size: 10, weight: .semibold)).kerning(1.2)
                                .foregroundStyle(Theme.textSecondary).padding(.top, 8)
                            ForEach(items) { kc in codeButton(kc.value, kc.label) }
                        }
                    }
                }
                .padding(.trailing, 4)
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface)
        .disabled(selected == nil)
    }

    private var layerKeys: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(loc.t("keymap.layerKeys")).font(.system(size: 10, weight: .semibold)).kerning(1.2).foregroundStyle(Theme.textSecondary).padding(.top, 8)
            ForEach(0..<model.layerCount, id: \.self) { n in
                HStack(spacing: 4) {
                    codeButton(LayerKC.MO(n), "MO(\(n))")
                    codeButton(LayerKC.TG(n), "TG(\(n))")
                    codeButton(LayerKC.TO(n), "TO(\(n))")
                }
            }
        }
    }

    private func keyLabel(_ ref: KeyRef) -> String {
        KB.keys.first { $0.row == ref.row && $0.col == ref.col }?.label ?? "Key"
    }

    private func filtered(_ group: String) -> [Keycode] {
        Keycodes.all.filter {
            $0.group == group && (search.isEmpty
                || $0.label.localizedCaseInsensitiveContains(search)
                || $0.name.localizedCaseInsensitiveContains(search))
        }
    }

    private func codeButton(_ value: UInt16, _ label: String) -> some View {
        Button {
            guard let s = selected else { return }
            Task { await model.setKey(row: s.row, col: s.col, keycode: value) }
        } label: {
            Text(label).font(.system(size: 11)).foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.surfaceAlt))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }
}
