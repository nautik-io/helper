import Foundation
import SwiftUI
import SwiftkubeClient
import Yams
import AppUpdater

@MainActor
@Observable
class AppState {
    let updater = AppUpdater(owner: "nautik-io", repo: "helper")
    
    static let decoder = YAMLDecoder()
    
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    static let deviceUUID = (try? executeCommand(command: "ioreg", arguments: [#"-d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $(NF-1)}'"#]).map { UUID(uuidString: $0) ?? UUID() }) ?? UUID()
    static let currentUser = (try? executeCommand(command: "id", arguments: ["-un"])) ?? "unknown"
    
    private var kubeConfigPathsCache: KubeConfigPaths
    
    var kubeConfigPaths: KubeConfigPaths {
        get {
            return kubeConfigPathsCache
        }
        set(newVal) {
            kubeConfigPathsCache = newVal
            UserDefaults.standard.set(newVal.rawValue, forKey: "kubeconfigs")
        }
    }
    
    var kubeConfigs: [WatchResult] {
        get {
            kubeConfigPaths.map { path in
                // TODO: Watch the path continuously.
                
                do {
                    guard path.startAccessingSecurityScopedResource() else {
                        throw "Couldn't access the selected file."
                    }
                    defer { path.stopAccessingSecurityScopedResource() }
                    
                    let contents = try String(contentsOf: path, encoding: .utf8)
                    let kubeConfig = try Self.decoder.decode(KubeConfig.self, from: contents)
                    
                    return .ok(WatchedKubeConfig(path: path, kubeConfig: kubeConfig))
                } catch {
                    return .error(WatchError(path: path, error: "\(error)"))
                }
            }
        }
        set(newVal) {
            kubeConfigPaths = newVal.map { $0.path }
        }
    }
    
    var validKubeConfigs: [WatchedKubeConfig] {
        kubeConfigs.compactMap {
            if case let .ok(watchedKubeConfig) = $0 {
                return watchedKubeConfig
            }
            return nil
        }
    }
    var invalidKubeConfigs: [WatchError] {
        kubeConfigs.compactMap {
            if case let .error(error) = $0 {
                return error
            }
            return nil
        }
    }
    
    var clusters: [StoredCluster] = []
    
    init() {
        kubeConfigPathsCache = UserDefaults.standard.string(forKey: "kubeconfigs")
            .map { KubeConfigPaths(rawValue: $0) ?? [] } ?? []
        
        do {
            clusters = try SyncKeychain.standard.listClusters()
        } catch {
            print("Error loading clusters from keychain: \(error)")
            clusters = []
        }
        
        startPeriodicClusterReEvaluation()
    }
    
    deinit {
        Task {
            await MainActor.run {
                stopPeriodicClusterReEvaluation()
            }
        }
    }
    
    func refreshClusters() async throws {
        try await Task.detached { [weak self] in
            guard let self else { return }
            
            let clusters = try await Keychain.standard.listClusters()
            
            // In case the main app changed something on the clusters on the keychain,
            // we're always setting our internal cluster state to the keychain's.
            await MainActor.run {
                self.clusters = clusters
            }
            
            for cluster in clusters {
                // Refresh cluster info, auth info & namespace from the file and re-evaluate auth.
                if case let .ok(watchResult) = await self.kubeConfigs.first(where: { $0.path == cluster.kubeConfigPath }),
                   let watchedCluster = watchResult.clusters.first(where: { $0.context.name == cluster.kubeConfigContextName }) {
                    cluster.cluster = watchedCluster.cluster.cluster
                    cluster.authInfo = watchedCluster.authInfo.authInfo
                    cluster.defaultNamespace = watchedCluster.context.context.namespace ?? cluster.defaultNamespace
                    
                    do {
                        try await cluster.evaluateAuth()
                    } catch {
                        cluster.error = "Error evaluating cluster auth: \(error)"
                    }
                } else {
                    cluster.error = "Error refreshing cluster from the watched kubeconfig at \(cluster.kubeConfigPath) - \(cluster.kubeConfigContextName)"
                }
                
                try? await self.updateCluster(cluster)
            }
        }.value
    }
    
    func addCluster(_ cluster: WatchedKubeConfig.Cluster, path kubeConfigPath: URL) async throws {
        let lastPosition = self.clusters.last?.position ?? 0
        let newPosition = Double.random(in: lastPosition + 0.000001...lastPosition + 0.2)
        let newCluster = cluster.toStoredCluster(
            position: newPosition,
            kubeConfigDeviceID: AppState.deviceUUID,
            kubeConfigDeviceUser: AppState.currentUser,
            kubeConfigPath: kubeConfigPath
        )
        
        try await newCluster.evaluateAuth()
        
        self.clusters.append(newCluster)
        
        try await Task.detached {
            try await Keychain.standard.saveCluster(newCluster)
        }.value
    }
    
    func updateCluster(_ cluster: StoredCluster) async throws {
        if let i = self.clusters.firstIndex(where: { $0.id == cluster.id }) {
            self.clusters[i] = cluster
            
            try await Task.detached {
                try await Keychain.standard.saveCluster(cluster)
            }.value
        }
    }
    
    func removeCluster(path kubeConfigPath: URL, name kubeConfigContextName: String) async throws {
        guard let clusterToRemove = self.clusters.first(where: {
            $0.kubeConfigPath == kubeConfigPath && 
            $0.kubeConfigContextName == kubeConfigContextName
        }) else { return }
        
        self.clusters = self.clusters.filter { $0.id != clusterToRemove.id }
        
        try await Task.detached {
            try await Keychain.standard.deleteCluster(clusterToRemove)
        }.value
    }
    
    var clusterReEvaluationTask: Task<Void, Error>? = nil
    
    func startPeriodicClusterReEvaluation() {
        if let clusterReEvaluationTask {
            clusterReEvaluationTask.cancel()
        }
        clusterReEvaluationTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await self?.refreshClusters()
                
                try await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds.
            }
        }
    }
    
    func stopPeriodicClusterReEvaluation() {
        if let clusterReEvaluationTask {
            clusterReEvaluationTask.cancel()
        }
        clusterReEvaluationTask = nil
    }
}

typealias KubeConfigPaths = [URL]

extension KubeConfigPaths: RawRepresentable {
    static let decoder = JSONDecoder()
    static let encoder = JSONEncoder()
    
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? Self.decoder.decode(KubeConfigPaths.self, from: data)
        else {
            return nil
        }
        self = result
    }
    
    public var rawValue: String {
        guard let data = try? Self.encoder.encode(self),
              let result = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return result
    }
}

enum WatchResult {
    case ok(WatchedKubeConfig)
    case error(WatchError)
    
    var path: URL {
        switch self {
        case .ok(let watchedKubeConfig): return watchedKubeConfig.path
        case .error(let error): return error.path
        }
    }
    
    var isOK: Bool {
        switch self {
        case .ok(_): return true
        case .error(_): return false
        }
    }
}

class WatchedKubeConfig {
    let path: URL
    var kubeConfig: KubeConfig
    
    var clusters: [Cluster] {
        guard let contexts = kubeConfig.contexts else { return [] }
        return contexts.compactMap { context in
            if let cluster = kubeConfig.clusters?.first(where: { $0.name == context.name }),
               let authInfo = kubeConfig.users?.first(where: { $0.name == context.name }) {
                return Cluster(context: context, cluster: cluster, authInfo: authInfo)
            }
            return nil
        }
    }
    
    init(path: URL, kubeConfig: KubeConfig) {
        self.path = path
        self.kubeConfig = kubeConfig
    }
    
    struct Cluster: @unchecked Sendable {
        let context: NamedContext
        let cluster: NamedCluster
        let authInfo: NamedAuthInfo
        
        func toStoredCluster(
            position: Double,
            kubeConfigDeviceID: UUID,
            kubeConfigDeviceUser: String,
            kubeConfigPath: URL
        ) -> StoredCluster {
            StoredCluster(
                id: UUID(),
                keychain: .localHelper,
                position: position,
                name: context.name,
                
                cluster: cluster.cluster,
                authInfo: authInfo.authInfo,
                
                defaultNamespace: context.context.namespace ?? "default",
                
                kubeConfigDeviceID: kubeConfigDeviceID,
                kubeConfigDeviceUser: kubeConfigDeviceUser,
                kubeConfigPath: kubeConfigPath,
                kubeConfigContextName: context.name,
                credentialsExpireAt: nil,
                lastEvaluation: Date.now
            )
        }
    }
}

class WatchError {
    let path: URL
    let error: String
    
    init(path: URL, error: String) {
        self.path = path
        self.error = error
    }
}

func executeCommand(command: String, arguments: [String]? = nil) throws -> String? {
    let task = Process()

    task.executableURL = URL(fileURLWithPath: command)
    if let arguments {
        task.arguments = arguments
    }

    let outputPipe = Pipe()
    let errorPipe = Pipe()
    task.standardOutput = outputPipe
    task.standardError = errorPipe

    try task.run()

    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    
    let output = String(decoding: outputData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    let error = String(decoding: errorData, as: UTF8.self)
    
    task.waitUntilExit()
    
    if !error.isEmpty {
        throw error
    }

    return output
}
