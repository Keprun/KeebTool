import Cocoa
import SwiftUI
import Combine

/// Menu-bar battery item (AppKit NSStatusItem) + on-demand SwiftUI configurator window.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static func main() {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: .darkAqua)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu-bar app; the configurator window still shows on demand
        app.run()
    }

    let model = AppModel()
    private var statusItem: NSStatusItem!
    private var configWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var batteryItem: NSMenuItem!
    private var restingItem: NSMenuItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()

        batteryItem = NSMenuItem(title: "Battery: —", action: nil, keyEquivalent: "")
        batteryItem.isEnabled = false
        menu.addItem(batteryItem)
        restingItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        restingItem.isEnabled = false
        menu.addItem(restingItem)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open Configurator…", action: #selector(openConfig), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        menu.delegate = self

        render()
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
        // The very first battery read in AppModel.init can fire before this sink is live,
        // so the menu bar would miss it (stuck on "—" until the next change). Force one now.
        Task { @MainActor in await self.model.refreshBattery() }
    }

    func menuWillOpen(_ menu: NSMenu) {
        Task { @MainActor in await self.model.refreshBattery() }
    }

    private func render() {
        guard let button = statusItem.button else { return }
        let pct = model.menuPercent
        let symbol: String
        switch pct {
        case .some(let p) where p <= 10: symbol = "battery.0"
        case .some(let p) where p <= 37: symbol = "battery.25"
        case .some(let p) where p <= 62: symbol = "battery.50"
        case .some(let p) where p <= 87: symbol = "battery.75"
        case .some: symbol = "battery.100"
        case .none: symbol = "battery.0"
        }
        if let pct {
            // ⚡ = charging over the cable (the % reads high), ~ = last-known value on the dongle.
            let prefix = model.charging ? " ⚡" : (model.menuApprox ? " ~" : " ")
            button.title = "\(prefix)\(pct)%"
        } else {
            button.title = model.dongleMode ? " 2.4G" : " —"
        }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "battery")
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeading

        renderMenuDetail()
    }

    /// Keep the dropdown's battery lines in sync with the model — honest about charging vs resting.
    private func renderMenuDetail() {
        guard batteryItem != nil else { return }
        if model.dongleMode {
            batteryItem.title = "2.4GHz dongle"
            if let r = model.restingText { restingItem.title = "Resting ~\(r)"; restingItem.isHidden = false }
            else { restingItem.title = "Plug cable for a live %"; restingItem.isHidden = false }
        } else if let b = model.battery {
            let p = model.menuPercent ?? b.pct
            let v = String(format: "%.2f", Double(b.mv) / 1000)
            batteryItem.title = model.charging ? "Charging \(p)% · \(v)V" : "Battery \(p)% · \(v)V"
            if let r = model.restingText { restingItem.title = "Resting ~\(r)"; restingItem.isHidden = false }
            else { restingItem.isHidden = true }
        } else {
            batteryItem.title = "Battery: —"
            restingItem.isHidden = true
        }
    }

    @objc private func openConfig() {
        if configWindow == nil {
            let host = NSHostingController(rootView: ConfigView().environmentObject(model))
            let w = NSWindow(contentViewController: host)
            w.title = "Keychron V1 Max"
            w.setContentSize(NSSize(width: 1040, height: 500))
            w.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            w.isReleasedWhenClosed = false
            w.center()
            configWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        configWindow?.makeKeyAndOrderFront(nil)
    }
}
