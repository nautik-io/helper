import Foundation
import SwiftUI
import SwiftkubeClient
import Yams

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

//@MainActor
@Observable
class KubeConfigModel {
    static let decoder = YAMLDecoder()
    
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
    
    init() {
        kubeConfigPathsCache = UserDefaults.standard.string(forKey: "kubeconfigs")
            .map { KubeConfigPaths(rawValue: $0) ?? [] } ?? []
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
    
    struct Cluster {
        let context: NamedContext
        let cluster: NamedCluster
        let authInfo: NamedAuthInfo
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
