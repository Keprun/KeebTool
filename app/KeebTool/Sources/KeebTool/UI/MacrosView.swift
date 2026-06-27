import SwiftUI

struct MacrosView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if model.macroCount == 0 {
                VStack(spacing: 12) {
                    Image(systemName: "text.append").font(.largeTitle).foregroundStyle(.secondary)
                    Text("No macros loaded").foregroundStyle(.secondary)
                    Button("Load from keyboard") { Task { await model.loadMacros() } }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        ForEach(model.macros.indices, id: \.self) { i in
                            HStack(spacing: 10) {
                                Text("M\(i)").font(.callout.monospaced()).foregroundStyle(.secondary)
                                    .frame(width: 36, alignment: .leading)
                                if model.isAdvancedMacro(i) {
                                    Text("⟨advanced macro — edit in VIA⟩").foregroundStyle(.secondary).italic()
                                } else {
                                    TextField("type text to send…", text: Binding(
                                        get: { model.macros[i] },
                                        set: { model.setMacroText(i, $0) }))
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    } header: {
                        Text("\(model.macroCount) macro slots")
                    } footer: {
                        Text("Plain-text macros type the characters. Bind a macro to a key on the Keymap tab — search “M0”…“M15” in the picker. Advanced macros (key combos / delays) are preserved but edited in VIA.")
                    }
                }
                HStack {
                    Button { Task { await model.loadMacros() } } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    Spacer()
                    Button { Task { await model.saveMacros() } } label: { Label("Save to keyboard", systemImage: "internaldrive") }
                        .buttonStyle(.borderedProminent)
                }
                .padding(12)
            }
        }
        .task { if model.macroCount == 0 { await model.loadMacros() } }
    }
}
