# Horizon iOS: SwiftUI launcher + native Rust engine bridge

The previous experimental binary initialized winit immediately and users
observed a gray rectangle on iOS 27. This branch creates a **separate native
SwiftUI application** which runs Apple's scene lifecycle and links a Rust
static library built for `aarch64-apple-ios`.

## Current, testable functionality

- Native SwiftUI home navigation (Home / Worlds / Settings) and responsive
  landscape iPhone layout, written in Swift without shipped Minecraft assets.
- A real Rust `horizon-ios-bridge` static library linked into the app;
  `horizon_ios_resources_status()` calls `horizon_client::assets::Assets::load`,
  which checks the actual prepared game data, not a dummy string.
- Import a **folder** prepared on the player's own computer for Horizon Java
  Edition 26.3, using iOS Files and a security-scoped document picker.
- Files go to the app's `Documents/Horizon/resources/` sandbox directory.
- Preserved singleplayer/multiplayer engine source in Rust.

## Important: gameplay is not wired yet

`Game::run` is in the old desktop executable at
`crates/horizon-client/src/game.rs`, using `winit::EventLoop::run_app`. On iOS,
that attempts to own UIApplicationMain and cannot be launched within an
already-running SwiftUI scene. The **next milestone** is extracting the game
simulation/controller/render lifecycle from that binary into a library that
renders on an owned `CAMetalLayer` via `wgpu`, with SwiftUI/UIView handing
size, input and foreground/background events into Rust.

This branch does **not** claim to play Minecraft yet. The Worlds screen and
performance controls are visibly labeled as not integrated; they deliberately
do not pretend to execute a world. In-app modification/install of Java mods is
out of scope.

The user's prepared resources are not shipped in GitHub releases or bundled
into the IPA. Never commit proprietary Mojang content, credentials or
prepared `.local` data to GitHub.

## Build

Use the **iOS SwiftUI launcher + Rust bridge** GitHub Actions workflow on
`ios/swiftui-launcher`. It builds a Rust `staticlib`, uses XcodeGen to
construct a native SwiftUI app, and creates an unsigned IPA artifact.
Sideloading requires valid signing and provisioning for the user's device.

The previous Rust-only native engine workflow remains on the parent branch.
