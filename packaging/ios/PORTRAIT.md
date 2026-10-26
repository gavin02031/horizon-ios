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
