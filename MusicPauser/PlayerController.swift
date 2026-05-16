import Foundation

enum PlayerKind: String, CaseIterable, Hashable {
    case appleMusic
    case spotify

    var displayName: String {
        switch self {
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}

protocol PlayerController: AnyObject {
    var kind: PlayerKind { get }
    var bundleIdentifier: String { get }

    func isRunning() -> Bool
    func isPlaying() -> Bool
    func pause()
    func play()
}
