import Foundation
import SwiftkubeClient

class StoredCluster {
    var id: UUID
    var position: UInt
    var name: String
    
    var cluster: Cluster
    var authInfo: AuthInfo
    var execCredential: ExecCredential?
    
    var defaultNamespace: String
    
    var externalError: String?
    var error: String?
    
    var kubeConfigPath: URL
    var kubeConfigContextName: String
    
    init(
        id: UUID,
        position: UInt,
        name: String,
        
        cluster: Cluster,
        authInfo: AuthInfo,
        execCredential: ExecCredential? = nil,
        
        defaultNamespace: String,
        
        externalError: String? = nil,
        error: String? = nil,
        
        kubeConfigPath: URL,
        kubeConfigContextName: String
    ) {
        self.id = id
        self.position = position
        self.name = name
        
        self.cluster = cluster
        self.authInfo = authInfo
        self.execCredential = execCredential
        
        self.defaultNamespace = defaultNamespace
        
        self.externalError = externalError
        self.error = error
        
        self.kubeConfigPath = kubeConfigPath
        self.kubeConfigContextName = kubeConfigContextName
    }
}
