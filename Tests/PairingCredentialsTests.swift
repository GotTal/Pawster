import XCTest
@testable import Pawster

final class PairingCredentialsTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    private func remote(identifier: String = "Synthetic-Test-Host") -> [String: Any] {
        ["public_key": Data(repeating: 1, count: 32), "private_key": Data(repeating: 2, count: 32), "identifier": identifier]
    }
    private func plist(_ object: Any, format: PropertyListSerialization.PropertyListFormat = .xml) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: format, options: 0)
    }
    private func lockdown() -> [String: Any] {
        var record: [String: Any] = ["SystemBUID": "Synthetic-BUID", "HostID": "Synthetic-Host", "WiFiMACAddress": "00:00:00:00:00:00"]
        for key in ["DeviceCertificate", "HostCertificate", "RootCertificate", "HostPrivateKey", "RootPrivateKey"] {
            record[key] = Data("Synthetic layout fixture; not a trusted device credential".utf8)
        }
        return record
    }
    func testBothSupportedLayoutsAcceptXMLAndBinaryWithoutRequiringOptionalFields() throws {
        for format in [PropertyListSerialization.PropertyListFormat.xml, .binary] {
            XCTAssertTrue(PairingCredentials.isSupported(try plist(remote(), format: format)))
            XCTAssertTrue(PairingCredentials.isSupported(try plist(lockdown(), format: format)))
        }
    }
    func testUnrelatedMalformedAndOversizedFilesAreNotReady() throws {
        for data in [Data(), Data("broken plist".utf8), try plist(["Wallpaper": "not a pairing record"]), try plist(["an", "array"]), Data(repeating: 0, count: PairingCredentials.maximumBytes + 1)] {
            XCTAssertFalse(PairingCredentials.isSupported(data))
        }
    }
    func testRemoteRecordNeedsCorrectKeyTypesLengthsAndIdentifier() throws {
        for key in ["public_key", "private_key", "identifier"] {
            var record = remote(); record.removeValue(forKey: key)
            XCTAssertFalse(PairingCredentials.isSupported(try plist(record)), key)
        }
        for key in ["public_key", "private_key"] {
            let invalidValues: [Any] = [Data(repeating: 0, count: 31), "not data"]
            for value in invalidValues {
                var record = remote(); record[key] = value
                XCTAssertFalse(PairingCredentials.isSupported(try plist(record)), key)
            }
        }
        XCTAssertFalse(PairingCredentials.isSupported(try plist(remote(identifier: " \n"))))
        var extra = remote(); extra["alt_irk"] = Data(repeating: 3, count: 16); extra["FutureField"] = "allowed"
        XCTAssertTrue(PairingCredentials.isSupported(try plist(extra)))
    }
    func testInspectionIsReadOnlyAndDistinguishesMissingAndInvalid() throws {
        let url = try root().appendingPathComponent("pairing.plist")
        XCTAssertEqual(PairingCredentials.state(at: url), .missing)
        let broken = Data("not plist".utf8); try broken.write(to: url)
        XCTAssertEqual(PairingCredentials.state(at: url), .invalid)
        XCTAssertEqual(try Data(contentsOf: url), broken)
        let ready = try plist(remote()); try ready.write(to: url)
        XCTAssertEqual(PairingCredentials.state(at: url), .ready)
        XCTAssertEqual(try Data(contentsOf: url), ready)
        try PairingDataRemoval.remove(in: url.deletingLastPathComponent())
        XCTAssertEqual(PairingCredentials.state(at: url), .missing)
    }
    func testReadIsBoundedBeforeParsing() throws {
        let url = try root().appendingPathComponent("oversized.plist")
        try Data(repeating: 0, count: PairingCredentials.maximumBytes + 100).write(to: url)
        XCTAssertEqual(try PairingCredentials.read(url).count, PairingCredentials.maximumBytes + 1)
        XCTAssertEqual(PairingCredentials.state(at: url), .invalid)
    }
    func testMissingFileErrorsRecognizeCocoaAndPOSIXWithoutHidingPermissionErrors() {
        for error in [
            NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileNoSuchFile.rawValue),
            NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadNoSuchFile.rawValue),
            NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXError.Code.ENOENT.rawValue))
        ] {
            XCTAssertTrue(PairingCredentials.isMissingFileError(error))
        }
        for error in [
            NSError(domain: NSCocoaErrorDomain, code: CocoaError.Code.fileReadNoPermission.rawValue),
            NSError(domain: NSPOSIXErrorDomain, code: Int(POSIXError.Code.EACCES.rawValue)),
            NSError(domain: "UnrelatedErrorDomain", code: CocoaError.Code.fileNoSuchFile.rawValue)
        ] {
            XCTAssertFalse(PairingCredentials.isMissingFileError(error))
        }
    }
    func testWithoutConsentOnlyPresenceIsReportedWithoutParsingContents() throws {
        let url = try root().appendingPathComponent("pairing.plist")
        XCTAssertEqual(PairingCredentials.state(at: url, allowInspection: false), .missing)
        let bytes = Data("This file must not be parsed before consent".utf8)
        try bytes.write(to: url)
        XCTAssertEqual(PairingCredentials.state(at: url, allowInspection: false), .saved)
        XCTAssertEqual(PairingCredentials.state(at: url, allowInspection: true), .invalid)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    @MainActor
    func testConsentRefreshUpdatesSavedStatusWithoutStartingPairing() throws {
        let url = try root().appendingPathComponent("pairing.plist")
        try plist(remote()).write(to: url)
        let service = PairingService(credentialsURL: url, enablePictureInPicture: false, allowInspection: false)
        XCTAssertEqual(service.credentialState, .saved)
        XCTAssertEqual(service.status, L10n.text("pairing.saved"))
        XCTAssertEqual(service.credentialState.pairAction, L10n.text("action.pairAgain"))
        service.refreshCredentials(allowInspection: true)
        XCTAssertEqual(service.credentialState, .ready)
        XCTAssertEqual(service.status, L10n.text("pairing.ready"))
        service.refreshCredentials(allowInspection: false)
        XCTAssertEqual(service.credentialState, .saved)
        XCTAssertFalse(service.completedSuccessfully); XCTAssertFalse(service.running)
    }
    @MainActor
    func testStartupWithSavedFileIsReadyWithoutClaimingNewPairingSucceeded() throws {
        let url = try root().appendingPathComponent("pairing.plist")
        try plist(remote()).write(to: url)
        let service = PairingService(credentialsURL: url, enablePictureInPicture: false)
        XCTAssertTrue(service.hasCredentials)
        XCTAssertFalse(service.completedSuccessfully); XCTAssertFalse(service.running)
        XCTAssertEqual(service.status, L10n.text("pairing.ready"))
        XCTAssertEqual(service.credentialState.pairAction, L10n.text("action.pairAgain"))
        XCTAssertEqual(service.credentialState.importAction, L10n.text("action.replacePairingFile"))
    }
    @MainActor
    func testMissingAndBrokenFilesHaveAppropriateStartupPrompts() throws {
        let url = try root().appendingPathComponent("pairing.plist")
        let missing = PairingService(credentialsURL: url, enablePictureInPicture: false)
        XCTAssertFalse(missing.hasCredentials)
        XCTAssertEqual(missing.status, L10n.text(missing.supportsOnDevicePairing ? "pairing.notStarted" : "pairing.importRequired"))
        XCTAssertEqual(missing.credentialState.importAction, L10n.text("action.importPairingFile"))
        XCTAssertEqual(missing.credentialState.pairAction, L10n.text("action.startPairing"))
        try Data("broken".utf8).write(to: url)
        let broken = PairingService(credentialsURL: url, enablePictureInPicture: false)
        XCTAssertFalse(broken.hasCredentials)
        XCTAssertEqual(broken.status, L10n.text("pairing.invalidSavedFile"))
        XCTAssertEqual(broken.credentialState.importAction, L10n.text("action.replacePairingFile"))
        XCTAssertEqual(broken.credentialState.pairAction, L10n.text("action.pairAgain"))
    }
    @MainActor
    func testImportedPairingWorksOn26AndNativeAttemptDoesNotStartOrReplaceIt() throws {
        let directory = try root(), url = directory.appendingPathComponent("pairing.plist")
        let source = directory.appendingPathComponent("import.plist")
        let bytes = try plist(lockdown()); try bytes.write(to: source)
        let service = PairingService(credentialsURL: url, enablePictureInPicture: false,
                                    systemVersion: .init(major: 26, minor: 6, patch: 2))
        XCTAssertFalse(service.supportsOnDevicePairing)
        XCTAssertEqual(service.status, L10n.text("pairing.importRequired"))
        service.start()
        XCTAssertFalse(service.running); XCTAssertNil(service.pin)
        XCTAssertEqual(service.guide.phase, .idle)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try service.importCredentials(source)
        XCTAssertTrue(service.hasCredentials)
        service.start()
        XCTAssertFalse(service.running); XCTAssertNil(service.pin)
        XCTAssertEqual(service.guide.phase, .idle)
        XCTAssertTrue(service.hasCredentials)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
    }
    @MainActor
    func testRejectedReplacementPreservesPreviousFileAndReadyState() throws {
        let directory = try root(), url = directory.appendingPathComponent("pairing.plist")
        let previous = try plist(remote()); try previous.write(to: url)
        let source = directory.appendingPathComponent("unrelated.plist")
        try plist(["NotPairing": true]).write(to: source)
        let service = PairingService(credentialsURL: url, enablePictureInPicture: false)
        XCTAssertThrowsError(try service.importCredentials(source))
        XCTAssertEqual(try Data(contentsOf: url), previous)
        XCTAssertTrue(service.hasCredentials)
        XCTAssertEqual(service.status, L10n.text("pairing.ready"))
    }
    @MainActor
    func testImportUpdatesPromptsAndSurvivesRestartWithoutClaimingHandshakeSuccess() throws {
        let directory = try root(), url = directory.appendingPathComponent("pairing.plist")
        let source = directory.appendingPathComponent("import.plist")
        let first = try plist(remote()); try first.write(to: source)
        let service = PairingService(credentialsURL: url, enablePictureInPicture: false)
        try service.importCredentials(source)
        XCTAssertTrue(service.hasCredentials); XCTAssertFalse(service.completedSuccessfully)
        XCTAssertEqual(service.status, L10n.text("pairing.imported"))
        let replacement = try plist(remote(identifier: "Replacement-Host"), format: .binary)
        try replacement.write(to: source); try service.importCredentials(source)
        XCTAssertEqual(try Data(contentsOf: url), replacement)
        let restarted = PairingService(credentialsURL: url, enablePictureInPicture: false)
        XCTAssertTrue(restarted.hasCredentials); XCTAssertFalse(restarted.completedSuccessfully)
        XCTAssertEqual(restarted.status, L10n.text("pairing.ready"))
    }
}
