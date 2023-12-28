import Foundation
import KeychainAccess

actor Keychain {
    let localHelperKeychain = KeychainAccess.Keychain(service: "io.nautik.Nautik.Helper.Cluster.local")
        .synchronizable(false)
    let iCloudHelperKeychain = KeychainAccess.Keychain(service: "io.nautik.Nautik.Helper.Cluster.iCloud")
        .synchronizable(true)
    
    static let encoder = {
        var encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    
    static let standard = Keychain()
    private init() {}
    
    enum KeychainType: Codable {
        case localHelper, iCloudHelper
    }
    
    func saveCluster(_ cluster: StoredCluster) throws {
        let keychain = switch cluster.keychain {
        case .localHelper: localHelperKeychain
        case .iCloudHelper: iCloudHelperKeychain
        }
        let otherKeychain = switch cluster.keychain {
        case .localHelper: iCloudHelperKeychain
        case .iCloudHelper: localHelperKeychain
        }

        Task.detached {
            let data = try Self.encoder.encode(cluster)
            try keychain
                .label("Kubernetes Cluster \(cluster.name)")
                .comment("Kubernetes Cluster \(cluster.name) stored by Nautik")
                .set(data, key: cluster.id.uuidString)
            
            try otherKeychain.remove(cluster.id.uuidString)
        }
    }
    
    func deleteCluster(_ cluster: StoredCluster) throws {
        let keychain = switch cluster.keychain {
        case .localHelper: localHelperKeychain
        case .iCloudHelper: iCloudHelperKeychain
        }
        
        try keychain.remove(cluster.id.uuidString)
    }
    
    func listClusters() throws -> [StoredCluster] {
        try SyncKeychain.standard.listClusters()
    }
}

struct SyncKeychain {
    let localHelperKeychain = KeychainAccess.Keychain(service: "io.nautik.Nautik.Helper.Cluster.local")
        .synchronizable(false)
    let iCloudHelperKeychain = KeychainAccess.Keychain(service: "io.nautik.Nautik.Helper.Cluster.iCloud")
        .synchronizable(true)
    
    static let decoder = {
        var decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    static let standard = SyncKeychain()
    private init() {}
    
    func listClusters() throws -> [StoredCluster] {
        var clusters = [StoredCluster]()
        
        for keychain in [localHelperKeychain, iCloudHelperKeychain] {
            let data = keychain.allItems() as! [[String: String]]
            
            for dict in data {
                if let key = dict["key"],
                   let clusterString = try? keychain.get(key),
                   let clusterData = clusterString.data(using: .utf8) {
                    if let cluster = try? Self.decoder.decode(StoredCluster.self, from: clusterData) {
                        clusters.append(cluster)
                    } else if let key = dict["key"] {
                        // This is our garbage collection routine, so to speak.
                        // If we fucked up and breakingly changed the stored cluster structure,
                        // delete the stuff we can't deserialize anymore to not leave dead clusters on the keychain.
                        print("Encountered Keychain deserialization error. Deleting entry: \(dict)")
                        try? keychain.remove(key)
                    }
                }
            }
        }
        
        clusters = clusters.filter {
            // Only show clusters that were added by this helper app instance.
            $0.kubeConfigDeviceID == AppState.deviceUUID &&
            $0.kubeConfigDeviceUser == AppState.currentUser
        }
        clusters.sort { $0.position < $1.position }
        
        return clusters
    }
}
