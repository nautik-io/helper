import Foundation
import SwiftUI
import SwiftkubeClient
import Yams

@MainActor
@Observable
class AppState {
    static let decoder = YAMLDecoder()
    
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
    }
    
    func refreshClusters() {
        Task.detached { [weak self] in
            do {
                guard let self else { return }
                
                let clusters = try await Keychain.standard.listClusters()
                
                await MainActor.run { [weak self] in
                    self?.clusters = clusters
                }
            } catch {
                print("Error reloading clusters from keychain: \(error)")
            }
        }
    }
    
    func addCluster(_ cluster: WatchedKubeConfig.Cluster, path kubeConfigPath: URL) throws {
        let lastPosition = self.clusters.last?.position ?? 0
        let newPosition = Double.random(in: lastPosition + 0.000001...lastPosition + 0.2)
        let newCluster = cluster.toStoredCluster(
            position: newPosition,
            kubeConfigDeviceID: AppState.deviceUUID,
            kubeConfigDeviceUser: AppState.currentUser,
            kubeConfigPath: kubeConfigPath
        )
        
        try newCluster.evaluateAuth()
        
        self.clusters.append(newCluster)
        
        Task.detached {
            try? await Keychain.standard.saveCluster(newCluster)
        }
    }
    
    func removeCluster(path kubeConfigPath: URL, name kubeConfigContextName: String) {
        guard let clusterToRemove = self.clusters.first(where: {
            $0.kubeConfigPath == kubeConfigPath && 
            $0.kubeConfigContextName == kubeConfigContextName
        }) else { return }
        
        self.clusters = self.clusters.filter { $0.id != clusterToRemove.id }
        
        Task.detached {
            try? await Keychain.standard.deleteCluster(clusterToRemove)
        }
    }
}

typealias KubeConfigPaths = [URL]

extension KubeConfigPaths: RawRepresentable {
    public init?(rawValue: String) {
        guard let data = rawValue.data(using: .utf8),
              let result = try? JSONDecoder().decode(KubeConfigPaths.self, from: data)
        else {
            return nil
        }
        self = result
    }
    
    public var rawValue: String {
        guard let data = try? JSONEncoder().encode(self),
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

struct WatchedKubeConfig {
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
                evaluationExpiration: nil,
                lastEvaluation: Date.now
            )
        }
    }
}

struct WatchError {
    let path: URL
    let error: String
    
    init(path: URL, error: String) {
        self.path = path
        self.error = error
    }
}
