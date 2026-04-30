import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                appHeader
                    .padding(24)
                Divider()
                setupSection
                    .padding(24)
                Divider()
                iconGuide
                    .padding(24)
                Divider()
                footer
                    .padding(20)
            }
        }
        .frame(width: 420, height: 650)
    }

    // MARK: - Header

    private var appHeader: some View {
        VStack(spacing: 12) {
            if let icon = NSImage(named: "AppColorIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            VStack(spacing: 3) {
                Text("JZLLMContext")
                    .font(.title2.bold())
                Text(String(format: L("about.version"), version))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(L("about.description"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Setup steps

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("about.setup.title"))
                .font(.headline)

            step(1, icon: "network", title: L("about.setup.step1.title")) {
                Text(LMD("about.setup.step1.text"))
            }

            step(2, icon: "key", title: L("about.setup.step2.title")) {
                Text(LMD("about.setup.step2.text"))
            }

            step(3, icon: "list.bullet", title: L("about.setup.step3.title")) {
                Text(LMD("about.setup.step3.text"))
            }

            HStack(spacing: 6) {
                flowStep(L("about.flow.copy"))
                flowArrow
                flowStep("Cmd+Shift+Space")
                flowArrow
                flowStep(L("about.flow.click"))
                flowArrow
                flowStep(L("about.flow.paste"))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func step<C: View>(_ n: Int, icon: String, title: String, @ViewBuilder content: () -> C) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 26, height: 26)
                Text("\(n)")
                    .font(.callout.bold())
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 3) {
                Label(title, systemImage: icon)
                    .font(.callout.bold())
                content()
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func flowStep(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.right")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    // MARK: - Icon guide

    private var iconGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("about.icons.title"))
                .font(.headline)

            iconRow("doc.on.clipboard",          L("about.icons.clipboard_text"))
            iconRow("doc.viewfinder",             L("about.icons.clipboard_ocr"))
            iconRow("eye.slash",                  L("about.icons.clipboard_ignored"))

            Divider().padding(.vertical, 2)

            iconRow("exclamationmark.triangle",   L("about.icons.missing_key"), color: .orange)
            HStack(alignment: .center, spacing: 12) {
                Text("1")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text(L("about.icons.keyboard_shortcut"))
                    .font(.callout)
            }
            iconRow("return.left",                L("about.icons.default_action"), color: .accentColor)
            HStack(alignment: .center, spacing: 12) {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 20, height: 16)
                Text(L("about.icons.action_running"))
                    .font(.callout)
            }
            iconRow("arrow.right",                L("about.icons.action_ready"))

            Divider().padding(.vertical, 2)

            iconRow("clock",                      L("about.icons.history"))
            iconRow("gearshape",                  L("about.icons.settings"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func iconRow(_ symbol: String, _ label: String, color: Color = .secondary) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 20, alignment: .center)
            Text(label)
                .font(.callout)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                Text("Autor: Jan Žák")
                    .font(.callout)
                Link("jan-zak.cz", destination: URL(string: "https://jan-zak.cz")!)
                    .font(.callout)
            }

            Divider()

            VStack(spacing: 6) {
                Link(L("about.footer.license"), destination: URL(string: "https://github.com/honzabfu/JZLLMContext/blob/main/LICENSE")!)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(L("about.footer.disclaimer"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
