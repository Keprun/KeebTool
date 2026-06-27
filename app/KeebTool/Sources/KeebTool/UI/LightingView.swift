import SwiftUI

struct LightingView: View {
    @EnvironmentObject var model: AppModel
    @State private var brightness = 255.0
    @State private var speed = 128.0
    @State private var hue = 0.0
    @State private var sat = 255.0

    private let effects = [
        "Off", "Solid Color", "Breathing", "Band Spiral", "Cycle All",
        "Cycle Left/Right", "Cycle Up/Down", "Rainbow Chevron", "Cycle Out/In",
        "Cycle Out/In Dual", "Cycle Pinwheel", "Cycle Spiral", "Dual Beacon",
        "Rainbow Beacon", "Jellybean Raindrops", "Pixel Rain", "Typing Heatmap",
        "Digital Rain", "Reactive Simple", "Reactive Multiwide", "Reactive Multinexus",
        "Splash", "Solid Splash",
    ]

    var body: some View {
        Form {
            Section("Effect") {
                Picker("Animation", selection: Binding(
                    get: { model.rgbEffect },
                    set: { e in Task { await model.setRGBEffect(e) } }
                )) {
                    ForEach(0..<effects.count, id: \.self) { Text(effects[$0]).tag($0) }
                }
            }

            Section("Brightness & speed") {
                slider("Brightness", $brightness) { Task { await model.setRGBBrightness(Int(brightness)) } }
                slider("Speed", $speed) { Task { await model.setRGBSpeed(Int(speed)) } }
            }

            Section("Color") {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(hue: hue / 255, saturation: sat / 255, brightness: 1))
                        .frame(width: 48, height: 28)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.3)))
                    Text("preview").font(.caption).foregroundStyle(.secondary)
                }
                slider("Hue", $hue) { Task { await model.setRGBColor(h: Int(hue), s: Int(sat)) } }
                slider("Saturation", $sat) { Task { await model.setRGBColor(h: Int(hue), s: Int(sat)) } }
                Text("Color applies to color-capable effects (Solid, Splash, Reactive…).")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button { Task { await model.loadLighting(); syncLocal() } } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    Spacer()
                    Button { Task { await model.saveLighting() } } label: { Label("Save to keyboard", systemImage: "internaldrive") }
                        .buttonStyle(.borderedProminent)
                }
            } footer: {
                Text("Changes apply live; Save writes them to the keyboard's memory so they survive a power cycle.")
            }
        }
        .formStyle(.grouped)
        .task { await model.loadLighting(); syncLocal() }
    }

    private func slider(_ label: String, _ value: Binding<Double>, onCommit: @escaping () -> Void) -> some View {
        HStack {
            Text(label).frame(width: 92, alignment: .leading)
            Slider(value: value, in: 0...255) { editing in if !editing { onCommit() } }
            Text("\(Int(value.wrappedValue))").frame(width: 38, alignment: .trailing).font(.callout.monospaced())
        }
    }

    private func syncLocal() {
        brightness = Double(model.rgbBrightness)
        speed = Double(model.rgbSpeed)
        hue = Double(model.rgbHue)
        sat = Double(model.rgbSat)
    }
}
