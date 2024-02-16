import Foundation
@preconcurrency import SwiftkubeClient
import NIOSSL

class StoredCluster: Codable, @unchecked Sendable {
    var id: UUID
    var keychain: Keychain.KeychainType
    var position: Double
    var name: String

    var cluster: Cluster
    var authInfo: AuthInfo

    var defaultNamespace: String

    var error: String?

    var kubeConfigDeviceID: UUID
    var kubeConfigDeviceUser: String
    var kubeConfigPath: URL
    var kubeConfigContextName: String
    var credentialsExpireAt: Date?
    var lastEvaluation: Date

    init(
        id: UUID,
        keychain: Keychain.KeychainType,
        position: Double,
        name: String,

        cluster: Cluster,
        authInfo: AuthInfo,

        defaultNamespace: String,

        error: String? = nil,

        kubeConfigDeviceID: UUID,
        kubeConfigDeviceUser: String,
        kubeConfigPath: URL,
        kubeConfigContextName: String,
        credentialsExpireAt: Date?,
        lastEvaluation: Date
    ) {
        self.id = id
        self.keychain = keychain
        self.position = position
        self.name = name

        self.cluster = cluster
        self.authInfo = authInfo

        self.defaultNamespace = defaultNamespace

        self.error = error

        self.kubeConfigDeviceID = kubeConfigDeviceID
        self.kubeConfigDeviceUser = kubeConfigDeviceUser
        self.kubeConfigPath = kubeConfigPath
        self.kubeConfigContextName = kubeConfigContextName
        self.credentialsExpireAt = credentialsExpireAt
        self.lastEvaluation = lastEvaluation
    }

    static let decoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    static let encoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    func evaluateAuth() async throws {
        if let caFile = cluster.certificateAuthority {
            let caData = try Data(contentsOf: URL(fileURLWithPath: caFile))
            cluster.certificateAuthorityData = caData
        }

        if let tokenFile = authInfo.tokenFile {
            let token = try String(contentsOf: URL(fileURLWithPath: tokenFile), encoding: .utf8)
            authInfo.token = token
        }

        if let clientCertificateFile = authInfo.clientCertificate {
            let clientCertificateData = try Data(contentsOf: URL(fileURLWithPath: clientCertificateFile))
            authInfo.clientCertificateData = clientCertificateData
        }
        if let clientKeyFile = authInfo.clientKey {
            let clientKeyData = try Data(contentsOf: URL(fileURLWithPath: clientKeyFile))
            authInfo.clientKeyData = clientKeyData
        }

        if let impersonate = authInfo.impersonate {
            // TODO
        }
        if let impersonateGroups = authInfo.impersonateGroups {
            // TODO
        }
        if let impersonateUserExtra = authInfo.impersonateUserExtra {
            // TODO
        }

        if let authProvider = authInfo.authProvider {
            // TODO
        }

        if let exec = authInfo.exec {
            try await Task.detached {
                let credential = try executeExecConfig(exec, cluster: self.cluster, decoder: Self.decoder, encoder: Self.encoder)
                
                await MainActor.run { [weak self] in
                    self?.authInfo.token = credential.status?.token

                    self?.authInfo.clientCertificateData = credential.status?.clientCertificateData.map { $0.data(using: .utf8).map { Data(base64Encoded: $0) } ?? nil } ?? nil
                    self?.authInfo.clientKeyData = credential.status?.clientKeyData.map { $0.data(using: .utf8).map { Data(base64Encoded: $0) } ?? nil } ?? nil

                    self?.credentialsExpireAt = credential.status?.expirationTimestamp
                }
            }
            .value
        } else {
            credentialsExpireAt = nil
        }

        error = nil
        lastEvaluation = Date.now
    }
}

func executeExecConfig(
    _ execConfig: ExecConfig,
    cluster: Cluster,
    decoder: JSONDecoder,
    encoder: JSONEncoder
) throws -> ExecCredential {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    
    // Determine the user's default shell.
    let defaultShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/sh"
    
    // On the kubeconfig spec, the `interactiveMode` field is a string containing
    // either "Never", "IfAvailable", or "Always" and defaulting to "IfAvailable"
    // when unset. So unless we see a "Never", here, we assume interactive mode.
    let interactiveMode = execConfig.interactiveMode == "Never" ? false : true

    // Wrap the command to be executed through the default shell.
    // This ensures the shell environment, including PATH, is used.
    process.executableURL = URL(fileURLWithPath: defaultShell)
    
    let args = execConfig.args?.joined(separator: " ") ?? ""
    var arguments = ["-l", "-c", "\(execConfig.command) \(args)"]
    
    // `-i` doesn't seem to work on bash.
    // TODO: We probably want to implement a better check, specific to more different shells.
    if interactiveMode && !defaultShell.contains("bash") {
        arguments.insert("-i", at: 0)
    }
    
    process.arguments = arguments
    
    // Prepare environment variables, appending or overriding the existing ones.
    var environment = ProcessInfo.processInfo.environment // Start with current environment.
    execConfig.env?.forEach { envVar in
        environment[envVar.name] = envVar.value
    }
    
    if execConfig.provideClusterInfo == true {
        let execCredentialSpec = ExecCredential.Spec(
            interactive: interactiveMode,
            cluster: ExecCredential.Cluster(
                server: cluster.server,
                tlsServerName: cluster.tlsServerName,
                insecureSkipTLSVerify: cluster.insecureSkipTLSVerify,
                certificateAuthorityData: cluster.certificateAuthorityData,
                proxyURL: cluster.proxyURL,
                disableCompression: false // TODO
            )
        )
        let execCredential = ExecCredential(
            apiVersion: execConfig.apiVersion,
            kind: "ExecCredential",
            spec: execCredentialSpec,
            status: nil
        )
        
        let execCredentialData = try encoder.encode(execCredential)
        guard let execCredentialString = String(data: execCredentialData, encoding: .utf8) else {
            throw "Failed to encode KUBERNETES_EXEC_INFO."
        }
        
        environment["KUBERNETES_EXEC_INFO"] = execCredentialString
    }
    
    // Ensure custom environment variables are used.
    process.environment = environment
    
    // Set up the output and error pipes.
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    
    // Launch the process.
    try process.run()
    
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    
    let output = String(decoding: outputData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    let error = String(decoding: errorData, as: UTF8.self)
    
    process.waitUntilExit()
    
    if output == "\(execConfig.command) not found" {
        throw "Executable \(execConfig.command) not found in the user's PATH."
    }
    if !error.isEmpty {
        throw error
    }
    if output.isEmpty {
        throw "Executing \(execConfig.command) yielded no stdout."
    }
    
    do {
        let credential = try decoder.decode(ExecCredential.self, from: Data(output.utf8))
        
        return credential
    } catch {
        // If we fail to decode an exec credential, there's probably
        // an error on the stdout/stderr that is far more valuable
        // to the user than the DecodingError we'd throw.
        throw output
    }
}

// TODO: Upstream this somehow.
struct ExecCredential: Codable {
    let apiVersion: String
    let kind: String
    let spec: Spec?
    let status: Status?
}

extension ExecCredential {
    struct Spec: Codable {
        let interactive: Bool?
        let cluster: Cluster?
    }
    
    // Role model: https://github.com/kubernetes/client-go/blob/master/pkg/apis/clientauthentication/types.go#L80
    struct Cluster: Codable {
        let server: String?
        /// TLSServerName is passed to the server for SNI and is used in the client to
        /// check server certificates against. If ServerName is empty, the hostname
        /// used to contact the server is used.
        /// +optional
        let tlsServerName: String?
        /// InsecureSkipTLSVerify skips the validity check for the server's certificate.
        /// This will make your HTTPS connections insecure.
        /// +optional
        let insecureSkipTLSVerify: Bool?
        /// CAData contains PEM-encoded certificate authority certificates.
        /// If empty, system roots should be used.
        /// +listType=atomic
        /// +optional
        let certificateAuthorityData: Data?
        /// ProxyURL is the URL to the proxy to be used for all requests to this
        /// cluster.
        /// +optional
        let proxyURL: String?
        /// DisableCompression allows client to opt-out of response compression for all requests to the server. This is useful
        /// to speed up requests (specifically lists) when client-server network bandwidth is ample, by saving time on
        /// compression (server-side) and decompression (client-side): https://github.com/kubernetes/kubernetes/issues/112296.
        /// +optional
        let disableCompression: Bool?
        /// Config holds additional config data that is specific to the exec
        /// plugin with regards to the cluster being authenticated to.
        ///
        /// This data is sourced from the clientcmd Cluster object's
        /// extensions[client.authentication.k8s.io/exec] field:
        ///
        /// clusters:
        /// - name: my-cluster
        ///   cluster:
        ///     ...
        ///     extensions:
        ///     - name: client.authentication.k8s.io/exec  # reserved extension name for per cluster exec config
        ///       extension:
        ///         audience: 06e3fbd18de8  # arbitrary config
        ///
        /// In some environments, the user config may be exactly the same across many clusters
        /// (i.e. call this exec plugin) minus some details that are specific to each cluster
        /// such as the audience.  This field allows the per cluster config to be directly
        /// specified with the cluster info.  Using this field to store secret data is not
        /// recommended as one of the prime benefits of exec plugins is that no secrets need
        /// to be stored directly in the kubeconfig.
        /// +optional
//        let config: Any? // TODO
    }

    struct Status: Codable {
        let expirationTimestamp: Date
        let token: String
        let clientCertificateData: String?
        let clientKeyData: String?
    }
}
