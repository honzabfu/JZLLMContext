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
