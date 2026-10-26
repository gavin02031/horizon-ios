# Metal + controls: iPhone 15 native foundation

This branch adds a real `wgpu 30` Metal surface hosted by UIKit inside a
separate SwiftUI full-screen view. **It is a Metal render path diagnostic**,
not Minecraft's playable world renderer. The existing Horizon `Game::run()`
and `gfx::Renderer` remain coupled to `winit::Window` and the owned
`ApplicationHandler` event loop.

## What you can test on an actual iPhone

- From Home, **Test Metal view** opens an independent full-screen view; returning
  does not exit the app or leave audio running.
- A Rust-created WGPU Metal device acquires a drawable from the SwiftUI-owned
  `CAMetalLayer`, runs a GPU pipeline and presents it. The procedural
  green/blue diagnostic moves as you move Horizon's actual pad state.
- The Rust bridge operates a 20-Hz scheduler and uses
  `horizon_client::gamepad::{PadState, Edges, move_vector, look_delta}`,
  `ACTIONS` and the standard hotbar step mapping.
- Apple GameController supplies Xbox/PlayStation/Switch-compatible extended
  controllers connected over Bluetooth. A touch joystick, swipe-look,
  inventory, jump, attack/use and hotbar controls contribute a separate
  PadState. Both sources merge in Rust on every display tick.
- SwiftUI's lifecycle owns the app; native Metal resources are destroyed
  before the view is released. The existing iOS assets import is unchanged.

## Remaining game integration (not shipped as playable)

1. Extract `gfx::Renderer` initialization from its required
   `Arc<winit::Window>` so it accepts an externally provided
   `wgpu::Surface<'static>` and framebuffer size from the UIKit view.
   Keep its shader resources, terrain section uploads, frame graph and
   game-specific pass order unchanged.
2. Extract `game.rs` event dispatch and 20-Hz simulation update from
   `winit::ApplicationHandler`; let a host pass in resize, touch/pad events,
   suspend/resume and frame ticks. Bind the iOS virtual pad to the same
   `Pads::injected` consumer, not the diagnostic copy here.
3. Wire actual Horizon prepared resources, menus, world streaming, block
   interactions, player positions and inventory across the host interface.
4. Validate native save/suspend behavior, input on paused/resumed app,
   Metal first-frame and performance on the A16 GPU.
5. Hook in iOS audio output before calling the result fully playable.

Nothing in the current GPU diagnostic should be represented as a functioning
Minecraft world, despite compiling Horizon into the app. No JVM or JIT is used
in this branch. The app doesn't ship Mojang data or Java mods.
