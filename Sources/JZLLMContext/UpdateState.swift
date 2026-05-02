import Foundation
import AppKit

@MainActor
final class UpdateState: ObservableObject {
    static let shared = UpdateState()
    @Published var updateURL: URL?
    @Published var updateVersion: String?
    var isAvailable: Bool { updateURL != nil }
}
