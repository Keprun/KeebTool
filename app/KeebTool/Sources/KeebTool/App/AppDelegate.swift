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
    private let loc = Loc.shared
    private var statusItem: NSStatusItem!
    private var configWindow: NSWindow?
    private var cancellables = Set<AnyCancellable>()
    private var batteryItem: NSMenuItem!
    private var restingItem: NSMenuItem!
    private var openItem: NSMenuItem!
    private var quitItem: NSMenuItem!

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

        openItem = NSMenuItem(title: loc.t("menu.open"), action: #selector(openConfig), keyEquivalent: "o")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        quitItem = NSMenuItem(title: loc.t("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        statusItem.menu = menu
        menu.delegate = self

        render()
        // Re-render the menu bar on either battery/model changes or a language switch.
        Publishers.Merge(model.objectWillChange, loc.objectWillChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
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
            let prefix = model.charging ? " ⚡" : (model.menuApprox ? " ~" : " ")
            button.title = "\(prefix)\(pct)%"
        } else {
            button.title = model.dongleMode ? " 2.4G" : " —"
        }
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "battery")
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeading

        openItem?.title = loc.t("menu.open")
        quitItem?.title = loc.t("menu.quit")
        renderMenuDetail()
    }

    private func renderMenuDetail() {
        guard batteryItem != nil else { return }
        if model.dongleMode {
            batteryItem.title = loc.t("device.dongle")
            if let r = model.restingText { restingItem.title = "\(loc.t("menu.resting")) ~\(r)"; restingItem.isHidden = false }
            else { restingItem.title = loc.t("menu.plugCable"); restingItem.isHidden = false }
        } else if let b = model.battery {
            let p = model.menuPercent ?? b.pct
            let v = String(format: "%.2f", Double(b.mv) / 1000)
            batteryItem.title = model.charging ? "\(loc.t("menu.charging")) \(p)% · \(v)V" : "\(loc.t("menu.battery")) \(p)% · \(v)V"
            if let r = model.restingText { restingItem.title = "\(loc.t("menu.resting")) ~\(r)"; restingItem.isHidden = false }
            else { restingItem.isHidden = true }
        } else {
            batteryItem.title = "\(loc.t("menu.battery")): —"
            restingItem.isHidden = true
        }
    }

    @objc private func openConfig() {
        if configWindow == nil {
            let host = NSHostingController(rootView: ConfigView().environmentObject(model).environmentObject(loc))
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
