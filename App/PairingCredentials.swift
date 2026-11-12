import Foundation

enum PairingCredentialState: Equatable {
    case missing, saved, ready, invalid

    var hasCredentials: Bool { self == .saved || self == .ready }
    var importAction: String {
        self == .missing ? L10n.text("action.importPairingFile") : L10n.text("action.replacePairingFile")
    }
    var pairAction: String {
        self == .missing ? L10n.text("action.startPairing") : L10n.text("action.pairAgain")
    }
    var initialStatus: String {
        switch self {
        case .missing: return L10n.text("pairing.notStarted")
        case .saved: return L10n.text("pairing.saved")
        case .ready: return L10n.text("pairing.ready")
        case .invalid: return L10n.text("pairing.invalidSavedFile")
        }
    }
}

enum PairingCredentials {
    static let maximumBytes = 1024 * 1024

    static func read(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: maximumBytes + 1) ?? Data()
    }

    static func state(at url: URL, allowInspection: Bool = true) -> PairingCredentialState {
        guard allowInspection else {
            return FileManager.default.fileExists(atPath: url.path) ? .saved : .missing
        }
        do { return isSupported(try read(url)) ? .ready : .invalid }
        catch { return isMissingFileError(error) ? .missing : .invalid }
    }

    static func isMissingFileError(_ error: Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain {
            return error.code == CocoaError.Code.fileNoSuchFile.rawValue
                || error.code == CocoaError.Code.fileReadNoSuchFile.rawValue
        }
        return error.domain == NSPOSIXErrorDomain && error.code == Int(POSIXError.Code.ENOENT.rawValue)
    }

    // Local format checks only. Device trust is checked by the connection handshake.
    // Match both record layouts consumed by Core/src/network.rs, allowing extra fields.
    static func isSupported(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= maximumBytes,
              let record = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] else { return false }
        func bytes(_ key: String) -> Data? { record[key] as? Data }
        func text(_ key: String) -> Bool {
            guard let value = record[key] as? String else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let remote = bytes("public_key")?.count == 32 && bytes("private_key")?.count == 32 && text("identifier")
        let certificates = ["DeviceCertificate", "HostCertificate", "RootCertificate", "HostPrivateKey", "RootPrivateKey"]
        let lockdown = certificates.allSatisfy { !(bytes($0)?.isEmpty ?? true) }
            && ["SystemBUID", "HostID", "WiFiMACAddress"].allSatisfy(text)
        return remote || lockdown
    }
}
