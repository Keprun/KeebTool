import Foundation
import IOKit
import IOKit.hid

/// Raw-HID transport + VIA/Keychron command layer for the Keychron V1 Max.
///
/// The device is scheduled on the main run loop; `transact` is async and resumed by the
/// input-report callback. Callers issue transactions sequentially (await one before the next).
/// All multi-byte values are big-endian. Buffer commands chunk 28 data bytes per report.
final class VIADevice: @unchecked Sendable {
    static let vid = 0x3434
    static let pid = 0x0913
    static let usagePage = 0xFF60
    static let usage = 0x61
    static let reportLen = 32

    enum Cmd {
        static let getProtocolVersion: UInt8 = 0x01
        static let getKeycode: UInt8 = 0x04
        static let setKeycode: UInt8 = 0x05
        static let customSetValue: UInt8 = 0x07
        static let customGetValue: UInt8 = 0x08
        static let customSave: UInt8 = 0x09
        static let macroGetCount: UInt8 = 0x0C
        static let macroGetBufferSize: UInt8 = 0x0D
        static let macroGetBuffer: UInt8 = 0x0E
        static let macroSetBuffer: UInt8 = 0x0F
        static let macroReset: UInt8 = 0x10
        static let getLayerCount: UInt8 = 0x11
        static let getBuffer: UInt8 = 0x12
        static let getEncoder: UInt8 = 0x14
        static let setEncoder: UInt8 = 0x15
        static let getBattery: UInt8 = 0xA4   // Keychron custom (our firmware patch)
        static let unhandled: UInt8 = 0xFF
    }
    static let rgbChannel: UInt8 = 0x03
    enum RGB { static let brightness: UInt8 = 1; static let effect: UInt8 = 2; static let speed: UInt8 = 3; static let color: UInt8 = 4 }

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private let inputBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: reportLen)
    private var statusManager: IOHIDManager?
    private let statusBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    /// Fired when the dongle emits a battery report on the 0x008C channel (event-driven).
    var onDongleBattery: ((Int) -> Void)?
    private var pending: CheckedContinuation<[UInt8]?, Never>?
    private var pendingCmd: UInt8 = 0
    private var token = 0
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    enum Link { case none, cable, dongle, other }
    private(set) var link: Link = .none
    private(set) var connected = false
    var onConnectionChange: ((Bool) -> Void)?

    init() { setupManager(); setupStatusListener() }

    // MARK: - Device lifecycle

    private func setupManager() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        // Match by vendor + raw-HID usage only (NO product id) so BOTH the wired keyboard
        // (PID 0x0913) and the 2.4GHz "Keychron Link" dongle (PID 0xD030) are picked up.
        let match: [String: Any] = [
            kIOHIDVendorIDKey: Self.vid,
            kIOHIDDeviceUsagePageKey: Self.usagePage,
            kIOHIDDeviceUsageKey: Self.usage,
        ]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, _ in
            guard let context = context else { return }
            Unmanaged<VIADevice>.fromOpaque(context).takeUnretainedValue().deviceArrived()
        }, ctx)
        IOHIDManagerRegisterDeviceRemovalCallback(mgr, { context, _, _, _ in
            guard let context = context else { return }
            Unmanaged<VIADevice>.fromOpaque(context).takeUnretainedValue().deviceRemoved()
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        manager = mgr
    }

    // MARK: - Dongle battery channel (usage page 0x008C) — Keychron emits battery here over 2.4G
    private func setupStatusListener() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let match: [String: Any] = [
            kIOHIDVendorIDKey: Self.vid,
            kIOHIDDeviceUsagePageKey: 0x8C,
            kIOHIDDeviceUsageKey: 0x01,
        ]
        IOHIDManagerSetDeviceMatching(mgr, match as CFDictionary)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(mgr, { context, _, _, dev in
            guard let context = context else { return }
            Unmanaged<VIADevice>.fromOpaque(context).takeUnretainedValue().registerStatusInput(dev)
        }, ctx)
        IOHIDManagerScheduleWithRunLoop(mgr, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        statusManager = mgr
    }

    private func registerStatusInput(_ dev: IOHIDDevice) {
        IOHIDDeviceOpen(dev, IOOptionBits(kIOHIDOptionsTypeNone))
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(dev, statusBuf, 64, { context, _, _, _, _, report, length in
            guard let context = context else { return }
            Unmanaged<VIADevice>.fromOpaque(context).takeUnretainedValue().handleStatus(report, length)
        }, ctx)
    }

    private func handleStatus(_ report: UnsafeMutablePointer<UInt8>, _ length: CFIndex) {
        guard length >= 1 else { return }
        let pct = Int(report[0])      // observed: byte0 = battery % (e.g. 84) on the 0x008C report
        if pct >= 1 && pct <= 100 { onDongleBattery?(pct) }
    }

    @discardableResult
    private func ensureOpen() -> Bool {
        if device != nil { return true }
        guard let mgr = manager,
              let set = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>,
              !set.isEmpty else { setConnected(false); return false }
        func pidOf(_ dev: IOHIDDevice) -> Int { (IOHIDDeviceGetProperty(dev, kIOHIDProductIDKey as CFString) as? Int) ?? 0 }
        // When both the wired keyboard (0x0913) and the 2.4GHz dongle (0xD030) are plugged in,
        // prefer the cable — the dongle's raw-HID interface is a dead end.
        let d = set.first { pidOf($0) == 0x0913 } ?? set.first { pidOf($0) == 0xD030 } ?? set.first!
        IOHIDDeviceOpen(d, IOOptionBits(kIOHIDOptionsTypeNone))
        let pid = pidOf(d)
        link = (pid == 0x0913) ? .cable : (pid == 0xD030 ? .dongle : .other)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        IOHIDDeviceRegisterInputReportCallback(d, inputBuf, Self.reportLen, { context, _, _, _, _, report, length in
            guard let context = context else { return }
            Unmanaged<VIADevice>.fromOpaque(context).takeUnretainedValue().handleInput(report, length)
        }, ctx)
        device = d
        setConnected(true)
        return true
    }

    private func setConnected(_ v: Bool) {
        if connected != v { connected = v; onConnectionChange?(v) }
    }

    /// Fired by IOKit when a matching device (cable or dongle) is plugged in / switched.
    private func deviceArrived() {
        device = nil          // drop any stale handle; re-acquire the fresh one on next transaction
        connected = true
        onConnectionChange?(true)
    }

    private func deviceRemoved() {
        device = nil
        link = .none
        connected = false
        onConnectionChange?(false)
    }

    /// Open (if needed) and report which physical link the keyboard is on.
    func currentLink() -> Link {
        _ = ensureOpen()
        return link
    }

    private func handleInput(_ report: UnsafeMutablePointer<UInt8>, _ length: CFIndex) {
        guard let cont = pending else { return }
        let n = min(Int(length), Self.reportLen)
        var resp = [UInt8](repeating: 0, count: Self.reportLen)
        for i in 0..<n { resp[i] = report[i] }
        // Match the echoed command id (or 0xFF unhandled); ignore stale/unrelated reports.
        guard resp[0] == pendingCmd || resp[0] == Cmd.unhandled else { return }
        pending = nil
        token &+= 1
        cont.resume(returning: resp)
    }

    // MARK: - Core transaction

    /// Send a 32-byte payload (payload[0] = command id) and await the 32-byte response.
    /// Returns nil on send failure, disconnect, or timeout.
    /// Async mutex so concurrent callers (battery timer, UI actions) don't interleave reports.
    private func lock() async {
        if !busy { busy = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    private func unlock() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    func transact(_ payload: [UInt8], timeoutMs: Int = 800) async -> [UInt8]? {
        await lock()
        defer { unlock() }
        guard ensureOpen(), let d = device else { return nil }
        var buf = payload
        if buf.count < Self.reportLen { buf += [UInt8](repeating: 0, count: Self.reportLen - buf.count) }
        else if buf.count > Self.reportLen { buf = Array(buf.prefix(Self.reportLen)) }
        let cmd = buf[0]
        return await withCheckedContinuation { (cont: CheckedContinuation<[UInt8]?, Never>) in
            self.pending = cont
            self.pendingCmd = cmd
            let myToken = self.token
            let res = buf.withUnsafeBufferPointer {
                IOHIDDeviceSetReport(d, kIOHIDReportTypeOutput, 0, $0.baseAddress!, Self.reportLen)
            }
            if res != kIOReturnSuccess {
                if self.pending != nil, self.token == myToken {
                    self.pending = nil; self.token &+= 1
                    self.device = nil; self.setConnected(false)
                    cont.resume(returning: nil)
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(timeoutMs)) {
                if self.pending != nil, self.token == myToken {
                    self.pending = nil; self.token &+= 1
                    cont.resume(returning: nil)
                }
            }
        }
    }

    // MARK: - Keymap

    func getLayerCount() async -> Int? {
        guard let r = await transact([Cmd.getLayerCount]), r[0] == Cmd.getLayerCount else { return nil }
        return Int(r[1])
    }

    func getProtocolVersion() async -> Int? {
        guard let r = await transact([Cmd.getProtocolVersion]), r[0] == Cmd.getProtocolVersion else { return nil }
        return (Int(r[1]) << 8) | Int(r[2])
    }

    /// Reset the entire dynamic keymap to the firmware default (VIA id_dynamic_keymap_reset = 0x06).
    func resetKeymap() async -> Bool {
        await transact([0x06])?[0] == 0x06
    }

    func getKeycode(layer: Int, row: Int, col: Int) async -> UInt16? {
        guard let r = await transact([Cmd.getKeycode, UInt8(layer), UInt8(row), UInt8(col)]),
              r[0] == Cmd.getKeycode else { return nil }
        return (UInt16(r[4]) << 8) | UInt16(r[5])
    }

    func setKeycode(layer: Int, row: Int, col: Int, keycode: UInt16) async -> Bool {
        let r = await transact([Cmd.setKeycode, UInt8(layer), UInt8(row), UInt8(col),
                                UInt8(keycode >> 8), UInt8(keycode & 0xFF)])
        return r?[0] == Cmd.setKeycode
    }

    func getEncoder(layer: Int, index: Int, clockwise: Bool) async -> UInt16? {
        guard let r = await transact([Cmd.getEncoder, UInt8(layer), UInt8(index), clockwise ? 1 : 0]),
              r[0] == Cmd.getEncoder else { return nil }
        return (UInt16(r[4]) << 8) | UInt16(r[5])
    }

    func setEncoder(layer: Int, index: Int, clockwise: Bool, keycode: UInt16) async -> Bool {
        let r = await transact([Cmd.setEncoder, UInt8(layer), UInt8(index), clockwise ? 1 : 0,
                                UInt8(keycode >> 8), UInt8(keycode & 0xFF)])
        return r?[0] == Cmd.setEncoder
    }

    /// Bulk-read the raw keymap buffer (big-endian keycodes, ordered layer/row/col), 28 bytes per transfer.
    func readKeymapBuffer(byteCount: Int) async -> [UInt8]? {
        var out = [UInt8](); out.reserveCapacity(byteCount)
        var offset = 0
        while offset < byteCount {
            let size = min(28, byteCount - offset)
            guard let r = await transact([Cmd.getBuffer, UInt8((offset >> 8) & 0xFF), UInt8(offset & 0xFF), UInt8(size)]),
                  r[0] == Cmd.getBuffer else { return nil }
            out.append(contentsOf: r[4..<(4 + size)])
            offset += size
        }
        return out
    }

    // MARK: - Macros

    func getMacroCount() async -> Int? {
        guard let r = await transact([Cmd.macroGetCount]), r[0] == Cmd.macroGetCount else { return nil }
        return Int(r[1])
    }

    func getMacroBufferSize() async -> Int? {
        guard let r = await transact([Cmd.macroGetBufferSize]), r[0] == Cmd.macroGetBufferSize else { return nil }
        return (Int(r[1]) << 8) | Int(r[2])
    }

    func readMacroBuffer() async -> [UInt8]? {
        guard let size = await getMacroBufferSize(), size > 0 else { return nil }
        var out = [UInt8](); out.reserveCapacity(size)
        var offset = 0
        while offset < size {
            let chunk = min(28, size - offset)
            guard let r = await transact([Cmd.macroGetBuffer, UInt8((offset >> 8) & 0xFF), UInt8(offset & 0xFF), UInt8(chunk)]),
                  r[0] == Cmd.macroGetBuffer else { return nil }
            out.append(contentsOf: r[4..<(4 + chunk)])
            offset += chunk
        }
        return out
    }

    /// Write the entire macro buffer. Uses VIA's in-progress flag (last byte non-zero during write).
    func writeMacroBuffer(_ data: [UInt8]) async -> Bool {
        guard let size = await getMacroBufferSize(), size > 0 else { return false }
        var buf = data
        if buf.count > size { buf = Array(buf.prefix(size)) }
        if buf.count < size { buf += [UInt8](repeating: 0, count: size - buf.count) }
        buf[size - 1] = 0 // VIA reserves the last byte as the valid flag (0 = ready)

        // 1. mark in-progress
        let mark = await transact([Cmd.macroSetBuffer, UInt8(((size - 1) >> 8) & 0xFF), UInt8((size - 1) & 0xFF), 1, 0xFF])
        guard mark?[0] == Cmd.macroSetBuffer else { return false }
        // 2. write all chunks (the final chunk re-writes the last byte as 0, clearing the flag)
        var offset = 0
        while offset < size {
            let chunk = min(28, size - offset)
            let payload = [Cmd.macroSetBuffer, UInt8((offset >> 8) & 0xFF), UInt8(offset & 0xFF), UInt8(chunk)] + Array(buf[offset..<offset + chunk])
            guard await transact(payload)?[0] == Cmd.macroSetBuffer else { return false }
            offset += chunk
        }
        return true
    }

    func resetMacros() async -> Bool {
        await transact([Cmd.macroReset])?[0] == Cmd.macroReset
    }

    // MARK: - Lighting (QMK RGB matrix custom channel = 3)

    func customGet(value: UInt8) async -> [UInt8]? {
        guard let r = await transact([Cmd.customGetValue, Self.rgbChannel, value]),
              r[0] == Cmd.customGetValue else { return nil }
        return Array(r[3..<Self.reportLen])
    }

    func customSet(value: UInt8, data: [UInt8]) async -> Bool {
        let r = await transact([Cmd.customSetValue, Self.rgbChannel, value] + data)
        return r?[0] == Cmd.customSetValue
    }

    func customSave() async -> Bool {
        await transact([Cmd.customSave, Self.rgbChannel])?[0] == Cmd.customSave
    }

    // MARK: - Battery (our 0xA4 patch)

    func readBattery() async -> (pct: Int, mv: Int)? {
        guard let r = await transact([Cmd.getBattery]), r[0] == Cmd.getBattery else { return nil }
        return (Int(r[1]), Int(r[2]) | (Int(r[3]) << 8))
    }
}
