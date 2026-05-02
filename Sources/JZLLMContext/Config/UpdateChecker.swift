import Foundation

enum UpdateChecker {
    private static let releasesURL = URL(string: "https://api.github.com/repos/honzabfu/JZLLMContext/releases/latest")!

    struct Release: Decodable {
        let tag_name: String
        let html_url: String

        var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    }

    private enum Cache {
        static let etag = "UpdateChecker.etag"
        static let data = "UpdateChecker.cachedRelease"
    }

    static func fetchLatest() async throws -> Release {
        var req = URLRequest(url: releasesURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        if let etag = UserDefaults.standard.string(forKey: Cache.etag) {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if http.statusCode == 304,
           let cached = UserDefaults.standard.data(forKey: Cache.data) {
            return try JSONDecoder().decode(Release.self, from: cached)
        }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
        if let newEtag = http.value(forHTTPHeaderField: "ETag") {
            UserDefaults.standard.set(newEtag, forKey: Cache.etag)
            UserDefaults.standard.set(data, forKey: Cache.data)
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        candidate.compare(current, options: .numeric) == .orderedDescending
    }

    static func checkOnLaunch() async {
        guard ConfigStore.shared.config.autoUpdateCheck else { return }
        guard let release = try? await fetchLatest(),
              isNewer(release.version, than: currentVersion),
              let url = URL(string: release.html_url),
              url.host == "github.com" else { return }
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
