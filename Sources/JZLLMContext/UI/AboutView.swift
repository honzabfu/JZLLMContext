import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1"
    }

    var body: some View {
        VStack(spacing: 14) {
            if let icon = NSImage(named: "AppColorIcon") {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            VStack(spacing: 4) {
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

            Divider()

            VStack(spacing: 6) {
                Text("Autor: Jan Žák")
                    .font(.callout)
                Link("jan-zak.cz", destination: URL(string: "https://jan-zak.cz")!)
                    .font(.callout)
            }
        }
        .padding(28)
        .frame(width: 280)
    }
}
