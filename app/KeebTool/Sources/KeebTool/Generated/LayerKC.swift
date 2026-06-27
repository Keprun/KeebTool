import Foundation

/// Encode/decode QMK layer-switch and mod/layer-tap keycodes.
/// Bit layouts verified against quantum/keycodes.h (see docs/via-spec.json -> keycodes.layer_keycode_encoding).
enum LayerKC {
    // Simple layer keys: base + layer (layer 0..31)
    static func MO(_ n: Int) -> UInt16 { 0x5220 &+ UInt16(n & 0x1F) }   // momentary
    static func TG(_ n: Int) -> UInt16 { 0x5260 &+ UInt16(n & 0x1F) }   // toggle
    static func TO(_ n: Int) -> UInt16 { 0x5200 &+ UInt16(n & 0x1F) }   // activate
    static func OSL(_ n: Int) -> UInt16 { 0x5280 &+ UInt16(n & 0x1F) }  // one-shot
    static func DF(_ n: Int) -> UInt16 { 0x5240 &+ UInt16(n & 0x1F) }   // default layer
    static func TT(_ n: Int) -> UInt16 { 0x52C0 &+ UInt16(n & 0x1F) }   // tap-toggle

    // Composite: hold = layer, tap = basic keycode (layer 0..15, kc = 8-bit basic)
    static func LT(_ layer: Int, _ kc: UInt16) -> UInt16 { 0x4000 | (UInt16(layer & 0xF) << 8) | (kc & 0xFF) }
    // Mod-tap: hold = mods, tap = basic keycode (mod = 5-bit MOD_MASK)
    static func MT(_ mod: Int, _ kc: UInt16) -> UInt16 { 0x2000 | (UInt16(mod & 0x1F) << 8) | (kc & 0xFF) }

    /// Human label for layer/mod-wrapped keycodes; nil if not one of these ranges.
    static func decode(_ kc: UInt16) -> String? {
        func basicLabel(_ v: UInt16) -> String { Keycodes.byValue[v & 0xFF]?.label ?? String(format: "0x%02X", v & 0xFF) }
        switch kc {
        case 0x5200...0x521F: return "TO(\(kc - 0x5200))"
        case 0x5220...0x523F: return "MO(\(kc - 0x5220))"
        case 0x5240...0x525F: return "DF(\(kc - 0x5240))"
        case 0x5260...0x527F: return "TG(\(kc - 0x5260))"
        case 0x5280...0x529F: return "OSL(\(kc - 0x5280))"
        case 0x52C0...0x52DF: return "TT(\(kc - 0x52C0))"
        case 0x4000...0x4FFF: return "LT(\((kc >> 8) & 0xF), \(basicLabel(kc)))"
        case 0x2000...0x2FFF: return "MT(\(basicLabel(kc)))"
        default: return nil
        }
    }
}
