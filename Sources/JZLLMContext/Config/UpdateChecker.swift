import Foundation

enum UpdateChecker {
    private static let releasesURL = URL(string: "https://api.github.com/repos/honzabfu/JZLLMContext/releases/latest")!

    struct Release: Decodable {
        let tag_name: String
        let html_url: String

        var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    }

    static func fetchLatest() async throws -> Release {
        var req = URLRequest(url: releasesURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func checkOnLaunch() async {
        guard ConfigStore.shared.config.autoUpdateCheck else { return }
        guard let release = try? await fetchLatest(),
              release.version != currentVersion,
              let url = URL(string: release.html_url) else { return }
        await MainActor.run {
            NotificationCenter.default.post(
                name: .updateAvailable,
                object: nil,
                userInfo: ["version": release.version, "url": url]
            )
        }
    }
}

extension Notification.Name {
    static let updateAvailable = Notification.Name("JZLLMContextUpdateAvailable")
}
