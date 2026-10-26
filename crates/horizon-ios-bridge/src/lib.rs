//! Native iOS SwiftUI <-> Horizon Rust bridge.
//! The launcher never invokes winit::EventLoop::run_app inside UIApplication:
//! winit 0.30 tries to own UIApplicationMain, which cannot coexist with a
//! SwiftUI @main lifecycle. The actual renderer needs an embedded Metal scene
//! adapter before the UI may enable its Play button.
use std::{env, ffi::{c_char, CString}, path::PathBuf, sync::OnceLock};

fn resource_dir() -> Option<PathBuf> {
    Some(PathBuf::from(env::var_os("HOME")?)
        .join("Documents")
        .join("Horizon")
        .join("resources"))
}

#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_bridge_api_version() -> u32 { 1 }

#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_minecraft_version() -> *const c_char {
    static VERSION: OnceLock<CString> = OnceLock::new();
    VERSION.get_or_init(|| CString::new(horizon_core::VANILLA_VERSION)
        .expect("Minecraft version must not contain NUL")).as_ptr()
}

/// 0 = prepared content validated, 1 = missing, 2 = invalid/incomplete,
/// 3 = app sandbox unavailable. A successful check does *not* imply the
/// GPU/gameplay loop is ready to launch.
#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_resources_status() -> i32 {
    let Some(dir) = resource_dir() else { return 3 };
    if !dir.join("horizon-resources.json").exists() { return 1 }
    match horizon_client::assets::Assets::load(&dir) {
        Ok(_) => 0,
        Err(_) => 2,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn horizon_ios_create_documents_directory() -> bool {
    let Some(home) = env::var_os("HOME") else { return false };
    std::fs::create_dir_all(PathBuf::from(home).join("Documents").join("Horizon")).is_ok()
}
