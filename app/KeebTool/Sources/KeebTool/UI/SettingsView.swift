import SwiftUI

/// Settings pane — interface language picker (7 languages) + a short About block.
struct SettingsView: View {
    @EnvironmentObject var loc: Loc

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                sectionTitle(loc.t("settings.language"))
                Text(loc.t("settings.languageNote"))
                    .font(.system(size: 11)).foregroundStyle(Theme.textSecondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                    ForEach(Lang.allCases) { langCard($0) }
                }

                Rectangle().fill(Theme.border).frame(height: 0.5).padding(.vertical, 6)

                sectionTitle(loc.t("settings.about"))
                VStack(alignment: .leading, spacing: 4) {
                    Text(loc.t("about.title")).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text("\(loc.t("about.version")) 2.0").font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    Text(loc.t("about.desc")).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(loc.t("about.note")).font(.system(size: 10)).foregroundStyle(Theme.textSecondary.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.paneVignette)
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased()).font(.system(size: 11, weight: .semibold)).kerning(1.2)
            .foregroundStyle(Theme.textSecondary)
    }

    private func langCard(_ l: Lang) -> some View {
        let active = loc.lang == l
        return Button { loc.lang = l } label: {
            HStack(spacing: 10) {
                Text(l.flag).font(.system(size: 20))
                VStack(alignment: .leading, spacing: 1) {
                    Text(l.native).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(active ? Theme.bg : Theme.textPrimary)
                    Text(l.english).font(.system(size: 10))
                        .foregroundStyle(active ? Theme.bg.opacity(0.7) : Theme.textSecondary)
                }
                Spacer()
                if active { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.bg) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background {
                if active {
                    RoundedRectangle(cornerRadius: 9).fill(Theme.accentFill)
                        .shadow(color: Theme.accent.opacity(0.3), radius: 8)
                } else {
                    RoundedRectangle(cornerRadius: 9).fill(Theme.surfaceAlt)
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.border))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
