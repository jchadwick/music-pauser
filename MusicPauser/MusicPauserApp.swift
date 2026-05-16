import SwiftUI
import AppKit

// Composites two SF Symbols into a single NSImage for the menu bar.
// The badge is drawn at the bottom-right corner of the primary symbol.
private func menuBarImage(primary: String, badge: String) -> NSImage {
    let size = NSSize(width: 22, height: 16)
    let image = NSImage(size: size, flipped: false) { rect in
        // Primary symbol — centered, slightly left to leave room for badge
        let primaryConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        if let sym = NSImage(systemSymbolName: primary, accessibilityDescription: nil)?
            .withSymbolConfiguration(primaryConfig) {
            let symSize = sym.size
            let origin = NSPoint(x: (rect.width - symSize.width) / 2 - 2,
                                 y: (rect.height - symSize.height) / 2)
            sym.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        }
        // Badge symbol — small, bottom-right
        let badgeConfig = NSImage.SymbolConfiguration(pointSize: 7, weight: .bold)
        if let sym = NSImage(systemSymbolName: badge, accessibilityDescription: nil)?
            .withSymbolConfiguration(badgeConfig) {
            let symSize = sym.size
            let origin = NSPoint(x: rect.width - symSize.width,
                                 y: 0)
            sym.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
        }
        return true
    }
    image.isTemplate = true  // lets macOS tint it for dark/light menu bar
    return image
}

@main
struct MusicPauserApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            ContentView(appState: appState)
        } label: {
            let img = appState.micInUse
                ? menuBarImage(primary: "mic.fill",        badge: "pause.fill")
                : menuBarImage(primary: "mic.slash.fill",  badge: "play.fill")
            Image(nsImage: img)
        }
        .menuBarExtraStyle(.menu)
    }
}
