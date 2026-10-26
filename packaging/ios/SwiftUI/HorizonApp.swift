import SwiftUI
import UniformTypeIdentifiers

@main
struct HorizonPhoneApp: App {
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
    case settings = "Settings"
    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .worlds: "square.stack.3d.up.fill"
        case .settings: "slider.horizontal.3"
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
        case .ready: "Minecraft resources verified"
        case .missing: "Minecraft resources required"
        case .incomplete: "Resources are incomplete or incompatible"
        case .unavailable: "Unable to access app storage"
        }
    }
    var details: String {
        switch self {
        case .ready: "Rust validated the Java Edition data. Gameplay integration is next."
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

private struct LauncherView: View {
    @StateObject private var model = HorizonModel()
    @State private var showFileImporter = false

    private let background = Color(red: 0.055, green: 0.068, blue: 0.115)
    private let panel = Color(red: 0.105, green: 0.126, blue: 0.205)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                background.ignoresSafeArea()
                RadialGradient(colors: [.indigo.opacity(0.42), .clear],
                    center: .topTrailing, startRadius: 20, endRadius: 520)
                    .ignoresSafeArea()

                HStack(spacing: 18) {
                    sidebar
                        .frame(width: min(164, max(112, geo.size.width * 0.20)))
                    Rectangle()
                        .fill(.white.opacity(0.09))
                        .frame(width: 1)
                    ScrollView {
                        content
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sun.horizon.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(.cyan)
                Text("HORIZON")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .tracking(1.5)
            }
            .padding(.bottom, 25)

            ForEach(Page.allCases, id: \.self) { page in
                Button { model.page = page } label: {
                    HStack(spacing: 11) {
                        Image(systemName: page.symbol).frame(width: 19)
                        Text(page.rawValue)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 14, weight: model.page == page ? .bold : .medium))
                    .foregroundStyle(model.page == page ? .white : .white.opacity(0.6))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 13)
                    .background(model.page == page ? .white.opacity(0.11) : .clear,
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 12)
            HStack(spacing: 7) {
                Circle().fill(.mint).frame(width: 6, height: 6)
                Text("Rust bridge v\(model.bridgeVersion)")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white.opacity(0.62))
            Text("JAVA \(model.javaVersion)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.44))
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.page {
        case .home: home
        case .worlds: worlds
        case .settings: settings
        }
    }

    private var home: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("MINECRAFT JAVA EDITION")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(2)
                        .foregroundStyle(.cyan)
                    Text("Your world, on iPhone.")
                        .font(.system(size: 25, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Label("Native ARM64", systemImage: "cpu")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(9)
                    .background(.white.opacity(0.09), in: Capsule())
            }
            HStack(spacing: 12) {
                actionCard("Singleplayer", "Your worlds, locally.", "square.stack.3d.up.fill", accent: .cyan)
                actionCard("Multiplayer", "Servers and friends.", "person.2.fill", accent: .purple)
            }
            resourceCard
            Text("Gameplay is not connected to SwiftUI yet. This build verifies the native launcher and Rust bridge; it does not claim to play worlds.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
        }
    }

    private func actionCard(_ title: String, _ subtitle: String, _ symbol: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 25))
                .foregroundStyle(accent)
            Spacer(minLength: 0)
            Text(title).font(.system(size: 18, weight: .bold, design: .rounded))
            Text(subtitle).font(.system(size: 11)).foregroundStyle(.white.opacity(0.58))
            Label("Engine integration pending", systemImage: "lock.fill")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.45))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 115)
        .padding(14)
        .background(
            LinearGradient(colors: [accent.opacity(0.17), panel],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.07)))
    }

    private var resourceCard: some View {
        HStack(spacing: 13) {
            Image(systemName: model.status.icon)
                .font(.system(size: 22))
                .foregroundStyle(model.status.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.status.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(model.status.details)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.62))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if model.busy {
                ProgressView().tint(.cyan)
            } else {
                Button {
                    showFileImporter = true
                } label: {
                    Label("Import files", systemImage: "folder.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.vertical, 11)
                        .padding(.horizontal, 12)
                        .background(.cyan.opacity(0.24), in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(13)
        .background(panel, in: RoundedRectangle(cornerRadius: 15))
    }

    private var worlds: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("My Worlds").font(.system(size: 26, weight: .bold, design: .rounded))
            VStack(spacing: 12) {
                Image(systemName: "square.stack.3d.up.slash")
                    .font(.system(size: 32)).foregroundStyle(.cyan.opacity(0.75))
                Text("World library coming next").font(.system(size: 15, weight: .bold))
                Text("World browsing will read Minecraft saves from the app's Documents/Horizon folder. Rust handles the actual world data.")
                    .font(.system(size: 12)).multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity, minHeight: 190)
            .padding()
            .background(panel, in: RoundedRectangle(cornerRadius: 18))
        }
        .foregroundStyle(.white)
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Settings").font(.system(size: 26, weight: .bold, design: .rounded))
            Text("Performance preferences will connect to the Rust renderer after the Metal game view is embedded.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.64))
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label("Render distance", systemImage: "mountain.2")
                    Spacer()
                    Text("\(Int(model.renderDistance)) chunks").foregroundStyle(.cyan)
                }
                Slider(value: $model.renderDistance, in: 2...10, step: 1).tint(.cyan)
                HStack {
                    Label("Target frame rate", systemImage: "speedometer")
                    Spacer()
                    Text("\(Int(model.frameLimit)) FPS").foregroundStyle(.cyan)
                }
                Picker("Target FPS", selection: $model.frameLimit) {
                    Text("30").tag(30.0)
                    Text("60").tag(60.0)
                }
                .pickerStyle(.segmented)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(16)
            .background(panel, in: RoundedRectangle(cornerRadius: 17))
        }
        .foregroundStyle(.white)
    }
}
