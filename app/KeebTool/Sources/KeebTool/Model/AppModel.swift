import SwiftUI
import Combine

/// Observable app state: owns the VIADevice, caches keymap + lighting, drives battery polling.
///
/// Battery honesty: over the cable the pack is being charged, so the voltage-based % reads high and
/// jitters — we smooth it and flag charging. Over the 2.4GHz dongle the keyboard only reports battery
/// at (re)connect (hardware limit), and that resting value (no charge load) is the truest "how full"
/// number — we keep it separately as `dongleResting`.
@MainActor
final class AppModel: ObservableObject {
    let device = VIADevice()

    // Connection / battery
    @Published var connected = false
    @Published var battery: (pct: Int, mv: Int)?                 // live cable reading (raw, charging-influenced)
    @Published var charging = false                              // true while powered/charging over the cable
    @Published var viaProtocol = 0
    @Published var status = Loc.shared.t("status.starting")
    @Published var loading = false
    @Published var dongleMode = false
    @Published var lastBattery: (pct: Int, mv: Int, date: Date)? // last-known from any source (launch display)
    @Published var dongleResting: (pct: Int, date: Date)?        // last reading taken on battery = truest charge

    private let store = UserDefaults.standard
    private var cableSamples: [Int] = []                         // jitter-smoothing window for the cable %

    /// Smoothed cable % (median of the recent window) to tame charging jitter.
    private var smoothedCablePct: Int? {
        guard !cableSamples.isEmpty else { return nil }
        let s = cableSamples.sorted(); return s[s.count / 2]
    }

    /// Headline % for the menu bar: smoothed live value on cable, last-known true charge on dongle.
    var menuPercent: Int? {
        if dongleMode { return dongleResting?.pct ?? lastBattery?.pct }
        return smoothedCablePct ?? battery?.pct
    }
    var menuApprox: Bool { dongleMode && (dongleResting != nil || lastBattery != nil) }

    var lastBatteryText: String? {
        guard let lb = lastBattery else { return nil }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return "~\(lb.pct)% · \(f.localizedString(for: lb.date, relativeTo: Date()))"
    }
    var restingText: String? {
        guard let r = dongleResting else { return nil }
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        return "\(r.pct)% · \(f.localizedString(for: r.date, relativeTo: Date()))"
    }

    // Keymap
    @Published var layerCount = KB.layerCount
    @Published var selectedLayer = 0
    @Published var keymap: [[[UInt16]]] = Array(
        repeating: Array(repeating: Array(repeating: UInt16(0), count: KB.matrixCols), count: KB.matrixRows),
        count: KB.layerCount)

    // Lighting (QMK RGB matrix, channel 3)
    @Published var rgbEffect = 1
    @Published var rgbBrightness = 255
    @Published var rgbSpeed = 128
    @Published var rgbHue = 0
    @Published var rgbSat = 255

    // Macros
    @Published var macros: [String] = []
    @Published var macroCount = 0
    private var macroRaw: [[UInt8]] = []

    private var batteryTimer: Timer?

    init() {
        if store.object(forKey: "lastBatDate") != nil {
            lastBattery = (store.integer(forKey: "lastBatPct"),
                           store.integer(forKey: "lastBatMv"),
                           Date(timeIntervalSince1970: store.double(forKey: "lastBatDate")))
        }
        if store.object(forKey: "restingDate") != nil {
            dongleResting = (store.integer(forKey: "restingPct"),
                             Date(timeIntervalSince1970: store.double(forKey: "restingDate")))
        }
        device.onConnectionChange = { [weak self] c in
            Task { @MainActor in
                self?.connected = c
                if c { await self?.refreshBattery(); await self?.loadKeymap() }
            }
        }
        device.onDongleBattery = { [weak self] pct in
            Task { @MainActor in self?.handleDongleBattery(pct) }
        }
        Task { @MainActor in await self.refreshBattery(); await self.loadKeymap() }
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshBattery() }
        }
        RunLoop.main.add(t, forMode: .common)
        batteryTimer = t
    }

    // MARK: Battery

    func refreshBattery() async {
        let lk = device.currentLink()
        connected = (lk != .none)
        dongleMode = (lk == .dongle)
        if lk == .dongle {
            battery = nil; charging = false; cableSamples.removeAll()
            status = dongleResting != nil ? Loc.shared.tf("status.dongleResting", restingText ?? "")
                                          : Loc.shared.t("status.donglePlug")
            return
        }
        guard lk == .cable else { battery = nil; charging = false; return }
        let b = await device.readBattery()
        battery = b
        if let b {
            cableSamples.append(b.pct)
            if cableSamples.count > 5 { cableSamples.removeFirst() }
            charging = b.pct < 99            // on cable the pack charges; treat ≥99 as full
            lastBattery = (b.pct, b.mv, Date())
            store.set(b.pct, forKey: "lastBatPct")
            store.set(b.mv, forKey: "lastBatMv")
            store.set(Date().timeIntervalSince1970, forKey: "lastBatDate")
            let v = String(format: "%.2f", Double(b.mv) / 1000)
            let p = smoothedCablePct ?? b.pct
            let detail = "\(p)% · \(v)V"
            status = charging ? Loc.shared.tf("status.cableCharging", detail) : Loc.shared.tf("status.cable", detail)
        }
    }

    /// Battery from the dongle's 0x008C channel — a resting reading (no charge load) = truest charge.
    func handleDongleBattery(_ pct: Int) {
        let now = Date()
        dongleResting = (pct, now)
        lastBattery = (pct, 0, now)
        store.set(pct, forKey: "restingPct")
        store.set(now.timeIntervalSince1970, forKey: "restingDate")
        store.set(pct, forKey: "lastBatPct")
        store.set(0, forKey: "lastBatMv")
        store.set(now.timeIntervalSince1970, forKey: "lastBatDate")
        dongleMode = (device.currentLink() == .dongle)
        status = Loc.shared.tf("status.dongleNow", "\(pct)%")
    }

    // MARK: Keymap

    func loadKeymap() async {
        if loading { return }
        loading = true; status = Loc.shared.t("status.readingKeymap")
        defer { loading = false }
        let link = device.currentLink()
        dongleMode = (link == .dongle)
        if link == .dongle {
            connected = true
            status = Loc.shared.t("status.dongleConfigure")
            return
        }
        let bytes = KB.layerCount * KB.matrixRows * KB.matrixCols * 2
        guard let buf = await device.readKeymapBuffer(byteCount: bytes), buf.count >= bytes else {
            connected = device.connected
            status = device.connected ? Loc.shared.t("status.keymapFailed") : Loc.shared.t("status.notConnected")
            return
        }
        var km = keymap
        var i = 0
        for l in 0..<KB.layerCount {
            for r in 0..<KB.matrixRows {
                for c in 0..<KB.matrixCols {
                    km[l][r][c] = (UInt16(buf[i]) << 8) | UInt16(buf[i + 1]); i += 2
                }
            }
        }
        keymap = km
        connected = true
        viaProtocol = await device.getProtocolVersion() ?? viaProtocol
        status = Loc.shared.t("status.keymapLoaded")
    }

    func keycode(_ layer: Int, _ row: Int, _ col: Int) -> UInt16 {
        guard layer < keymap.count, row < keymap[layer].count, col < keymap[layer][row].count else { return 0 }
        return keymap[layer][row][col]
    }

    func setKey(row: Int, col: Int, keycode kc: UInt16) async {
        let layer = selectedLayer
        if await device.setKeycode(layer: layer, row: row, col: col, keycode: kc) {
            keymap[layer][row][col] = kc
            status = "Set \(Keycodes.label(for: kc))"
        } else {
            status = "Set failed"
        }
    }

    func resetKeymap() async {
        status = Loc.shared.t("status.resetting")
        if await device.resetKeymap() {
            await loadKeymap()
            status = Loc.shared.t("status.resetDone")
        } else {
            status = Loc.shared.t("status.resetFailed")
        }
    }

    // MARK: Lighting

    private func clamp(_ v: Int) -> UInt8 { UInt8(max(0, min(255, v))) }

    func loadLighting() async {
        if let v = await device.customGet(value: VIADevice.RGB.effect), !v.isEmpty { rgbEffect = Int(v[0]) }
        if let v = await device.customGet(value: VIADevice.RGB.brightness), !v.isEmpty { rgbBrightness = Int(v[0]) }
        if let v = await device.customGet(value: VIADevice.RGB.speed), !v.isEmpty { rgbSpeed = Int(v[0]) }
        if let v = await device.customGet(value: VIADevice.RGB.color), v.count > 1 { rgbHue = Int(v[0]); rgbSat = Int(v[1]) }
        if device.connected { status = Loc.shared.t("status.lightingLoaded") }
    }

    func setRGBEffect(_ e: Int) async {
        rgbEffect = e
        _ = await device.customSet(value: VIADevice.RGB.effect, data: [clamp(e)])
        status = Loc.shared.t("status.effectSet")
    }

    func setRGBBrightness(_ b: Int) async {
        rgbBrightness = b
        _ = await device.customSet(value: VIADevice.RGB.brightness, data: [clamp(b)])
    }

    func setRGBSpeed(_ s: Int) async {
        rgbSpeed = s
        _ = await device.customSet(value: VIADevice.RGB.speed, data: [clamp(s)])
    }

    func setRGBColor(h: Int, s: Int) async {
        rgbHue = h; rgbSat = s
        _ = await device.customSet(value: VIADevice.RGB.color, data: [clamp(h), clamp(s)])
    }

    func saveLighting() async {
        status = await device.customSave() ? Loc.shared.t("status.lightingSaved") : Loc.shared.t("status.saveFailed")
    }

    // MARK: Macros

    func loadMacros() async {
        guard let count = await device.getMacroCount(), let buf = await device.readMacroBuffer() else {
            status = device.connected ? Loc.shared.t("status.macroReadFailed") : Loc.shared.t("status.notConnected"); return
        }
        macroCount = count
        var segs: [[UInt8]] = []
        var cur: [UInt8] = []
        for b in buf {
            if b == 0 { segs.append(cur); cur = []; if segs.count == count { break } }
            else { cur.append(b) }
        }
        while segs.count < count { segs.append([]) }
        macroRaw = segs
        macros = segs.map { bytes in
            bytes.allSatisfy { $0 >= 0x20 && $0 < 0x7F } ? (String(bytes: bytes, encoding: .ascii) ?? "") : ""
        }
        status = Loc.shared.tf("status.macrosLoaded", count)
    }

    func isAdvancedMacro(_ i: Int) -> Bool {
        guard i < macroRaw.count else { return false }
        return macroRaw[i].contains { $0 < 0x20 || $0 >= 0x7F }
    }

    func setMacroText(_ i: Int, _ text: String) {
        guard i < macros.count else { return }
        macros[i] = text
        macroRaw[i] = Array(text.utf8).filter { $0 >= 0x20 && $0 < 0x7F }
    }

    func saveMacros() async {
        var buf: [UInt8] = []
        for seg in macroRaw { buf.append(contentsOf: seg); buf.append(0) }
        status = await device.writeMacroBuffer(buf) ? Loc.shared.t("status.macrosSaved") : Loc.shared.t("status.macroSaveFailed")
    }
}
