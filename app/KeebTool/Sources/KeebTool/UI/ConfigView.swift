import SwiftUI

enum Pane: String, CaseIterable, Identifiable {
    case keymap, macros, lighting, settings
    var id: String { rawValue }
    var key: String { "nav.\(rawValue)" }
    var icon: String {
        switch self {
        case .keymap: return "keyboard"
        case .macros: return "command"
        case .lighting: return "lightbulb"
        case .settings: return "gearshape"
        }
    }
}

struct ConfigView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Loc
    @State private var pane: Pane = .keymap
    @State private var showInfo = false
    @State private var showAbout = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(minWidth: 980, minHeight: 560)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .environment(\.layoutDirection, loc.layout)
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 0.5)
            Group {
                switch pane {
                case .keymap: KeymapView()
                case .macros: MacrosView()
                case .lighting: LightingView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 9) {
                Image(systemName: "keyboard.fill").font(.title3).foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text("KEYCHRON").font(.system(size: 11, weight: .semibold)).kerning(1.5).foregroundStyle(Theme.textPrimary)
                    Text("V1 Max").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 14).padding(.top, 16).padding(.bottom, 14)

            ForEach(Pane.allCases) { navItem($0) }
            Spacer()
            deviceButton
        }
        .frame(width: 198)
        .background(Theme.surface)
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.border).frame(width: 0.5) }
    }

    private func navItem(_ p: Pane) -> some View {
        let active = pane == p
        return Button { pane = p } label: {
            HStack(spacing: 10) {
                Image(systemName: p.icon).frame(width: 18)
                Text(loc.t(p.key)).font(.system(size: 13, weight: active ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 11).padding(.vertical, 7)
            .foregroundStyle(active ? Theme.bg : Theme.textSecondary)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 7).fill(Theme.accentFill)
                        .shadow(color: Theme.accent.opacity(0.35), radius: 8)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private var deviceButton: some View {
        Button { showInfo.toggle() } label: {
            HStack(spacing: 9) {
                Image(systemName: statusIcon).foregroundStyle(statusColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(statusTitle).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(statusSub).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surfaceAlt))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border))
        }
        .buttonStyle(.plain)
        .padding(10)
        .popover(isPresented: $showInfo, arrowEdge: .trailing) { DeviceInfoView().environmentObject(model).environmentObject(loc) }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5).fill(Theme.accent).frame(width: 3, height: 18)
            Text(loc.t(pane.key)).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
            if model.loading { ProgressView().controlSize(.small) }
            Text(model.status).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSecondary)
            Button { showAbout.toggle() } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .popover(isPresented: $showAbout, arrowEdge: .bottom) { AboutView().environmentObject(loc) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Theme.bg)
    }

    private var statusIcon: String {
        if model.dongleMode { return "cable.connector" }
        return model.connected ? "checkmark.circle.fill" : "xmark.circle.fill"
    }
    private var statusColor: Color {
        if model.dongleMode { return Theme.accent2 }
        return model.connected ? Color(hex: 0x5CE0A0) : Theme.textSecondary
    }
    private var statusTitle: String {
        if model.dongleMode { return loc.t("device.dongle") }
        return model.connected ? loc.t("device.connected") : loc.t("device.disconnected")
    }
    private var statusSub: String {
        if model.dongleMode { return model.restingText ?? model.lastBatteryText ?? "—" }
        if let b = model.battery { return "\(b.pct)% · \(String(format: "%.2f", Double(b.mv) / 1000))V" }
        return "—"
    }
}
