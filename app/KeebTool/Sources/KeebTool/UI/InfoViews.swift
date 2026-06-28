import SwiftUI

/// Popover with full device / connection / battery details (the "separate button" status panel).
struct DeviceInfoView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Loc

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: model.connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(model.connected ? Color.green : Color.red)
                Text(model.connected ? loc.t("device.connected") : loc.t("device.disconnected")).font(.headline)
            }
            Divider()

            if let b = model.battery {
                HStack {
                    Text(model.charging ? loc.t("info.charging") : loc.t("info.battery")).foregroundStyle(.secondary)
                    Spacer()
                    if model.charging { Image(systemName: "bolt.fill").foregroundStyle(.yellow).font(.caption) }
                    Text("\(model.menuPercent ?? b.pct)%").font(.callout.monospaced())
                }
                ProgressView(value: Double(model.menuPercent ?? b.pct), total: 100).tint(batteryTint(model.menuPercent ?? b.pct))
                row(loc.t("info.voltage"), String(format: "%.3f V", Double(b.mv) / 1000))
                if model.charging {
                    Text(loc.t("info.chargingNote")).font(.caption2).foregroundStyle(.secondary)
                }
                if let r = model.restingText { row(loc.t("info.resting"), r) }
            } else if model.dongleMode {
                row(loc.t("info.resting"), model.restingText ?? model.lastBatteryText ?? "—")
                Text(loc.t("info.dongleNote")).font(.caption2).foregroundStyle(.secondary)
            } else {
                row(loc.t("info.battery"), "—")
            }

            row(loc.t("info.connection"), model.dongleMode ? loc.t("device.dongle") : (model.connected ? loc.t("info.usbCable") : "—"))
            row(loc.t("info.model"), "Keychron V1 Max · ANSI")
            row(loc.t("info.usbId"), "0x3434 : 0x0913")
            row(loc.t("info.viaProto"), model.viaProtocol > 0 ? "v\(model.viaProtocol)" : "—")
            Divider()
            Button { Task { await model.refreshBattery() } } label: {
                Label(loc.t("common.refresh"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 280)
    }

    private func row(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.callout.monospaced())
        }
    }

    private func batteryTint(_ pct: Int) -> Color {
        switch pct { case ...15: return .red; case ...35: return .orange; default: return .green }
    }
}

struct AboutView: View {
    @EnvironmentObject var loc: Loc
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "keyboard.fill").font(.system(size: 38)).foregroundStyle(.tint)
            Text(loc.t("about.title")).font(.headline)
            Text("\(loc.t("about.version")) 2.0").font(.caption).foregroundStyle(.secondary)
            Text(loc.t("about.desc"))
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text(loc.t("about.note"))
                .font(.caption2).multilineTextAlignment(.center).foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 300)
    }
}
