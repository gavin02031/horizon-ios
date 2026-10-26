import SwiftUI
import UniformTypeIdentifiers

@main
struct HorizonPhoneApp: App {
    @UIApplicationDelegateAdaptor(HorizonOrientationDelegate.self) private var orientationDelegate

    var body: some Scene {
        WindowGroup {
            LauncherView()
                .preferredColorScheme(.dark)
        }
    }
}

private enum Page: String, CaseIterable {
    case home = "Home"
    case worlds = "Worlds"
    case files = "Files"
    case settings = "Settings"
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .worlds: "square.stack.3d.up.fill"
        case .files: "square.and.arrow.down"
        case .settings: "gearshape.fill"
        }
    }
}

private enum ResourceStatus: Int32 {
    case ready = 0
    case missing = 1
    case incomplete = 2
    case unavailable = 3

    var title: String {
        switch self {
        case .ready: "Core Minecraft resources verified"
        case .missing: "Minecraft resources required"
        case .incomplete: "Resources are incomplete or incompatible"
        case .unavailable: "Unable to access app storage"
        }
    }
    var details: String {
        switch self {
        case .ready: "The native Rust engine checked the prepared data. The full game renderer is still being connected."
        case .missing: "Import resources prepared from your own Minecraft Java Edition 26.3 installation."
        case .incomplete: "Use the complete Horizon-prepared resources folder for Java Edition 26.3."
        case .unavailable: "The app couldn't find its Documents folder."
        }
    }
    var icon: String { self == .ready ? "checkmark.seal.fill" : "exclamationmark.circle.fill" }
    var color: Color { self == .ready ? .mint : .orange }
}

@MainActor
private final class HorizonModel: ObservableObject {
    @Published var page: Page = .home
    @Published var status: ResourceStatus = .missing
    @Published var importing = false
    @Published var busy = false
    @Published var message: String?
    @Published var renderDistance = 6.0
    @Published var frameLimit = 30.0

    let javaVersion: String = {
        guard let ptr = horizon_ios_minecraft_version() else { return "unknown" }
        return String(cString: ptr)
    }()
    let bridgeVersion = horizon_ios_bridge_api_version()

    init() { refresh() }

    func refresh() {
        Task.detached(priority: .userInitiated) {
            let value = ResourceStatus(rawValue: horizon_ios_resources_status()) ?? .unavailable
            await MainActor.run { self.status = value }
        }
    }

    func importFolder(_ url: URL) {
        busy = true
        Task.detached(priority: .userInitiated) {
            let opened = url.startAccessingSecurityScopedResource()
            defer { if opened { url.stopAccessingSecurityScopedResource() } }
            do {
                let fm = FileManager.default
                guard horizon_ios_create_documents_directory(),
                      let doc = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
                    throw NSError(domain: "Horizon", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Unable to create Horizon's Documents folder."])
                }
                let home = doc.appendingPathComponent("Horizon", isDirectory: true)
                let stage = home.appendingPathComponent("resources-importing", isDirectory: true)
                let destination = home.appendingPathComponent("resources", isDirectory: true)
                let backup = home.appendingPathComponent("resources-previous", isDirectory: true)
                if fm.fileExists(atPath: stage.path) { try fm.removeItem(at: stage) }
                try fm.copyItem(at: url, to: stage)
                guard fm.fileExists(atPath: stage.appendingPathComponent("horizon-resources.json").path) else {
                    try? fm.removeItem(at: stage)
                    throw NSError(domain: "Horizon", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Choose the prepared resources folder containing horizon-resources.json, not a Minecraft jar or zip."])
                }
                if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
                let hadPrevious = fm.fileExists(atPath: destination.path)
                if hadPrevious { try fm.moveItem(at: destination, to: backup) }
                do {
                    try fm.moveItem(at: stage, to: destination)
                } catch {
                    if hadPrevious { try? fm.moveItem(at: backup, to: destination) }
                    throw error
                }
                let result = ResourceStatus(rawValue: horizon_ios_resources_status()) ?? .unavailable
                await MainActor.run {
                    self.status = result
                    self.busy = false
                    self.message = result == .ready ?
                        "Resources imported and verified by the Rust engine." :
                        "Folder imported, but Rust couldn't validate all required data. Check that it was prepared for Java Edition 26.3."
                }
            } catch {
                await MainActor.run {
                    self.busy = false
                    self.message = error.localizedDescription
                }
            }
        }
    }
}


private enum HorizonPalette {
    static let bg = Color(red: 0.035, green: 0.052, blue: 0.102)
    static let card = Color(red: 0.083, green: 0.112, blue: 0.185)
    static let accent = Color(red: 0.16, green: 0.79, blue: 0.98)
    static let blue = Color(red: 0.06, green: 0.42, blue: 0.98)
    static let muted = Color(red: 0.64, green: 0.72, blue: 0.85)
}

private struct LauncherView: View {
    @StateObject private var model = HorizonModel()
    @State private var showFileImporter = false
    @State private var showMetalDiagnostic = false

    var body: some View {
        ZStack {
            HorizonPalette.bg.ignoresSafeArea()
            RadialGradient(colors: [HorizonPalette.blue.opacity(0.24), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 480)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 19) {
                        header
                        switch model.page {
                        case .home: home
                        case .worlds: worlds
                        case .files: files
                        case .settings: settings
                        }
                    }
                    .frame(maxWidth: 580, alignment: .leading)
                    .padding(.horizontal, 19)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
                tabBar
            }
        }
        .foregroundStyle(.white)
        .onAppear { HorizonOrientation.request(.portrait) }
        .fullScreenCover(isPresented: $showMetalDiagnostic, onDismiss: {
            HorizonOrientation.request(.portrait)
            model.refresh()
        }) {
            GameDiagnosticScreen()
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.folder],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let files):
                if let first = files.first { model.importFolder(first) }
            case .failure(let error):
                model.message = error.localizedDescription
            }
        }
        .alert("Horizon iOS", isPresented: Binding(
            get: { model.message != nil },
            set: { if !$0 { model.message = nil } }
        )) {
            Button("OK", role: .cancel) { model.message = nil }
        } message: {
            Text(model.message ?? "")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "cube.transparent.fill")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(HorizonPalette.accent)
                .frame(width: 45, height: 45)
                .background(HorizonPalette.blue.opacity(0.19),
                            in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text("HORIZON")
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .tracking(1.1)
                Text("JAVA EDITION · NATIVE iOS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.7)
                    .foregroundStyle(HorizonPalette.accent)
            }
            Spacer(minLength: 6)
            Text("ARM64 · METAL")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(HorizonPalette.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(.white.opacity(0.07), in: Capsule())
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 9) {
                Text("YOUR NEXT ADVENTURE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(2.1)
                    .foregroundStyle(HorizonPalette.accent)
                Text("Your world,\non iPhone.")
                    .font(.system(size: 37, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.85)
                    .lineSpacing(-4)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Minecraft Java Edition, rebuilt in Rust.")
                    .font(.system(size: 13))
                    .foregroundStyle(HorizonPalette.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 22)
            .background(
                LinearGradient(colors: [
                    Color(red: 0.10, green: 0.19, blue: 0.34),
                    Color(red: 0.08, green: 0.09, blue: 0.20)
                ], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 22)
            )
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(HorizonPalette.accent.opacity(0.20)))

            Button { showMetalDiagnostic = true } label: {
                HStack(spacing: 13) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 21, weight: .semibold))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Test native Metal & controls")
                            .font(.system(size: 16, weight: .bold))
                        Text("Full-screen GPU test · not Minecraft gameplay")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer(minLength: 3)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(16)
                .background(
                    LinearGradient(colors: [HorizonPalette.accent, HorizonPalette.blue],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18)
                )
            }
            .buttonStyle(.plain)

            resourceCard
            sectionHeading("Game readiness", "CPU + GPU progress")
            HStack(spacing: 10) {
                progressCard("Rust engine", "Compiled", "checkmark.seal.fill", .mint)
                progressCard("Metal display", "Test available", "cpu.fill", HorizonPalette.accent)
            }
            HStack(spacing: 10) {
                progressCard("World gameplay", "Integration pending", "shippingbox", .orange)
                progressCard("Microsoft", "Not signed in here", "person.crop.circle", .orange)
            }
            Text("Version " + model.javaVersion + " identifies the Java Edition data Horizon targets. This app does not install Java or download Minecraft from Microsoft automatically.")
                .font(.system(size: 11))
                .foregroundStyle(HorizonPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func progressCard(_ title: String, _ detail: String,
                              _ icon: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
            Text(title).font(.system(size: 12, weight: .bold))
                .lineLimit(1).minimumScaleFactor(0.8)
            Text(detail).font(.system(size: 10))
                .foregroundStyle(HorizonPalette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
        .padding(13)
        .background(HorizonPalette.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var resourceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: model.status.icon)
                    .font(.system(size: 23))
                    .foregroundStyle(model.status.color)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.status.title)
                        .font(.system(size: 14, weight: .bold))
                    Text(model.status.details)
                        .font(.system(size: 11))
                        .foregroundStyle(HorizonPalette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: 10) {
                Button { showFileImporter = true } label: {
                    Label("Import my game files", systemImage: "folder.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(HorizonPalette.blue.opacity(0.36),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(model.busy)
                Button { model.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 43, height: 43)
                        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(HorizonPalette.card, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.06)))
    }

    private func sectionHeading(_ title: String, _ subtitle: String? = nil) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 19, weight: .bold, design: .rounded))
            Spacer()
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(HorizonPalette.muted)
            }
        }
    }

    private var worlds: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading("My worlds")
            Text("Saved Minecraft worlds on this iPhone. World launch stays unavailable until the actual Rust renderer and simulation are integrated.")
                .font(.system(size: 12))
                .foregroundStyle(HorizonPalette.muted)
            WorldFoldersView()
            resourceCard
        }
    }

    private var files: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionHeading("Game files")
            Text("Horizon uses Minecraft Java Edition " + model.javaVersion + " data prepared from your own installation. It does not run a Java virtual machine.")
                .font(.system(size: 12))
                .foregroundStyle(HorizonPalette.muted)
            resourceCard
            VStack(alignment: .leading, spacing: 10) {
                Label("Import instructions", systemImage: "info.circle")
                    .font(.system(size: 15, weight: .semibold))
                Text("On a computer, run Horizon's resource preparation for the matching Java Edition version. Move the resulting folder into Files on your iPhone, then import the folder here.")
                    .font(.system(size: 12))
                    .foregroundStyle(HorizonPalette.muted)
                Text("Don't upload game files, Microsoft login tokens, or credentials to a public GitHub repository.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange.opacity(0.85))
            }
            .padding(16)
            .background(HorizonPalette.card, in: RoundedRectangle(cornerRadius: 18))
        }
    }

    private var settings: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeading("Settings")
                    Text("Each category has its own page. Gameplay options become active once the Rust game loop is embedded.")
                        .font(.system(size: 12))
                        .foregroundStyle(HorizonPalette.muted)
                    settingsLink("Graphics & performance", "speedometer",
                                 "FPS target, render distance") {
                        GraphicsSettingsView(renderDistance: $model.renderDistance,
                                             frameLimit: $model.frameLimit)
                    }
                    settingsLink("Touch & Bluetooth", "gamecontroller.fill",
                                 "Layout, controller mappings") {
                        ControllerSettingsView()
                    }
                    settingsLink("Account & ownership", "person.crop.circle",
                                 "Microsoft integration status") {
                        AccountSettingsView()
                    }
                    settingsLink("About Horizon", "info.circle",
                                 "App and Rust engine information") {
                        AboutHorizonView(version: model.javaVersion, bridge: model.bridgeVersion)
                    }
                }
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
        }
        .tint(HorizonPalette.accent)
    }

    private func settingsLink<Destination: View>(
        _ title: String, _ symbol: String, _ subtitle: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 19))
                    .foregroundStyle(HorizonPalette.accent)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(subtitle).font(.system(size: 11))
                        .foregroundStyle(HorizonPalette.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(HorizonPalette.muted)
            }
            .padding(15)
            .background(HorizonPalette.card, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(Page.allCases, id: \.self) { page in
                Button { model.page = page } label: {
                    VStack(spacing: 5) {
                        Image(systemName: page.symbol)
                            .font(.system(size: 19, weight: .medium))
                        Text(page.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(model.page == page ? HorizonPalette.accent : HorizonPalette.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(.white.opacity(0.08)).frame(height: 1)
        }
    }
}

private struct WorldFoldersView: View {
    @State private var folders: [URL] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if folders.isEmpty {
                Label("No saved worlds found in Horizon's Documents folder.",
                      systemImage: "square.stack.3d.up.slash")
                    .font(.system(size: 12))
                    .foregroundStyle(HorizonPalette.muted)
                    .frame(maxWidth: .infinity, minHeight: 112)
            } else {
                ForEach(folders, id: \.path) { folder in
                    HStack {
                        Image(systemName: "globe.americas.fill")
                            .foregroundStyle(HorizonPalette.accent)
                        Text(folder.lastPathComponent)
                            .font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("Stored")
                            .font(.system(size: 11))
                            .foregroundStyle(HorizonPalette.muted)
                    }
                    .padding(.vertical, 9)
                }
            }
        }
        .padding(16)
        .background(HorizonPalette.card, in: RoundedRectangle(cornerRadius: 18))
        .onAppear(perform: reload)
    }
    private func reload() {
        guard let doc = FileManager.default.urls(for: .documentDirectory,
                                                 in: .userDomainMask).first else { return }
        let root = doc.appendingPathComponent("Horizon/saves", isDirectory: true)
        folders = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]))?.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending } ?? []
    }
}

private struct SettingsSubpage<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Button { dismiss() } label: {
                    Label("Settings", systemImage: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(HorizonPalette.accent)
                Text(title)
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                content
            }
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(HorizonPalette.bg)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct GraphicsSettingsView: View {
    @Binding var renderDistance: Double
    @Binding var frameLimit: Double
    var body: some View {
        SettingsSubpage(title: "Graphics & performance") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved as launcher preferences only — not yet applied to the game renderer.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                HStack {
                    Text("Target render distance")
                    Spacer()
                    Text("\(Int(renderDistance)) chunks").foregroundStyle(HorizonPalette.accent)
                }
                Slider(value: $renderDistance, in: 2...10, step: 1)
                    .tint(HorizonPalette.accent)
                Text("Frame rate preference")
                Picker("FPS", selection: $frameLimit) {
                    Text("30 FPS").tag(30.0)
                    Text("60 FPS").tag(60.0)
                }
                .pickerStyle(.segmented)
            }
            .font(.system(size: 13))
            .padding(17)
            .background(HorizonPalette.card, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

private struct ControllerSettingsView: View {
    var body: some View {
        SettingsSubpage(title: "Touch & Bluetooth") {
            VStack(alignment: .leading, spacing: 13) {
                Label("Supported by the Metal test scene",
                      systemImage: "gamecontroller.fill")
                    .font(.system(size: 14, weight: .semibold))
                Text("Connect a Bluetooth gamepad in iOS Settings. The test scene reads Apple's extended controller profile and combines it with on-screen joystick, jump, attack and use controls.")
                    .font(.system(size: 12))
                    .foregroundStyle(HorizonPalette.muted)
                Text("Mappings are not yet connected to Minecraft gameplay.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            .padding(17)
            .background(HorizonPalette.card, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

private struct AccountSettingsView: View {
    var body: some View {
        SettingsSubpage(title: "Microsoft account") {
            VStack(alignment: .leading, spacing: 12) {
                Label("Not connected in this iOS build",
                      systemImage: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 14, weight: .semibold))
                Text("Microsoft sign-in in desktop Horizon is not carried over automatically to this iPhone app. The iOS version does not yet include a secure Microsoft OAuth login and Minecraft entitlement verification.")
                    .font(.system(size: 12))
                    .foregroundStyle(HorizonPalette.muted)
                Text("Never paste access tokens into this app or a GitHub repository.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            .padding(17)
            .background(HorizonPalette.card, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

private struct AboutHorizonView: View {
    let version: String
    let bridge: UInt32
    var body: some View {
        SettingsSubpage(title: "About Horizon") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Minecraft Java Edition data: \(version)")
                Text("Native Rust bridge API: \(bridge)")
                Text("Runtime: compiled ARM64 Rust, no Java VM, no JIT")
                Text("Display: Apple's Metal graphics API")
                Text("Gameplay: not yet embedded in the iOS Metal scene")
            }
            .font(.system(size: 12))
            .padding(17)
            .background(HorizonPalette.card, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}
