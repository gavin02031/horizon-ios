# Native Horizon iOS: engineering first pass

**Goal:** port the existing Rust Minecraft Java Edition game engine to an iPhone 15
using native AArch64 machine code and Metal. No Java VM, Java bytecode interpreter,
JIT, cloud streaming or emulation in the runtime.

**Current status:** experimental cross-compilation prototype only. It is NOT
yet certified playable, and the presence of an IPA artifact alone does not
establish that it launches, renders, accepts touch input or plays worlds on iOS 27.

## What the branch actually does

- Adds the separate `horizon-ios` binary using Horizon's **existing gameplay
  code** (`game.rs`) rather than creating a fake title screen.
- Uses `wgpu`'s Metal backend on iOS.
- Disables desktop-oriented `audio` and `controllers` feature dependencies in
  this initial build; there is currently no iOS audio or gamepad backend.
- Uses the sandbox path `Documents/Horizon/` as the current working directory:
  saves and `options.txt` live there.
- Expects prepared *user-owned* Minecraft Java Edition 26.3 resources in
  `Documents/Horizon/resources/`. The app creates a symlink to that folder from
  Horizon's default resource location.
- Builds using a hosted macOS GitHub Actions runner, so the developer may
  trigger it from Windows. On success, produces an experimental **unsigned**
  IPA artifact without Mojang assets, and without a Java runtime.

## Current blocking issues

1. **iOS 27 UIKit scene lifecycle:** the desktop game's `winit 0.30` app
   delegate may not satisfy iOS 27's UIScene requirement. A compatible scene
   delegate/window integration or newer validated `winit` integration is needed.
   A successful cross-compile is **not** an on-device launch test.
2. **Touch UI and input:** add iOS multitouch handling and native-feeling
   virtual sticks, break/place buttons, hotbar and inventory controls.
3. **GPU/device compatibility:** verify drawable creation, Metal capabilities,
   texture-array limits and frame pacing on iPhone 15. The existing wgpu
   shader pipelines may need device-specific changes.
4. **Resource import and diagnostics:** the first prototype assumes files
   were prepared externally; it needs an iOS importer and a clear missing-files
   screen before release.
5. **Audio, physical controllers, lifecycle:** implement AVAudioSession/engine
   output, Apple GameController input, background/foreground saves and cleanup.
6. **Performance:** measure on-device before promising FPS. A Rust rewrite
   does not guarantee better frame rates on A16; world generation, GPU bandwidth
   and memory pressure remain constraints.
7. **On-device verification:** test actual world load/save, rendering, hotbar,
   gameplay, suspend/resume and crash reporting. Only then label a build playable.

## How to get a first build

Open **Actions -> iOS native engine (experimental) -> Run workflow** on the
`ios/native-arm64-first-pass` branch. The workflow uses a macOS GitHub-hosted
runner to compile `aarch64-apple-ios`. If it fails, inspect the Rust compiler
errors; there will be no IPA artifact.

If it succeeds, download the `horizon-ios-engine-experimental` artifact from
the workflow run. It contains an IPA ZIP with `Payload/Horizon.app`, not a
signed distribution. A tool such as Sideloadly must apply a valid signature and
provisioning before installing. This experimental build is not ready to be
treated as a working game.

## Legally prepared assets

Horizon has no permission to ship Minecraft's game files. Prepare the
26.3 resources from your own Java Edition installation on your own Windows
PC, as documented in the root README and `horizon-prepare` CLI. You will
need the matching game install, JDK 25, and the version's official server JAR
used by Horizon's preparation. The output is a *folder* resembling
`.local/horizon-client/26.3/`; move its **contents** to
`Documents/Horizon/resources/` in the app's shared Documents container.

Do not upload game JARs, Microsoft credentials, extracted assets or the
prepared `.local` folder to a public GitHub repository or a public release.

## Scope of the next PR

Prioritize a working iOS 27 scene/window + Metal first-frame test on device,
then add iPhone touch controls and world-load/save validation, and only
then optimize for the A16 GPU. Mods and Modrinth are explicitly deferred.
All these changes stay in the `horizon-ios` fork.
