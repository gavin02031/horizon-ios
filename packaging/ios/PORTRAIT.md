# iPhone 15 portrait launcher / separate Metal scene

The SwiftUI launcher presents in portrait with edge-to-edge dark/navy
background and safe-area-aware content. Home, Worlds, Files and Settings use
a bottom tab bar. Settings categories are independent NavigationStack pages
with a Back button, not squished sidebar items. The landscape Metal GPU/input
test remains a separate fullScreenCover, requests an orientation change via
UIWindowScene.requestGeometryUpdate, then returns to portrait.

## Source of truth for game readiness
- The iOS app does **not** have a Microsoft sign-in flow or entitlement check.
  The original desktop launcher can sign in, but auth is not transferred to iOS.
- "Java Edition 26.3" is the **game data version**, not a Java VM installed on
  the phone. Horizon is ahead-of-time compiled native Rust without JIT.
- The only current validation is Assets::load over the imported prepared
  resource directory. It does not verify the full renderer, world saves,
  Microsoft ownership, shader assets or a successful game session.
- The fullScreenCover is a Rust wgpu / Metal *diagnostic*. It does **not**
  run the existing desktop Game::run simulation or render its terrain.
- Actual game play requires decoupling game.rs from winit's ApplicationHandler
  and gfx::Renderer from Arc<Window>. No finished "Play Minecraft" action
  is exposed until that wiring actually exists.

## Verification
- Cross-compile with the iOS SwiftUI workflow.
- Physically test device upright Home/Settings, safe areas, import and full
  screen portrait-to-landscape Metal diagnostic and rotation back.
- On iOS some system orientation-lock policies may reject the scene geometry
  request; do not assume a successful compilation proves rotation.

## Install/build identification
The signed or unsigned IPA from this branch is labelled **Horizon iOS
0.4.0**, bundle `com.gavin02031.horizonios.swiftui`, build channel
`portrait-metal-test`. It is distinct from the older gray-screen Rust-only
IPA (`com.gavin02031.horizonios`). GitHub Actions verifies the bundle ID,
SwiftUI dynamic framework link, build channel, version and ARM64 architecture
before publishing the artifact.

Because the new SwiftUI bundle ID uses a **different sandbox**, resource files
imported into the old Rust-only app do not migrate automatically. Import your
prepared resources again from Files; do not delete the old app until you have
copied any data you want to preserve. No passwords/tokens are imported.

## Full-screen sizing fix (v0.4.1)

A portrait screenshot from an iPhone 15 showed the entire SwiftUI viewport
letterboxed with black bands above and below. The project's hand-authored
`Info.plist` lacked the `UILaunchScreen` key, and XcodeGen disables automatic
Info.plist generation, so there was no generated launch screen either.

This patch adds the standard empty `UILaunchScreen` dictionary used in
modern SwiftUI templates and verifies that it survives Xcode's packaging.
Portrait launch and landscape Metal test orientations remain supported,
with the existing UIKit scene geometry requests preserved.

**Validation:** a successful CI build is not a physical-device sizing test.
If installed over an old IPA and letterboxing persists, preserve/copy any
Documents from the installed app, remove that version, then sideload v0.4.1
afresh and take a new screenshot. Deleting an app can delete its sandbox files.

The app uses its own `com.gavin02031.horizonios.swiftui` bundle identifier,
not the prior legacy Rust-only `com.gavin02031.horizonios` app.
