import SwiftUI

/// Popover with full device / connection / battery details (the "separate button" status panel).
struct DeviceInfoView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: model.connected ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(model.connected ? Color.green : Color.red)
                Text(model.connected ? "Connected" : "Disconnected").font(.headline)
            }
            Divider()

            if let b = model.battery {
                // On the cable — live, but the pack is charging so % reads high.
                HStack {
                    Text(model.charging ? "Charging" : "Battery").foregroundStyle(.secondary)
                    Spacer()
                    if model.charging { Image(systemName: "bolt.fill").foregroundStyle(.yellow).font(.caption) }
                    Text("\(model.menuPercent ?? b.pct)%").font(.callout.monospaced())
                }
                ProgressView(value: Double(model.menuPercent ?? b.pct), total: 100).tint(batteryTint(model.menuPercent ?? b.pct))
                row("Voltage", String(format: "%.3f V", Double(b.mv) / 1000))
                if model.charging {
                    Text("On the cable the pack is charging, so % reads high. The truest charge is the resting value below.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if let r = model.restingText { row("Resting ≈", r) }
            } else if model.dongleMode {
                // On the dongle — battery only arrives at (re)connect; show last resting value.
                row("Resting ≈", model.restingText ?? model.lastBatteryText ?? "—")
                Text("The 2.4GHz dongle reports battery only when the keyboard (re)connects. Plug a USB cable for a live reading.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                row("Battery", "—")
            }

            row("Connection", model.dongleMode ? "2.4GHz dongle" : (model.connected ? "USB cable" : "—"))
            row("Model", "Keychron V1 Max · ANSI")
            row("USB ID", "0x3434 : 0x0913")
            row("VIA protocol", model.viaProtocol > 0 ? "v\(model.viaProtocol)" : "—")
            Divider()
            Button { Task { await model.refreshBattery() } } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 270)
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
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "keyboard.fill").font(.system(size: 38)).foregroundStyle(.tint)
            Text("Keychron V1 Max Tool").font(.headline)
            Text("Version 2.0").font(.caption).foregroundStyle(.secondary)
            Text("Battery monitor + VIA configurator — keymap, macros and lighting for the Keychron V1 Max over the VIA raw-HID protocol.")
                .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("Live battery uses the custom 0xA4 firmware command over USB. The 2.4GHz dongle reports battery only at (re)connect.")
                .font(.caption2).multilineTextAlignment(.center).foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 300)
    }
}
