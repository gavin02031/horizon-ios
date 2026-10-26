import Foundation
import CryptoKit
import Combine

/// Downloads *unmodified* Minecraft Java Edition 26.3 source files directly
/// from official Mojang endpoints. Horizon's gameplay runs as native Rust:
/// downloading these files never installs/runs a Java VM on iOS.
///
/// The desktop prepare pipeline needs JDK 25 to run vanilla exporters and
/// produce horizon-resources.json. This iOS installer deliberately does NOT
/// say "Ready to play" until that independent work is actually implemented.
@MainActor
final class MinecraftSourceInstaller: ObservableObject {
    enum Stage: Equatable {
        case idle, downloading, downloaded, error
    }

    @Published private(set) var stage: Stage = .idle
    @Published private(set) var label = "Official Minecraft files not downloaded"
    @Published private(set) var completed = 0
    @Published private(set) var total = 4
    @Published private(set) var problem: String?
    @Published private(set) var hasSourceFiles = false

    private var task: Task<Void, Never>?
    private let version = "26.3"
    private let clientSha1 = "e877b6a07acd633fb3bb475002175cec036e7b87"
    private let serverSha1 = "33680f5f2ac32864d6d7cf5e56a705fdb3e05f4c"
    private let acceptedManifestHashes: Set<String> = [
        "11f1aefe473eefba0af62e3286c33b692807b2eb",
        "4fe1aa1ef8da1cb95c5bad1fb98890ca56dd8ca3",
        "702fe59163c6ee6578607daa85811d9bc9c7cc40",
        "61fff1316bd50312624a858bbb5eb18fa45208ed"
    ]

    var busy: Bool { stage == .downloading }
    var fraction: Double { Double(completed) / Double(max(1, total)) }

    init() {
        refresh()
    }

    func refresh() {
        let base = sourceDirectory
        hasSourceFiles = FileManager.default.fileExists(atPath:
            base.appendingPathComponent("versions/26.3/26.3.jar").path)
            && FileManager.default.fileExists(atPath:
                base.appendingPathComponent("versions/26.3/26.3.json").path)
            && FileManager.default.fileExists(atPath:
                base.appendingPathComponent("versions/26.3/server.jar").path)
        if hasSourceFiles && stage == .idle {
            label = "Downloaded game files found • preparation still required"
        }
    }

    func start() {
        guard !busy else { return }
        stage = .downloading
        problem = nil
        completed = 0
        total = 4
        task = Task {
            do {
                try await install()
                stage = .downloaded
                label = "Official game sources verified • preparation pending"
                hasSourceFiles = true
            } catch is CancellationError {
                stage = .idle
                label = "Download cancelled. Verified files are saved for retry."
            } catch {
                stage = .error
                problem = error.localizedDescription
                label = "Game download couldn't finish"
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    private var sourceDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory,
                                             in: .userDomainMask)[0]
        return docs.appendingPathComponent("Horizon/minecraft-source", isDirectory: true)
    }

    private func install() async throws {
        let root = sourceDirectory
        try FileManager.default.createDirectory(at: root,
                                                withIntermediateDirectories: true)
        label = "Reading Mojang's official version manifest..."
        let indexURL = URL(string: "https://piston-meta.mojang.com/mc/game/version_manifest_v2.json")!
        let (indexData, _) = try await URLSession.shared.data(from: indexURL)
        try Task.checkCancellation()
        guard let index = try JSONSerialization.jsonObject(with: indexData)
                as? [String: Any],
              let entries = index["versions"] as? [[String: Any]],
              let entry = entries.first(where: { $0["id"] as? String == version }),
              let manifestURL = entry["url"] as? String,
              let advertisedSha = entry["sha1"] as? String,
              acceptedManifestHashes.contains(advertisedSha.lowercased()) else {
            throw InstallError.pin("Mojang's version metadata does not match Horizon's pinned 26.3 files. Update the research lock before continuing.")
        }

        let versionDir = root.appendingPathComponent("versions/26.3",
                                                     isDirectory: true)
        let manifestPath = versionDir.appendingPathComponent("26.3.json")
        try await fetchVerified(url: manifestURL, sha1: advertisedSha, to: manifestPath)
        completed = 1
        label = "Downloading the pinned Minecraft client..."
        let data = try Data(contentsOf: manifestPath)
        guard let manifest = try JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let downloads = manifest["downloads"] as? [String: Any],
              let client = downloads["client"] as? [String: Any],
              let server = downloads["server"] as? [String: Any],
              let clientURL = client["url"] as? String,
              let serverURL = server["url"] as? String,
              let pinnedClient = client["sha1"] as? String,
              let pinnedServer = server["sha1"] as? String,
              pinnedClient.lowercased() == clientSha1,
              pinnedServer.lowercased() == serverSha1 else {
            throw InstallError.pin("Minecraft JAR hashes differ from Horizon's research lock.")
        }
        try await fetchVerified(url: clientURL, sha1: clientSha1,
                                to: versionDir.appendingPathComponent("26.3.jar"))
        completed = 2
        label = "Downloading the official server preparation source..."
        try await fetchVerified(url: serverURL, sha1: serverSha1,
                                to: versionDir.appendingPathComponent("server.jar"))
        completed = 3
        label = "Downloading and checking the Minecraft asset index..."
        guard let assets = manifest["assetIndex"] as? [String: Any],
              let assetURL = assets["url"] as? String,
              let assetSha1 = assets["sha1"] as? String,
              let assetID = assets["id"] as? String,
              assetID.range(of: #"^[a-zA-Z0-9._-]{1,45}$"#,
                            options: .regularExpression) != nil else {
            throw InstallError.pin("The version manifest has no safe asset index.")
        }
        try await fetchVerified(url: assetURL, sha1: assetSha1,
                                to: root.appendingPathComponent("assets/indexes/\(assetID).json"))
        completed = 4
        refresh()
    }

    private func fetchVerified(url text: String, sha1 expected: String,
                               to destination: URL) async throws {
        try Task.checkCancellation()
        guard let url = URL(string: text),
              url.scheme == "https",
              let host = url.host?.lowercased(),
              ["piston-meta.mojang.com", "piston-data.mojang.com",
               "launchermeta.mojang.com", "resources.download.minecraft.net",
               "launcher.mojang.com"].contains(host),
              expected.range(of: #"^[a-fA-F0-9]{40}$"#,
                             options: .regularExpression) != nil else {
            throw InstallError.pin("Untrusted Minecraft download URL or checksum.")
        }

        if FileManager.default.fileExists(atPath: destination.path),
           (try? sha1Hex(destination)) == expected.lowercased() {
            return
        }

        let (temporary, response) = try await URLSession.shared.download(from: url)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else {
            throw InstallError.network("Mojang's download server didn't return a file.")
        }
        guard try sha1Hex(temporary) == expected.lowercased() else {
            throw InstallError.pin("A downloaded Minecraft file failed SHA-1 verification. It was not installed.")
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let stage = destination.appendingPathExtension("download")
        if FileManager.default.fileExists(atPath: stage.path) {
            try FileManager.default.removeItem(at: stage)
        }
        try FileManager.default.copyItem(at: temporary, to: stage)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: stage, to: destination)
    }

    private func sha1Hex(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var sha = Insecure.SHA1()
        while true {
            try Task.checkCancellation()
            guard let chunk = try file.read(upToCount: 1_048_576),
                  !chunk.isEmpty else { break }
            sha.update(data: chunk)
        }
        return sha.finalize().map { String(format: "%02x", $0) }.joined()
    }

    enum InstallError: LocalizedError {
        case pin(String), network(String)
        var errorDescription: String? {
            switch self {
            case .pin(let text), .network(let text): text
            }
        }
    }
}
