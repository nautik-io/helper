import Foundation
import SwiftkubeClient
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
            try await Task.detached { [weak self] in
                guard let stdout = try executeCommand(command: exec.command, arguments: exec.args) else {
                    throw "Executing \(exec.command) yielded no stdout."
                }

                do {
                    let credential = try Self.decoder.decode(ExecCredential.self, from: Data(stdout.utf8))

                    await MainActor.run { [weak self] in
                        self?.authInfo.token = credential.status.token

                        self?.authInfo.clientCertificateData = credential.status.clientCertificateData.map { $0.data(using: .utf8).map { Data(base64Encoded: $0) } ?? nil } ?? nil
                        self?.authInfo.clientKeyData = credential.status.clientKeyData.map { $0.data(using: .utf8).map { Data(base64Encoded: $0) } ?? nil } ?? nil

                        self?.credentialsExpireAt = credential.status.expirationTimestamp
                    }
                } catch {
                    // If we fail to decode an exec credential, there's probably
                    // an error on the stdout/stderr that is far more valuable
                    // to the user than the DecodingError we'd throw.
                    throw "\(stdout.utf8)"
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

// TODO: Replace this with the patched upstream `ExecCredential`
struct ExecCredential: Codable, @unchecked Sendable {
    let apiVersion: String
    let kind: String
    let spec: Spec
    let status: Status

    struct Spec: Codable {
        let cluster: Cluster?
        let interactive: Bool?
    }

    struct Status: Codable {
        let expirationTimestamp: Date
        let token: String
        let clientCertificateData: String?
        let clientKeyData: String?
    }
}

func executeCommand(command: String, arguments: [String]? = nil) throws -> String? {
    guard let shell = try runProcess(command: "/usr/bin/env", arguments: ["/bin/sh", "-cl", "echo $SHELL"]) else {
        throw "Couldn't evaluate the user's SHELL."
    }

    guard let cmdPath = try runProcess(command: shell, arguments: ["-cl\(shell.contains("zsh") ? "i" : "")", "which \(command)"]) else {
        throw "Executable \(command) not found in the user's PATH."
    }
    if cmdPath == "\(command) not found" {
        throw "Executable \(command) not found in the user's PATH."
    }

    let stdout = try runProcess(command: shell, arguments: ["-cl\(shell.contains("zsh") ? "i" : "")", "\(cmdPath) \(arguments.map { $0.joined(separator: " ") } ?? "")"])

    return stdout

    func runProcess(command: String, arguments: [String]?, path: String? = nil) throws -> String? {
        let task = Process()

        if let path {
            var env = ProcessInfo.processInfo.environment
            if var existingPath = env["PATH"] {
                existingPath = path + ":" + existingPath
                env["PATH"] = existingPath
            } else {
                env["PATH"] = path
            }
        }

        task.executableURL = URL(fileURLWithPath: command)
        if let arguments {
            task.arguments = arguments
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        try task.run()
        //task.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        
        let output = String(decoding: outputData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let error = String(decoding: errorData, as: UTF8.self)
        
        if !error.isEmpty {
            throw error
        }

        return output
    }
}
