# Assets

Every file here was authored in this repository. Nothing is downloaded, so nothing carries a
third-party licence, an attribution requirement or a "not for commercial use" clause into the app's
store listing — which is the kind of thing that surfaces during review, not before it.

Two scripts reproduce all of it. Both need only Pillow and the standard library:

```
python3 tool/make_icons.py     # the PNGs
python3 tool/make_sounds.py    # the WAVs
python3 tool/preview_svg.py    # tool/preview.png — a contact sheet of the SVGs, for looking at
```

The SVGs are hand-authored and edited by hand; the scripts do not generate them.

## Where each file comes from

| File | Provenance |
|---|---|
| `images/launcher_icon.png` | the fleet's mark, mask taken from `mobile/assets/images/launcher_icon.png`'s alpha, painted white on `#742CE7` |
| `images/launcher_icon_foreground.png` | same mark, adaptive-safe-zone framing from `mobile/.../launcher_icon_foreground.png`, painted white |
| `images/mark_purple.png` | same, painted `#742CE7` — for in-app lockups on white |
| `images/splash_logo.png` | the purple mark cropped to its ink and re-padded at 8%, 512² |
| `images/notification_icon.png` | the white silhouette at 96²; Android tints this itself, so its colour does not matter |
| `images/waiting_room.svg` | drawn here |
| `images/waiting_room_ripple.svg` | drawn here |
| `images/empty_chats.svg`, `empty_coops.svg`, `empty_calls.svg` | drawn here |
| `images/state_offline.svg`, `state_error.svg` | drawn here |
| `sounds/join.wav`, `knock.wav`, `ringback.wav` | synthesised by `tool/make_sounds.py` |

The launcher icon deliberately reuses the existing Communal mark rather than introducing a new one.
The member app and the collector app already ship that mark and differ only in tint —
`collector_mobile/pubspec.yaml` explains the convention — so Meet takes the same geometry and
inverts the ground instead of adding a fourth tint. `DESIGN.md` §9 has the reasoning.

## Wiring it up (step 5, when the Flutter project is scaffolded)

`pubspec.yaml`:

```yaml
flutter_launcher_icons:
  android: true
  ios: true
  remove_alpha_ios: true
  image_path: "assets/images/launcher_icon.png"
  background_color_android: "#742CE7"
  adaptive_icon_background: "#742CE7"
  adaptive_icon_foreground: "assets/images/launcher_icon_foreground.png"
  min_sdk_android: 21

flutter:
  assets:
    - assets/images/
    - assets/sounds/
```

Then `dart run flutter_launcher_icons`, as the other two apps do.

The five 48² glyphs are stroked in `currentColor`, so they are recoloured at the call site with
`SvgPicture.asset(..., colorFilter: ColorFilter.mode(AppColors.muted, BlendMode.srcIn))`. They are
only ever used on light surfaces.

`waiting_room.svg` is intentionally just the door: the knock ripples are the separate
`waiting_room_ripple.svg`, drawn three times in a `Stack` and animated, because `flutter_svg`
renders a file statically and motion baked into one SVG would be motion nobody can play. The
ripple's viewBox is symmetric about its own origin, so it scales about its centre with no alignment
arithmetic; position that centre on the door's right edge, `(156, 104)` in the door's coordinate
space. `DESIGN.md` §9 gives the timings.

## Not verified

The WAVs are checked structurally — 16kHz mono 16-bit, first and last sample at zero, no
discontinuity beyond the waveform's own slope, so neither edge clicks — but nobody has listened to
them. If a tone is unpleasant, `tool/make_sounds.py` is four frequency constants and a gain.
