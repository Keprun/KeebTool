import SwiftUI

struct MacrosView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var loc: Loc

    var body: some View {
        VStack(spacing: 0) {
            if model.macroCount == 0 {
                VStack(spacing: 12) {
                    Image(systemName: "text.append").font(.largeTitle).foregroundStyle(.secondary)
                    Text(loc.t("macros.none")).foregroundStyle(.secondary)
                    Button(loc.t("macros.load")) { Task { await model.loadMacros() } }
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
                                    Text("⟨\(loc.t("macros.advanced"))⟩").foregroundStyle(.secondary).italic()
                                } else {
                                    TextField(loc.t("macros.placeholder"), text: Binding(
                                        get: { model.macros[i] },
                                        set: { model.setMacroText(i, $0) }))
                                    .textFieldStyle(.roundedBorder)
                                }
                            }
                        }
                    } header: {
                        Text(loc.tf("macros.slots", model.macroCount))
                    } footer: {
                        Text(loc.t("macros.footer"))
                    }
                }
                HStack {
                    Button { Task { await model.loadMacros() } } label: { Label(loc.t("common.reload"), systemImage: "arrow.clockwise") }
                    Spacer()
                    Button { Task { await model.saveMacros() } } label: { Label(loc.t("common.save"), systemImage: "internaldrive") }
                        .buttonStyle(.borderedProminent)
                }
                .padding(12)
            }
        }
        .task { if model.macroCount == 0 { await model.loadMacros() } }
    }
}
