//! iOS device entry point. The same Rust game code as the desktop client is used.
#![forbid(unsafe_code)]
#![cfg(target_os = "ios")]

mod game;

use std::{env, fs, io, path::PathBuf};

/// Store saves and user-prepared Minecraft resources in the app's Documents
/// directory, which can be accessed using Files / Finder file sharing.
fn prepare_sandbox() -> io::Result<PathBuf> {
    let home = env::var_os("HOME")
        .ok_or_else(|| io::Error::other("iOS sandbox HOME is unavailable"))?;
    let root = PathBuf::from(home).join("Documents").join("Horizon");
    fs::create_dir_all(&root)?;

    // Horizon's default resource lookup is .local/horizon-client/<version>.
    // The symlink points to the clearly named, user-importable "resources" dir.
    // The contents are generated from the user's licensed Java Edition files
    // on their own computer; they are never distributed with this app.
    let alias = root
        .join(".local")
        .join("horizon-client")
        .join(horizon_core::VANILLA_VERSION);
    if let Some(parent) = alias.parent() {
        fs::create_dir_all(parent)?;
    }
    if fs::symlink_metadata(&alias).is_err() {
        std::os::unix::fs::symlink(root.join("resources"), &alias)?;
    }

    // Vanilla settings and saves use the current working directory.
    env::set_current_dir(&root)?;
    Ok(root)
}

fn main() {
    if let Err(error) = run() {
        eprintln!("Horizon iOS failed: {error}");
        std::process::exit(1);
    }
}

fn run() -> horizon_client::Result<()> {
    let home = prepare_sandbox()?;
    horizon_client::telemetry::mark_start();
    horizon_client::logging::init(&home, "Render thread");
    horizon_client::crash::install(home, "client");
    // Winit owns UIApplicationMain; the game creates its window in resumed().
    // This is a native Rust entry point, not a JVM or streamed desktop app.
    game::run()?;
    horizon_client::logging::flush();
    Ok(())
}
