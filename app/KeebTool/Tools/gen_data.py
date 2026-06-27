#!/usr/bin/env python3
"""Generate Swift data files (KeyLayout.swift, Keycodes.swift) from docs/via-spec.json.

The spec is produced by the research workflow (byte-exact, sourced from the QMK repo).
Regenerate after updating the spec:  python3 gen_data.py
"""
import json
import os

ROOT = os.path.realpath(os.path.join(os.path.dirname(__file__), "..", ".."))
SPEC = os.path.join(ROOT, "docs", "via-spec.json")
OUT = os.path.dirname(os.path.realpath(__file__))


def sw(s: str) -> str:
    """Escape a Python string for a Swift double-quoted string literal."""
    return s.replace("\\", "\\\\").replace("\"", "\\\"")


def main() -> None:
    spec = json.load(open(SPEC))
    L = spec["layout"]
    KC = spec["keycodes"]["keycodes"]
    # Macro keycodes (QK_MACRO base 0x7700) — needed to bind a macro to a key; not in the VIA spec table.
    for n in range(16):
        KC.append({"value": "0x%04X" % (0x7700 + n), "name": "MACRO_%d" % n, "label": "M%d" % n, "group": "Macro"})

    # ---- KeyLayout.swift ----
    keys = L["keys"]
    out = [
        "// AUTO-GENERATED from docs/via-spec.json by gen_data.py — do not edit by hand.",
        "import Foundation",
        "",
        "struct KeyDef: Identifiable {",
        "    let id = UUID()",
        "    let label: String",
        "    let x: Double, y: Double, w: Double, h: Double",
        "    let row: Int, col: Int",
        "}",
        "",
        "enum KB {",
        f"    static let layerCount = {L['layer_count']}",
        f"    static let matrixRows = {L['matrix_rows']}",
        f"    static let matrixCols = {L['matrix_cols']}",
        "    static let keys: [KeyDef] = [",
    ]
    for k in keys:
        out.append(
            f'        KeyDef(label: "{sw(k["label"])}", x: {k["x"]}, y: {k["y"]}, '
            f'w: {k["w"]}, h: {k["h"]}, row: {k["row"]}, col: {k["col"]}),'
        )
    out += ["    ]", "}", ""]
    open(os.path.join(OUT, "KeyLayout.swift"), "w").write("\n".join(out))

    # ---- Keycodes.swift ----
    pref = ["Letters", "Numbers", "Punctuation", "Editing", "Fkeys", "Modifiers",
            "Nav", "System", "Media", "Mouse", "RGB", "Layer", "Special"]
    present = {c["group"] for c in KC}
    groups = [g for g in pref if g in present] + sorted(g for g in present if g not in pref)

    out = [
        "// AUTO-GENERATED from docs/via-spec.json by gen_data.py — do not edit by hand.",
        "import Foundation",
        "",
        "struct Keycode: Identifiable, Hashable {",
        "    let value: UInt16",
        "    let name: String",
        "    let label: String",
        "    let group: String",
        "    var id: UInt16 { value }",
        "}",
        "",
        "enum Keycodes {",
        "    static let all: [Keycode] = [",
    ]
    for c in KC:
        out.append(
            f'        Keycode(value: {c["value"]}, name: "{sw(c["name"])}", '
            f'label: "{sw(c["label"])}", group: "{sw(c["group"])}"),'
        )
    out += [
        "    ]",
        "    static let byValue: [UInt16: Keycode] = "
        "Dictionary(all.map { ($0.value, $0) }, uniquingKeysWith: { a, _ in a })",
        "    static let groups: [String] = [" + ", ".join(f'"{g}"' for g in groups) + "]",
        "",
        "    /// Human label for any 16-bit keycode, decoding layer/mod-wrapped values when not in the table.",
        "    static func label(for kc: UInt16) -> String {",
        "        if let k = byValue[kc] { return k.label }",
        "        return LayerKC.decode(kc) ?? String(format: \"0x%04X\", kc)",
        "    }",
        "}",
        "",
    ]
    open(os.path.join(OUT, "Keycodes.swift"), "w").write("\n".join(out))

    print(f"generated KeyLayout.swift ({len(keys)} keys), Keycodes.swift ({len(KC)} codes, groups={groups})")


if __name__ == "__main__":
    main()
