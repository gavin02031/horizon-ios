import SwiftUI
import UniformTypeIdentifiers

/// Portrait interpretation of the desktop Horizon launcher:
/// graphite/purple navigation, pixel-art sunset, installation rail,
/// download/readiness pipeline and independent settings pages.
/// Gameplay remains a separate full-screen landscape scene.
private enum DesktopTab: String, CaseIterable {
    case home = "Home"
    case mods = "Mods"
    case servers = "Servers"
    case versions = "Versions"
    case notes = "Patch notes"

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .mods: "shippingbox.fill"
        case .servers: "server.rack"
        case .versions: "square.stack.3d.up.fill"
        case .notes: "text.book.closed.fill"
        }
    }
}

private enum DesktopTheme {
    static let background = Color(red: 0.066, green: 0.060, blue: 0.105)
    static let chrome = Color(red: 0.115, green: 0.109, blue: 0.16)
    static let surface = Color(red: 0.145, green: 0.129, blue: 0.215)
    static let raised = Color(red: 0.20, green: 0.18, blue: 0.30)
    static let lilac = Color(red: 0.73, green: 0.56, blue: 1.0)
    static let blue = Color(red: 0.35, green: 0.37, blue: 1.0)
    static let muted = Color(red: 0.76, green: 0.73, blue: 0.83)
    static let gold = Color(red: 1.0, green: 0.70, blue: 0.24)
}

struct DesktopInspiredLauncherView: View {
    @StateObject private var model = HorizonModel()
    @StateObject private var installer = MinecraftSourceInstaller()
    @State private var tab: DesktopTab = .home
    @State private var showSettings = false
    @State private var showFiles = false
    @State private var showMetal = false
    @State private var showImport = false
    @State private var notice: String?
    @State private var acknowledgedOwnership = false

    var body: some View {
        ZStack {
            DesktopTheme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                tabs
                Divider().overlay(DesktopTheme.lilac.opacity(0.23))
                ScrollView {
                    VStack(alignment: .leading, spacing: 15) {
                        if tab == .home {
                            installations
                            hero
                            preparation
                            quickTiles
                        } else {
                            selectedPage
                        }
                    }
                    .frame(maxWidth: 590, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 17)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                bottomBar
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .onAppear { HorizonOrientation.request(.portrait); model.refresh(); installer.refresh() }
        .fullScreenCover(isPresented: $showSettings) {
            DesktopSettingsView()
        }
        .fullScreenCover(isPresented: $showMetal, onDismiss: {
            HorizonOrientation.request(.portrait)
        }) {
            GameDiagnosticScreen()
        }
        .fullScreenCover(isPresented: $showFiles) {
            NativeFilesPage(model: model, installer: installer) {
                showFiles = false
            } importAction: {
                showFiles = false
                showImport = true
            }
        }
        .fileImporter(isPresented: $showImport, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { model.importFolder(url) }
            case .failure(let error): notice = error.localizedDescription
            }
        }
        .alert("Horizon", isPresented: Binding(
            get: { notice != nil || model.message != nil },
            set: { if !$0 { notice = nil; model.message = nil } }
        )) {
            Button("OK") { notice = nil; model.message = nil }
        } message: {
            Text(notice ?? model.message ?? "")
        }
    }

    private var topBar: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(DesktopTheme.lilac.opacity(0.18))
                Text("H")
                    .font(.system(size: 22, weight: .black, design: .monospaced))
                    .foregroundStyle(DesktopTheme.lilac)
            }
            .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Horizon")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                Text("JAVA EDITION 26.3 · RUST ON iOS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesktopTheme.muted)
            }
            Spacer(minLength: 5)
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 38, height: 38)
                    .background(DesktopTheme.raised, in: RoundedRectangle(cornerRadius: 9))
            }
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 16)
        .padding(.top, 9)
        .padding(.bottom, 13)
        .background(DesktopTheme.chrome)
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(DesktopTab.allCases, id: \.self) { page in
                    Button { tab = page } label: {
                        HStack(spacing: 7) {
                            Image(systemName: page.icon)
                                .font(.system(size: 11, weight: .bold))
                            Text(page.rawValue)
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundStyle(tab == page ? .white : DesktopTheme.muted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(tab == page ? DesktopTheme.blue.opacity(0.52) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                        .overlay(alignment: .bottom) {
                            if tab == page {
                                Rectangle()
                                    .fill(DesktopTheme.lilac)
                                    .frame(height: 3)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .background(DesktopTheme.chrome)
    }

    private var installations: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("INSTALLATIONS", systemImage: "square.stack.3d.up")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(DesktopTheme.muted)
                Spacer()
                Button { tab = .versions } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 29, height: 29)
                        .background(DesktopTheme.raised, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 9)
                    .fill(DesktopTheme.blue.opacity(0.48))
                    .frame(width: 43, height: 43)
                    .overlay {
                        Text("H")
                            .font(.system(size: 23, weight: .black, design: .monospaced))
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Horizon")
                        .font(.system(size: 15, weight: .bold))
                    Text(model.status == .ready ? "Resources checked • engine pending" :
                            installer.hasSourceFiles ? "Downloaded • needs preparing" :
                            "Needs preparing")
                        .font(.system(size: 11))
                        .foregroundStyle(DesktopTheme.muted)
                }
                Spacer()
                Circle().fill(model.status == .ready ? .mint : DesktopTheme.gold)
                    .frame(width: 8, height: 8)
            }
            .padding(12)
            .background(DesktopTheme.raised, in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(13)
        .background(DesktopTheme.surface, in: RoundedRectangle(cornerRadius: 15))
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            PixelHorizonBanner()
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "square.grid.2x2")
                    Text("MINECRAFT 26.3")
                        .tracking(0.6)
                    Text("NEEDS PREPARING")
                        .foregroundStyle(DesktopTheme.gold)
                }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                Text("Horizon")
                    .font(.system(size: 38, weight: .black, design: .monospaced))
                    .shadow(color: .black.opacity(0.42), radius: 7, y: 4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("The native Java Edition rewrite.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.89))
                HStack(spacing: 9) {
                    Menu {
                        Text("Pinned version")
                        Button("Minecraft Java 26.3") {}
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("VERSION").font(.system(size: 9, weight: .bold))
                            HStack {
                                Text("26.3").font(.system(size: 14, weight: .bold))
                                Image(systemName: "chevron.down").font(.system(size: 9))
                            }
                        }
                        .padding(.vertical, 9)
                        .padding(.horizontal, 12)
                        .background(DesktopTheme.background.opacity(0.88),
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                    Button {
                        notice = "Minecraft playback is not implemented yet. The SwiftUI app can test Rust/Metal, but Horizon's desktop world renderer and game loop must still be adapted."
                    } label: {
                        HStack {
                            Image(systemName: "lock.fill")
                            Text("Play")
                        }
                        .font(.system(size: 17, weight: .heavy))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(DesktopTheme.blue.opacity(0.85),
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .frame(height: 246)
        .clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17)
            .stroke(DesktopTheme.lilac.opacity(0.34)))
    }

    private var preparation: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ready to play", systemImage: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Text(model.status == .ready ? "ASSETS CHECKED" : "SETUP INCOMPLETE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(DesktopTheme.gold)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(DesktopTheme.lilac)
                Text("The PC launcher downloads Minecraft and runs a Java 25 exporter once. iOS can now download the pinned Mojang files, but the exporter and native gameplay still need porting.")
                    .font(.system(size: 12))
                    .foregroundStyle(DesktopTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if installer.busy {
                ProgressView(value: installer.fraction)
                    .tint(DesktopTheme.lilac)
                HStack {
                    Text(installer.label)
                    Spacer()
                    Button("Cancel") { installer.cancel() }
                        .foregroundStyle(.orange)
                }
                .font(.system(size: 11))
            } else {
                HStack {
                    Image(systemName: installer.hasSourceFiles ?
                          "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(installer.hasSourceFiles ? .mint : DesktopTheme.lilac)
                    Text(installer.label)
                        .lineLimit(2)
                        .font(.system(size: 12))
                    Spacer()
                }
            }
            if let problem = installer.problem {
                Text(problem).font(.system(size: 11)).foregroundStyle(.orange)
            }
            Toggle(isOn: $acknowledgedOwnership) {
                Text("I own Minecraft: Java Edition")
                    .font(.system(size: 11))
                    .foregroundStyle(DesktopTheme.muted)
            }
            .tint(DesktopTheme.lilac)
            Button {
                installer.start()
            } label: {
                Label(installer.hasSourceFiles ? "Verify / redownload files" :
                      "Download official Minecraft files",
                      systemImage: "arrow.down.to.line.compact")
                    .font(.system(size: 13, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(acknowledgedOwnership && !installer.busy ?
                                DesktopTheme.blue : DesktopTheme.raised,
                                in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!acknowledgedOwnership || installer.busy)

            Button { showImport = true } label: {
                Label("Import already-prepared Horizon resources",
                      systemImage: "folder.badge.plus")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(DesktopTheme.raised,
                                in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            Text("Downloading sources does not create horizon-resources.json. Java export and playable Minecraft still need native iOS integration.")
                .font(.system(size: 10))
                .foregroundStyle(DesktopTheme.muted)
        }
        .padding(16)
        .background(DesktopTheme.surface, in: RoundedRectangle(cornerRadius: 15))
    }

    private var quickTiles: some View {
        VStack(spacing: 10) {
            Button { showFiles = true } label: {
                tile("Minecraft folder", detail: "Game source files and resources",
                     symbol: "folder.fill")
            }
            Button { showMetal = true } label: {
                tile("Native Metal test", detail: "Full-screen diagnostic • gamepad & touch",
                     symbol: "gamecontroller.fill")
            }
            Button {
                notice = "Multiplayer and friend invitations will become available after the real Rust Minecraft client runs on iOS."
            } label: {
                tile("Join a friend", detail: "Invitations • coming later",
                     symbol: "person.2.fill")
            }
        }
        .buttonStyle(.plain)
    }

    private func tile(_ title: String, detail: String, symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(DesktopTheme.lilac)
                .frame(width: 35)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 11))
                    .foregroundStyle(DesktopTheme.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesktopTheme.muted)
        }
        .padding(15)
        .background(DesktopTheme.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var selectedPage: some View {
        switch tab {
        case .home:
            EmptyView()
        case .mods:
            placeholderPage("Mods", "shippingbox",
                "The PC launcher supports Horizon's own Rust/WASM mods, not Java mod JARs. Native iOS gameplay is our first priority.")
        case .servers:
            placeholderPage("Servers", "server.rack",
                "Servers and invitations will come after the gameplay loop and network client are embedded in the iPhone app.")
        case .versions:
            VStack(alignment: .leading, spacing: 15) {
                Text("Versions").font(.system(size: 27, weight: .heavy))
                Text("Horizon targets one pinned Java Edition version at a time.")
                    .font(.system(size: 12)).foregroundStyle(DesktopTheme.muted)
                HStack {
                    Image(systemName: "square.stack.3d.up.fill")
                        .foregroundStyle(DesktopTheme.lilac)
                    VStack(alignment: .leading) {
                        Text("Minecraft Java 26.3").font(.system(size: 15, weight: .bold))
                        Text("Pinned by Horizon research-lock.json")
                            .font(.system(size: 11)).foregroundStyle(DesktopTheme.muted)
                    }
                    Spacer()
                    Text("CURRENT").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.mint)
                }
                .padding(17)
                .background(DesktopTheme.surface, in: RoundedRectangle(cornerRadius: 14))
                Button("Return to install") { tab = .home }
                    .buttonStyle(.borderedProminent)
            }
        case .notes:
            VStack(alignment: .leading, spacing: 16) {
                Text("Patch notes").font(.system(size: 27, weight: .heavy))
                Text("Horizon iOS • Launcher preview")
                    .font(.system(size: 12))
                    .foregroundStyle(DesktopTheme.muted)
                tile("Desktop-style launcher", detail: "Purple theme, installations, pinned version selector, preparation flow",
                     symbol: "sparkles")
                tile("Official Minecraft downloads", detail: "Pinned 26.3 Mojang files with SHA-1 verification",
                     symbol: "arrow.down.circle")
                tile("Native display and inputs", detail: "SwiftUI portrait shell + full-screen Rust Metal test",
                     symbol: "cpu.fill")
            }
        }
    }

    private func placeholderPage(_ title: String, _ symbol: String, _ message: String) -> some View {
        VStack(alignment: .leading, spacing: 15) {
            Label(title, systemImage: symbol)
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(DesktopTheme.lilac)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(DesktopTheme.muted)
            Button("Back to Home") { tab = .home }
                .buttonStyle(.borderedProminent)
                .tint(DesktopTheme.blue)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesktopTheme.surface, in: RoundedRectangle(cornerRadius: 15))
    }

    private var bottomBar: some View {
        HStack {
            Image(systemName: "circle.fill")
                .font(.system(size: 7)).foregroundStyle(DesktopTheme.gold)
            Text("Player offline")
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            Text("iOS LAUNCHER · JAVA 26.3")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(DesktopTheme.muted)
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 12)
        .background(DesktopTheme.chrome)
    }
}

/// Decorative SwiftUI art, not a screenshot or Mojang texture:
/// pixel-stepped purple ridges and a warm square sun like PC Horizon.
private struct PixelHorizonBanner: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [
                    Color(red: 0.26, green: 0.13, blue: 0.40),
                    Color(red: 0.57, green: 0.24, blue: 0.51),
                    Color(red: 0.94, green: 0.43, blue: 0.36),
                ], startPoint: .top, endPoint: .bottom)
                Canvas { context, size in
                    let step = 13.0
                    let count = Int(ceil(size.width / step))
                    let sunRect = CGRect(x: size.width * 0.80,
                        y: size.height * 0.19, width: 37, height: 37)
                    context.fill(Path(sunRect), with: .color(
                        Color(red: 1.0, green: 0.85, blue: 0.46)))
                    for column in 0..<count {
                        let x = Double(column) * step
                        let wave = sin(Double(column) * 0.41) * 17
                        let distant = size.height * 0.58 + wave
                        context.fill(Path(CGRect(x: x, y: distant,
                                                 width: step + 1, height: size.height - distant)),
                                     with: .color(Color(red: 0.38, green: 0.18, blue: 0.49)))
                        let ridge = size.height * 0.78 + sin(Double(column) * 0.52) * 26
                        context.fill(Path(CGRect(x: x, y: ridge,
                                                 width: step + 1, height: size.height - ridge)),
                                     with: .color(Color(red: 0.17, green: 0.10, blue: 0.29)))
                    }
                }
                Rectangle().fill(LinearGradient(colors: [
                    .black.opacity(0.48), .black.opacity(0.03)
                ], startPoint: .leading, endPoint: .trailing))
            }
        }
    }
}

private struct NativeFilesPage: View {
    @ObservedObject var model: HorizonModel
    @ObservedObject var installer: MinecraftSourceInstaller
    let close: () -> Void
    let importAction: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                DesktopTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 17) {
                        Text("Minecraft folder")
                            .font(.system(size: 27, weight: .heavy))
                        Text("Stored inside the iOS app's Documents/Horizon directory. Files downloaded here are the original Mojang game sources, not prepared engine data.")
                            .font(.system(size: 13))
                            .foregroundStyle(DesktopTheme.muted)
                        tile("Source download", status: installer.label,
                             symbol: "arrow.down.doc")
                        tile("Horizon prepared resources",
                             status: model.status.title,
                             symbol: "shippingbox")
                        Button(action: importAction) {
                            Label("Import prepared resources from Files",
                                  systemImage: "folder.badge.plus")
                                .font(.system(size: 13, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(14)
                                .background(DesktopTheme.blue,
                                            in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        Text("The Java 25 export stage has not yet been ported to run without Java on iPhone.")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                    }
                    .padding(18)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back", action: close)
                }
            }
        }
        .tint(DesktopTheme.lilac)
    }

    private func tile(_ title: String, status: String, symbol: String) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .foregroundStyle(DesktopTheme.lilac)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(status).font(.system(size: 12))
                    .foregroundStyle(DesktopTheme.muted)
            }
            Spacer()
        }
        .padding(15)
        .background(DesktopTheme.surface, in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct DesktopSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ZStack {
                DesktopTheme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        Text("Settings")
                            .font(.system(size: 29, weight: .heavy))
                        settingRow("Launcher & display",
                                   detail: "Portrait UI, landscape Metal test",
                                   symbol: "iphone")
                        settingRow("Graphics",
                                   detail: "Rust/Metal world graphics pending",
                                   symbol: "cpu")
                        settingRow("Controllers",
                                   detail: "Bluetooth & touch input test ready",
                                   symbol: "gamecontroller.fill")
                        settingRow("Account",
                                   detail: "Microsoft OAuth not implemented on iOS",
                                   symbol: "person.crop.circle")
                        Text("Horizon iOS is an independent native port. Game downloads don't automatically grant account authentication or prepare engine data.")
                            .font(.system(size: 12))
                            .foregroundStyle(DesktopTheme.muted)
                            .padding(.top, 9)
                    }
                    .padding(18)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(DesktopTheme.lilac)
    }

    private func settingRow(_ name: String, detail: String,
                            symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(DesktopTheme.lilac)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 14, weight: .bold))
                Text(detail).font(.system(size: 11))
                    .foregroundStyle(DesktopTheme.muted)
            }
            Spacer()
        }
        .padding(16)
        .background(DesktopTheme.surface, in: RoundedRectangle(cornerRadius: 13))
    }
}
