# Caption, splash, and interaction presentation

## Text surfaces

Settled panels, captions, buttons, keycaps, cards, tooltips and keyboard/print
banners have opaque backgrounds. Hover and selection colours use `Qt.tint`
over the solid theme background instead of reducing the surface alpha.
Disabled buttons use muted text and a subdued solid fill, not whole-button
opacity. Intro text prompts and capture practice cards follow the same rule.
Decorative shadows, desktop highlights and deliberate transition fades retain
their transparency. The surface regression renders the production components
over changing backgrounds, including hovered and disabled controls.
Titled button tooltips use a semibold heading and a 6-pixel, text-scaled gap
before the description. Label-only tooltips do not reserve an empty body or gap.

## Splash and startup

The splash restores the original illustrated poster: Ohm hovering beside a
three-pane desktop, Ollie perched on its corner, and the large Learn Omarchy
title above. `SplashArtwork` displays `assets/splash/learn-omarchy-poster.png`
with aspect-fit scaling, smoothing and mipmaps appropriate for an illustration,
not a sprite sheet. It fills the available screen above the loading hint without
cropping either mascot or the title. The surrounding navy background is
independent of the user's desktop theme.

The shell supplies an absolute, URL-encoded `file://` source from `appRoot`.
Do not use `Qt.resolvedUrl("../assets/...")` here: Quickshell's intercepted QML
URLs cannot resolve assets outside the configuration directory and redirect
that request to `qrc:/qs-blackhole`. The startup regression runs under real
Quickshell as well as the standalone QML component tests.

Startup fades the splash out over 650 ms with sine easing. For a returning
learner, the already-composed Lessons picker is revealed directly when that
fade finishes instead of running a second entrance animation. Destinations that
must wait for an intro or fallback frame still fade in over 750 ms.
The splash layer retains its navy background behind the fading poster and stays
mapped as a solid cover until the destination has finished appearing. The
destination window starts with that same opaque background, then makes it
transparent as its content appears; the compositor never exposes a desktop
frame between the two layer surfaces.
The UI window and separate coach/intro
window share `startupOpacity`, so neither appears abruptly over the other.
For entrances, the reveal waits for `IntroPlayer` to reach `playing` or
`fallback`; cancellation also releases a pending reveal. Pickers and errors
reveal immediately after the splash exits. This runs only at startup, not
when switching lessons or replaying Welcome. Reduced motion bypasses both
stages, including when enabled partway through a transition.

The Lessons picker reuses the already-watched current Omarchy wallpaper as an
aspect-cropped backdrop beneath its opaque panel. A light theme-colored shade
keeps the picker prominent without exposing distracting open windows. Starting
a lesson fades the wallpaper away over 300 ms to reveal the real desktop needed
for hands-on teaching; reduced motion removes that transition. Settings opened
from the picker retain the backdrop, while settings opened during a lesson do
not restore it. An opaque theme-color fallback remains behind the picker until
the wallpaper is decoded, so image loading cannot introduce a desktop flash.

Both mascots are app branding, not a preview or change of the selected coach.
The selected pack still owns the entrance animation, lesson sprites and voice.
Load errors emit `imageFailed`, log a warning through the shell, and leave a
neutral title. They neither block startup nor change the image's visibility.

Regenerate with `node tools/prepare-splash-poster.mjs` (requires FFmpeg).
The original `learn-omarchy.png` is retained unchanged. Local hue corrections
match Ohm's accents and Ollie's scarf to magenta and change the orange boot
flames to magenta while retaining cyan exhaust. The original shading, desktop,
lettering and composition remain intact. `poster.provenance.json` records
source/output hashes, the operation and the original CC BY 4.0 attribution.

`WordRevealText` uses `revealEnd` to make each spoken word visible while retaining
the complete caption for wrapping, stable dimensions and accessibility. The
unrevealed suffix is transparent styled text, so welcome, tour, instruction,
completion and wrap-up captions all follow the same narration clock without
reflowing the panel. If that clock is unavailable, `CaptionReveal` continues at
reading speed instead of flashing the whole paragraph. The **Reveal captions as
spoken** preference controls this behavior; turning it off shows complete captions
immediately. Reduced-motion mode also shows complete captions. The existing
`typeText` settings key is retained for preference compatibility.

## Intro artwork

Ohm's pack now selects half-resolution, nearest-neighbour samples of its existing
closed/open rocket artwork. Both frames use the same 140 × 320 sampling grid,
giving approximately 1.7 logical pixels per sample at the standard 540-pixel
intro height, closer to the coach's visible pixel detail. The generic image
renderer explicitly disables smoothing and mipmaps, just like `CharacterSprite`.
This is a sampling improvement, not a redraw or a promise of identical pixel
density at every viewport size.

The original palette and alpha are retained without adding interpolated colours.
Both layers explicitly retain the original 279:640 aspect ratio, so the hatch,
character handoff, landing alignment, timing and viewport clamps are unchanged.
The original PNGs remain available as sources; selection of the sampled frames
lives in the character pack's sequence, not character-specific application code.

Regenerate with `node tools/prepare-intro-pixels.mjs` (requires FFmpeg).
Source/output hashes and sampling provenance are stored alongside the pack's
sprites in `intro-pixels.provenance.json`. The sampled art retains CC BY 4.0.

## Interaction cues

`InteractionAudio` uses the existing Effects volume and master mute. Bind:

```qml
InteractionAudio {
    id: interactionAudio
    appRoot: root.appRoot
    enabled: root.audioEnabled && root.effectsEnabled
    volume: root.effectsVolume
    paused: root.phase === "paused"
    suspended: root.phase === "settings"
        || root.introActive || root.welcomeStage !== ""
}
```

Call `notify("correct")` only for accepted learner actions, `notify("wrong")`
only for a deliberately submitted incorrect shortcut, `notify("step-complete")`
for verified step completion, and `notify("module-complete")` for module
completion. Do not signal on arbitrary desktop keys, hints, skips, replays or
navigation. Call `stop()` when leaving/resetting a lesson or shutting down.
`play(kind)` is an equivalent standalone entry point; both return whether the
cue was accepted. Motion preferences do not mute interaction audio.

The 65 ms coalescing window replaces an action cue with the resulting completion.
Priority is module > step > action; repeated wrong chords have a 650 ms debounce.
There is only one playback process, and preemption waits for its actual exit.
Muted, zero-volume or suspended playback cancels both pending and active cues.
Narration uses a separate channel and is never stopped by an interaction cue.
`playbackEnabled: false` is a test-only scheduling seam: it emits `cueStarted`
and simulates clip duration without touching an audio device.
Playback failures emit `playbackFailed(kind, message)`, update `lastError`, and
log a warning without blocking lesson progression. A 1.5-second startup deadline
also recovers a missing player; intentional cancellation is not an error.

Regenerate the four original mono 48 kHz/16-bit WAV files with:

```sh
node tools/generate-interaction-sounds.mjs
```

The generator uses deterministic additive sine synthesis, restrained harmonics,
12 ms attacks, 50 ms releases and a -19.2 dBFS peak ceiling. No sampled,
downloaded, or third-party sounds are used. The WAV assets are covered by the
project's CC BY 4.0 artwork/sound licence; the generator is MIT-licensed source.
`tests/interaction-sounds.test.ts` verifies byte-for-byte reproducibility, peak,
RMS, format, duration and soft edges. `tst_interaction_audio.qml` tests scheduling
without live audio; the splash and text fixtures run offscreen.
