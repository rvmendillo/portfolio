import Foundation
import CoreNFC

@MainActor
final class NFCService: NSObject, ObservableObject {
    enum Operation { case read, write, erase, lock, inspect }

    @Published var isAvailable = NFCNDEFReaderSession.readingAvailable
    @Published var isScanning = false
    @Published var status = "Ready"
    @Published var lastSnapshot: NFCSnapshot?
    @Published var errorMessage: String?

    weak var store: AppStore?

    private var ndefSession: NFCNDEFReaderSession?
    private var tagSession: NFCTagReaderSession?
    private var operation: Operation = .read
    private var pendingMessage: NFCNDEFMessage?
    private var lockAfterWrite = false

    func read() { startNDEF(.read, alert: "Hold your iPhone near an NFC tag.") }

    func write(records: [NDEFRecordModel], lockAfterWrite: Bool) {
        guard let message = NDEFCodec.message(from: records) else {
            errorMessage = "One or more records could not be encoded."
            return
        }
        pendingMessage = message
        self.lockAfterWrite = lockAfterWrite
        startNDEF(.write, alert: lockAfterWrite ? "Hold near a writable tag. It will be permanently locked after writing." : "Hold near a writable NFC tag.")
    }

    func erase() {
        pendingMessage = NFCNDEFMessage(records: [])
        startNDEF(.erase, alert: "Hold near a writable NFC tag to erase its NDEF message.")
    }

    func lockTag() { startNDEF(.lock, alert: "Hold near a writable tag. Locking is permanent and cannot be undone.") }

    func inspect() {
        guard NFCTagReaderSession.readingAvailable else { errorMessage = "Tag inspection is not available on this device."; return }
        operation = .inspect
        status = "Scanning…"; isScanning = true
        guard let session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693, .iso18092], delegate: self, queue: nil) else {
    errorMessage = "Unable to start the NFC tag reader session."
    isScanning = false
    return
}
        session.alertMessage = "Hold your iPhone near a tag to inspect its protocol and identifier."
        tagSession = session
        session.begin()
    }

    func cancel() { ndefSession?.invalidate(); tagSession?.invalidate(); isScanning = false }

    private func startNDEF(_ op: Operation, alert: String) {
        guard NFCNDEFReaderSession.readingAvailable else { errorMessage = "NFC tag reading is not available on this iPhone."; return }
        operation = op
        status = "Scanning…"; isScanning = true
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = alert
        ndefSession = session
        session.begin()
    }

    private func finish(snapshot: NFCSnapshot?, message: String, session: NFCReaderSession) {
        Task { @MainActor in
            self.status = message
            self.isScanning = false
            if let snapshot { self.lastSnapshot = snapshot; self.store?.addHistory(snapshot) }
        }
        session.alertMessage = message
        session.invalidate()
    }

    private func fail(_ error: Error, session: NFCReaderSession?) {
        Task { @MainActor in
            self.isScanning = false
            let ns = error as NSError
            if ns.domain == NFCReaderError.errorDomain,
               ns.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue { self.status = "Canceled"; return }
            self.errorMessage = error.localizedDescription
            self.status = "Failed"
        }
        session?.invalidate(errorMessage: error.localizedDescription)
    }
}

extension NFCService: NFCNDEFReaderSessionDelegate {
    nonisolated func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {}

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.isScanning = false
            let ns = error as NSError
            if ns.domain == NFCReaderError.errorDomain,
               ns.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue { self.status = "Canceled" }
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard tags.count == 1, let tag = tags.first else { session.alertMessage = "More than one tag detected. Present only one tag."; session.restartPolling(); return }
        session.connect(to: tag) { error in
            if let error { Task { @MainActor in self.fail(error, session: session) }; return }
            tag.queryNDEFStatus { status, capacity, error in
                if let error { Task { @MainActor in self.fail(error, session: session) }; return }
                Task { @MainActor in self.handleNDEF(tag: tag, status: status, capacity: capacity, session: session) }
            }
        }
    }

    private func handleNDEF(tag: NFCNDEFTag, status: NFCNDEFStatus, capacity: Int, session: NFCNDEFReaderSession) {
        let statusName: String = switch status { case .notSupported: "Not supported"; case .readOnly: "Read only"; case .readWrite: "Read / write"; @unknown default: "Unknown" }

        switch operation {
        case .read:
            guard status != .notSupported else { session.invalidate(errorMessage: "This tag does not contain/support NDEF."); isScanning = false; return }
            tag.readNDEF { message, error in
                if let error { Task { @MainActor in self.fail(error, session: session) }; return }
                let records = message?.records.map(NDEFCodec.decode) ?? []
                let snapshot = NFCSnapshot(tagType: "NDEF tag", identifierHex: "Unavailable in NDEF session", ndefStatus: statusName, capacity: capacity, records: records)
                Task { @MainActor in self.finish(snapshot: snapshot, message: "Read \(records.count) record(s).", session: session) }
            }
        case .write, .erase:
            guard status == .readWrite else { session.invalidate(errorMessage: status == .readOnly ? "This tag is read-only." : "This tag does not support NDEF writing."); isScanning = false; return }
            guard let pendingMessage else { session.invalidate(errorMessage: "No message to write."); isScanning = false; return }
            if pendingMessage.length > capacity { session.invalidate(errorMessage: "Payload is \(pendingMessage.length) bytes but this tag has \(capacity) bytes of NDEF capacity."); isScanning = false; return }
            tag.writeNDEF(pendingMessage) { error in
                if let error { Task { @MainActor in self.fail(error, session: session) }; return }
                if self.operation == .write && self.lockAfterWrite {
                    tag.writeLock { lockError in
                        if let lockError { Task { @MainActor in self.fail(lockError, session: session) }; return }
                        Task { @MainActor in self.finish(snapshot: nil, message: "Written and permanently locked read-only.", session: session) }
                    }
                } else {
                    Task { @MainActor in self.finish(snapshot: nil, message: self.operation == .erase ? "NDEF message erased." : "Write complete.", session: session) }
                }
            }
        case .lock:
            guard status == .readWrite else { session.invalidate(errorMessage: "Only writable NDEF tags can be locked."); isScanning = false; return }
            tag.writeLock { error in
                if let error { Task { @MainActor in self.fail(error, session: session) }; return }
                Task { @MainActor in self.finish(snapshot: nil, message: "Tag permanently locked read-only.", session: session) }
            }
        case .inspect:
            break
        }
    }
}

extension NFCService: NFCTagReaderSessionDelegate {
    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.isScanning = false
            let ns = error as NSError
            if ns.domain == NFCReaderError.errorDomain,
               ns.code == NFCReaderError.readerSessionInvalidationErrorUserCanceled.rawValue { self.status = "Canceled" }
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard tags.count == 1, let tag = tags.first else { session.alertMessage = "More than one tag detected."; session.restartPolling(); return }
        session.connect(to: tag) { error in
            if let error { Task { @MainActor in self.fail(error, session: session) }; return }
            Task { @MainActor in self.inspectConnected(tag: tag, session: session) }
        }
    }

    private func inspectConnected(tag: NFCTag, session: NFCTagReaderSession) {
        var type = "Unknown"
        var identifier = ""
        var details: [String: String] = [:]
        let ndefTag: NFCNDEFTag

        switch tag {
        case .iso7816(let t):
            type = "ISO 7816"
            identifier = t.identifier.hex
            details["Historical bytes"] = t.historicalBytes?.hex ?? ""
            details["Initial selected AID"] = t.initialSelectedAID
            ndefTag = t
        case .iso15693(let t):
            type = "ISO 15693"
            identifier = t.identifier.hex
            details["IC manufacturer code"] = String(format: "0x%02X", t.icManufacturerCode)
            details["IC serial"] = t.icSerialNumber.hex
            ndefTag = t
        case .feliCa(let t):
            type = "FeliCa"
            identifier = t.currentIDm.hex
            details["System code"] = t.currentSystemCode.hex
            ndefTag = t
        case .miFare(let t):
            type = "MIFARE"
            identifier = t.identifier.hex
            details["Family"] = String(describing: t.mifareFamily)
            details["Historical bytes"] = t.historicalBytes?.hex ?? ""
            ndefTag = t
        @unknown default:
            session.invalidate(errorMessage: "Unsupported tag type."); isScanning = false; return
        }

        ndefTag.queryNDEFStatus { status, capacity, error in
            let statusName: String
            if error != nil { statusName = "Unknown" }
            else { statusName = switch status { case .notSupported: "Not supported"; case .readOnly: "Read only"; case .readWrite: "Read / write"; @unknown default: "Unknown" } }

            if status == .notSupported || error != nil {
                let snapshot = NFCSnapshot(tagType: type, identifierHex: identifier, ndefStatus: statusName, capacity: capacity, records: [], protocolDetails: details)
                Task { @MainActor in self.finish(snapshot: snapshot, message: "Tag inspected.", session: session) }
                return
            }
            ndefTag.readNDEF { message, _ in
                let records = message?.records.map(NDEFCodec.decode) ?? []
                let snapshot = NFCSnapshot(tagType: type, identifierHex: identifier, ndefStatus: statusName, capacity: capacity, records: records, protocolDetails: details)
                Task { @MainActor in self.finish(snapshot: snapshot, message: "Tag inspected.", session: session) }
            }
        }
    }
}
