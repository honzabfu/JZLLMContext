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
        .frame(width: 420, height: 580)
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
                Text("Verze \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("Zpracovává obsah schránky (text i obrázky) pomocí jazykových modelů. Definuj vlastní akce se systémovými prompty a spouštěj je globální klávesovou zkratkou.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Setup steps

    private var setupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Před prvním použitím")
                .font(.headline)

            step(1, icon: "network", title: "Získej přístup k LLM") {
                Text("Pro cloudové providery (**OpenAI**, **Anthropic**) si vytvoř účet a vygeneruj API klíč. Vlastní nebo lokální modely (**Ollama**, **LM Studio**) žádný klíč nevyžadují.")
            }

            step(2, icon: "key", title: "Nakonfiguruj provider") {
                Text("Nastavení → záložka **Providery** → zadej adresu endpointu (pokud je potřeba) a API klíč → klikni **Uložit**.")
            }

            step(3, icon: "list.bullet", title: "Přizpůsob akce") {
                Text("V záložce **Akce** uprav systémové prompty nebo přidej vlastní. 5 akcí je předpřipraveno — tenhle krok je volitelný.")
            }

            HStack(spacing: 6) {
                flowStep("Zkopíruj text")
                flowArrow
                flowStep("Cmd+Shift+Space")
                flowArrow
                flowStep("Klikni na akci")
                flowArrow
                flowStep("Zkopíruj")
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
            Text("Přehled ikon v panelu")
                .font(.headline)

            iconRow("doc.on.clipboard",          "Text ze schránky")
            iconRow("doc.viewfinder",             "Text rozpoznaný z obrázku (OCR)")
            iconRow("eye.slash",                  "Schránka ignorována — akce dostane jen doplňkový kontext")

            Divider().padding(.vertical, 2)

            iconRow("exclamationmark.triangle",   "Chybí API klíč nebo adresa endpointu", color: .orange)
            HStack(alignment: .center, spacing: 12) {
                Text("1")
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Klávesová zkratka — stiskni číslici pro spuštění akce")
                    .font(.callout)
            }
            iconRow("return.left",                "Výchozí akce — spustí se také stiskem Enter", color: .accentColor)
            HStack(alignment: .center, spacing: 12) {
                ProgressView()
                    .scaleEffect(0.6)
                    .frame(width: 20, height: 16)
                Text("Akce právě běží")
                    .font(.callout)
            }
            iconRow("arrow.right",                "Akce připravena ke spuštění")

            Divider().padding(.vertical, 2)

            iconRow("clock",                      "Historie výsledků — uložena jen do zavření aplikace, nikam jinam se neukládá")
            iconRow("gearshape",                  "Otevřít nastavení")
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
        VStack(spacing: 5) {
            Text("Autor: Jan Žák")
                .font(.callout)
            Link("jan-zak.cz", destination: URL(string: "https://jan-zak.cz")!)
                .font(.callout)
        }
    }
}
