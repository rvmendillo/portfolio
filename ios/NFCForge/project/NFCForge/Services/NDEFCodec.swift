import Foundation
import CoreNFC

struct NDEFCodec {
    static func encode(_ model: NDEFRecordModel) -> NFCNDEFPayload? {
        switch model.kind {
        case .text:
            return NFCNDEFPayload.wellKnownTypeTextPayload(string: model.value, locale: Locale(identifier: model.auxiliary.isEmpty ? "en" : model.auxiliary))
        case .url:
            return NFCNDEFPayload.wellKnownTypeURIPayload(string: model.value)
        case .phone:
            return NFCNDEFPayload.wellKnownTypeURIPayload(string: "tel:\(model.value)")
        case .email:
            return NFCNDEFPayload.wellKnownTypeURIPayload(string: "mailto:\(model.value)")
        case .sms:
            let body = model.auxiliary.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? model.auxiliary
            return NFCNDEFPayload.wellKnownTypeURIPayload(string: "sms:\(model.value)?body=\(body)")
        case .location:
            return NFCNDEFPayload.wellKnownTypeURIPayload(string: "geo:\(model.value)")
        case .contact:
            return NFCNDEFPayload(format: .media,
                                  type: Data("text/vcard".utf8),
                                  identifier: Data(),
                                  payload: Data(model.value.utf8))
        case .wifi:
            // iOS does not expose a universal OS-level Wi-Fi provisioning writer through NDEF.
            // Store a broadly portable WIFI: text payload used by many tag/QR workflows.
            let escapedSSID = escapeWiFi(model.value)
            let parts = model.auxiliary.split(separator: ";", maxSplits: 1).map(String.init)
            let auth = parts.first ?? "WPA"
            let pass = parts.count > 1 ? parts[1] : ""
            return NFCNDEFPayload.wellKnownTypeTextPayload(string: "WIFI:T:\(auth);S:\(escapedSSID);P:\(escapeWiFi(pass));;", locale: Locale(identifier: "en"))
        case .json:
            return NFCNDEFPayload(format: .media,
                                  type: Data("application/json".utf8),
                                  identifier: Data(),
                                  payload: Data(model.value.utf8))
        case .mime:
            let mime = model.type.isEmpty ? "application/octet-stream" : model.type
            return NFCNDEFPayload(format: .media,
                                  type: Data(mime.utf8),
                                  identifier: dataFromHex(model.identifierHex),
                                  payload: Data(model.value.utf8))
        case .external:
            let ext = model.type.isEmpty ? "example.com:record" : model.type
            return NFCNDEFPayload(format: .nfcExternal,
                                  type: Data(ext.utf8),
                                  identifier: dataFromHex(model.identifierHex),
                                  payload: Data(model.value.utf8))
        case .raw:
            return NFCNDEFPayload(format: NFCTypeNameFormat(rawValue: model.tnfRaw) ?? .unknown,
                                  type: dataFromHex(model.type),
                                  identifier: dataFromHex(model.identifierHex),
                                  payload: dataFromHex(model.payloadHex.isEmpty ? model.value : model.payloadHex))
        }
    }

    static func decode(_ payload: NFCNDEFPayload) -> NDEFRecordModel {
        let (text, locale) = payload.wellKnownTypeTextPayload()
        if let text {
            return .init(kind: .text, value: text, auxiliary: locale?.identifier ?? "")
        }
        if let url = payload.wellKnownTypeURIPayload() {
            let s = url.absoluteString
            if s.hasPrefix("tel:") { return .init(kind: .phone, value: String(s.dropFirst(4))) }
            if s.hasPrefix("mailto:") { return .init(kind: .email, value: String(s.dropFirst(7))) }
            if s.hasPrefix("sms:") { return .init(kind: .sms, value: s) }
            if s.hasPrefix("geo:") { return .init(kind: .location, value: String(s.dropFirst(4))) }
            return .init(kind: .url, value: s)
        }
        let type = String(data: payload.type, encoding: .utf8) ?? payload.type.hex
        if payload.typeNameFormat == .media {
            let body = String(data: payload.payload, encoding: .utf8) ?? payload.payload.hex
            if type.lowercased() == "text/vcard" || type.lowercased() == "text/x-vcard" { return .init(kind: .contact, value: body) }
            if type.lowercased() == "application/json" { return .init(kind: .json, value: body) }
            return .init(kind: .mime, value: body, type: type, identifierHex: payload.identifier.hex, payloadHex: payload.payload.hex, tnfRaw: payload.typeNameFormat.rawValue)
        }
        if payload.typeNameFormat == .nfcExternal {
            return .init(kind: .external, value: String(data: payload.payload, encoding: .utf8) ?? payload.payload.hex, type: type, identifierHex: payload.identifier.hex, payloadHex: payload.payload.hex, tnfRaw: payload.typeNameFormat.rawValue)
        }
        return .init(kind: .raw,
                     value: payload.payload.hex,
                     type: payload.type.hex,
                     identifierHex: payload.identifier.hex,
                     payloadHex: payload.payload.hex,
                     tnfRaw: payload.typeNameFormat.rawValue)
    }

    static func message(from records: [NDEFRecordModel]) -> NFCNDEFMessage? {
        let payloads = records.compactMap(encode)
        guard payloads.count == records.count, !payloads.isEmpty else { return nil }
        return NFCNDEFMessage(records: payloads)
    }

    static func byteEstimate(_ records: [NDEFRecordModel]) -> Int {
        guard let message = message(from: records) else { return 0 }
        return message.length
    }

    private static func escapeWiFi(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ":", with: "\\:")
    }

    static func dataFromHex(_ string: String) -> Data {
        let cleaned = string.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "0x", with: "")
        var data = Data(); var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2, limitedBy: cleaned.endIndex) ?? cleaned.endIndex
            if let byte = UInt8(cleaned[index..<next], radix: 16) { data.append(byte) }
            index = next
        }
        return data
    }
}

extension Data {
    var hex: String { map { String(format: "%02X", $0) }.joined() }
}
