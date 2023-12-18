import Foundation
import SwiftkubeClient
import NIOSSL

extension Cluster {
    func trustRoots() throws -> NIOSSLTrustRoots? {
        if let caFile = certificateAuthority {
            let certificates = try NIOSSLCertificate.fromPEMFile(caFile)
            return NIOSSLTrustRoots.certificates(certificates)
        }
        
        if let caData = certificateAuthorityData {
            let certificates = try NIOSSLCertificate.fromPEMBytes([UInt8](caData))
            return NIOSSLTrustRoots.certificates(certificates)
        }
        
        return nil
    }
}

extension AuthInfo {
    static let decoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    func authentication() throws -> (KubernetesClientAuthentication?, ExecCredential?) {
        if let username = username, let password = password {
            return (.basicAuth(username: username, password: password), nil)
        }
        
        if let token = token {
            return (.bearer(token: token), nil)
        }

        if let tokenFile = tokenFile {
            let fileURL = URL(fileURLWithPath: tokenFile)
            let token = try String(contentsOf: fileURL, encoding: .utf8)
            return (.bearer(token: token), nil)
        }

        if let clientCertificateFile = clientCertificate, let clientKeyFile = clientKey {
            let clientCertificate = try NIOSSLCertificate(file: clientCertificateFile, format: .pem)
            let clientKey = try NIOSSLPrivateKey(file: clientKeyFile, format: .pem)
            return (.x509(clientCertificate: clientCertificate, clientKey: clientKey), nil)
        }

        if let clientCertificateData = clientCertificateData, let clientKeyData = clientKeyData {
            let clientCertificate = try NIOSSLCertificate(bytes: [UInt8](clientCertificateData), format: .pem)
            let clientKey = try NIOSSLPrivateKey(bytes: [UInt8](clientKeyData), format: .pem)
            return (.x509(clientCertificate: clientCertificate, clientKey: clientKey), nil)
        }
        
        if let impersonate {
            // TODO
        }
        if let impersonateGroups {
            // TODO
        }
        if let impersonateUserExtra {
            // TODO
        }
        
        if let authProvider {
            // TODO
        }

        if let exec {
            guard let stdout = try? executeCommand(command: exec.command, arguments: exec.args) else {
                throw "Executing \(exec.command) yielded no stdout."
            }

            let credential = try Self.decoder.decode(ExecCredential.self, from: Data(stdout.utf8))

            return (.bearer(token: credential.status.token), credential)
        }
        
        return (nil, nil)
    }
}

internal struct ExecCredential: Decodable {
    let apiVersion: String
    let kind: String
    let spec: Spec
    let status: Status
}

internal extension ExecCredential {
    struct Spec: Decodable {
        let cluster: Cluster?
        let interactive: Bool?
    }

    struct Status: Decodable {
        let expirationTimestamp: Date
        let token: String
        let clientCertificateData: String?
        let clientKeyData: String?
    }
}

internal func runProcess(command: String, arguments: [String]?, path: String? = nil) throws -> String? {
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

    task.launchPath = command
    if let arguments {
        task.arguments = arguments
    }

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe

    task.launch()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let string = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)

    return string
}

internal func executeCommand(command: String, arguments: [String]?) throws -> String? {
    guard let shell = try runProcess(command: "/usr/bin/env", arguments: ["/bin/sh", "-cl", "echo $SHELL"]) else {
        throw "Couldn't evaluate the user's SHELL."
    }

    if try runProcess(command: "/usr/bin/env", arguments: [shell, "-cl", "eval $(/usr/libexec/path_helper -s) && which \(command)"]) == nil {
        throw "Executable \(command) not found in the user's PATH."
    }

    let stdout = try runProcess(command: "/usr/bin/env", arguments: [shell, "-cl", "eval $(/usr/libexec/path_helper -s) && \(command)\(arguments.map { $0.joined(separator: " ") } ?? "")"])

    return stdout
}
