# Battery over the 2.4 GHz dongle — findings

Goal: read the V1 Max battery on the Mac while the keyboard runs on the **2.4 GHz
dongle** (not cable), ideally refreshable on demand (e.g. via Fn+B).

**Verdict: on-demand battery over the dongle is not achievable.** It is a hardware
limitation of the closed dongle firmware, not a gap in our code. Reliable, exact,
live battery requires the USB cable.

## How battery actually flows

```
keyboard MCU --(SPI, LKBT51 cmd 0x32 UPDATE_BAT_LVL)--> radio module --(RF)--> dongle --(USB HID 0x008C)--> host
```

- The keyboard only *pushes* battery into its radio module (it never emits the
  `0x008C` HID report itself — that report is synthesized by the dongle).
- The dongle decides when to forward a `0x008C` report to the host. Empirically it
  does so **only at RF (re)connect**, not on mid-session pushes.
- There is **no host→device query path** over 2.4 GHz.

## What we tried (all on awake hardware)

| Probe | Result |
|---|---|
| raw-HID `0xFF60` over dongle (VIA `0x01`, custom `0xA4`) | **TIMEOUT** — dongle exposes the descriptor but does not bridge the command/response channel |
| `GET_FEATURE` on `0x008C`, report IDs 0–7 | error `0xE0005000` |
| `GetReport(Input)` on `0x008C`, report IDs 0–7 | error `0xE0005000` |
| Output/request reports on `0x008C` | no response |
| Reopen `0x008C` repeatedly (poll for cached value) | nothing |
| Firmware periodic push every ~3 s (`battery.c`) | no host-visible report |
| Firmware Fn+B push (`lkbt51_update_bat_lvl`) | animation fires, **no host report** |
| Firmware Fn+B **value-wiggle** (push `pct±1` then `pct` to defeat on-change dedup) | **no host report** — dongle still does not forward mid-session |
| Switch **Cable → 2.4G** (fresh RF connect) | **`[84, 226, 1, 1, 0…]` — byte0 = battery %** ✅ |
| Switch **2.4G → Off → 2.4G** | did **not** reliably re-emit |

The only capture we ever obtained was on a cold RF connect. byte0 of the `0x008C`
report is the battery percentage (our dongle PID `0xD030`; note the M3 mouse dongle
`0xD034` uses a different `[00|01][PCT][02][02]` marker layout).

Cross-checked against a 3-agent investigation of byte-bandit/keychron-m3-linux
(passive `read()` only, never writes — same model), the Keychron QMK `wireless_playground`
source, and web protocol notes. All agree: **push-only, listen-to-receive, no query.**

## What works

| Path | Battery | Precision | On demand |
|---|---|---|---|
| **Cable** (raw-HID `0xA4`) | instant | exact % + voltage (mV) | yes |
| **Dongle** (`0x008C`) | opportunistic, at RF connect | integer % | no |
| **Fn+B on keyboard** | colour gauge on the board itself | coarse (red/amber/green) | yes — but on the keyboard, not the Mac |

## App behaviour (consequence)

The app passively listens on `0x008C` (VID `0x3434`, PID `0xD030`, usage page `0x8C`),
parses `report[0]` as the percentage, caches the last value with a timestamp, and shows
`~NN% · <time ago>` in dongle mode. It updates whenever the dongle volunteers a report
(i.e. on connect). For a live exact reading at any moment, connect the cable.
