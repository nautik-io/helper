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

extension URL {
    static let decoder = YAMLDecoder()
    
    var kubeConfigError: String? {
        guard self.startAccessingSecurityScopedResource() else {
            return "Couldn't access the selected file."
        }
        defer { self.stopAccessingSecurityScopedResource() }

        do {
            let yaml = try String(contentsOf: self, encoding: .utf8)
            let _ = try Self.decoder.decode(KubeConfig.self, from: yaml)
        } catch {
            return "Error decoding kubeconfig file: \(error)"
        }
        
        return nil
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
    var validKubeConfigPaths: KubeConfigPaths {
        kubeConfigPaths.filter { $0.kubeConfigError == nil }
    }
    
    var kubeConfigs: [WatchedKubeConfig] {
        validKubeConfigPaths.compactMap { path in
            // TODO: Watch the path continuously.
            
            guard let contents = try? String(contentsOf: path, encoding: .utf8) else {
                return nil
            }
            guard let kubeConfig = try? Self.decoder.decode(KubeConfig.self, from: contents) else {
                return nil
            }
            
            return WatchedKubeConfig(path: path, kubeConfig: kubeConfig)
        }
    }
    
    init() {
        kubeConfigPathsCache = UserDefaults.standard.string(forKey: "kubeconfigs")
            .map { KubeConfigPaths(rawValue: $0) ?? [] } ?? []
    }
}

class WatchedKubeConfig {
    let path: URL
    var kubeConfig: KubeConfig
    
    init(path: URL, kubeConfig: KubeConfig) {
        self.path = path
        self.kubeConfig = kubeConfig
    }
}
