import SwiftUI
import CoreNFC

struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }.tabItem { Label("Home", systemImage: "wave.3.right.circle.fill") }
            NavigationStack { WriterView() }.tabItem { Label("Write", systemImage: "square.and.pencil") }
            NavigationStack { HistoryView() }.tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            NavigationStack { TemplatesView() }.tabItem { Label("Templates", systemImage: "square.stack.3d.up.fill") }
            NavigationStack { SettingsView() }.tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(.indigo)
    }
}

struct DashboardView: View {
    @EnvironmentObject var nfc: NFCService
    @EnvironmentObject var store: AppStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Image(systemName: "wave.3.right.circle.fill").font(.system(size: 44)); Spacer(); Text(nfc.isAvailable ? "NFC READY" : "UNAVAILABLE").font(.caption.bold()).padding(8).background(.thinMaterial, in: Capsule()) }
                    Text("NFC Forge").font(.largeTitle.bold())
                    Text("Read, inspect, compose and write standard NFC NDEF tags from one native iPhone app.").foregroundStyle(.secondary)
                }
                .padding(20).frame(maxWidth: .infinity, alignment: .leading).background(.indigo.gradient, in: RoundedRectangle(cornerRadius: 24)).foregroundStyle(.white)

                HStack(spacing: 12) {
                    ActionCard(title: "Read tag", icon: "dot.radiowaves.left.and.right", subtitle: "NDEF records") { nfc.read() }
                    ActionCard(title: "Inspect", icon: "magnifyingglass.circle", subtitle: "Type + UID") { nfc.inspect() }
                }
                HStack(spacing: 12) {
                    NavigationLink { WriterView() } label: { MiniNavCard(title: "Write", icon: "square.and.pencil", subtitle: "Multi-record") }
                    NavigationLink { TemplatesView() } label: { MiniNavCard(title: "Templates", icon: "square.stack.3d.up", subtitle: "Reusable") }
                }

                if let snap = nfc.lastSnapshot {
                    NavigationLink { SnapshotDetailView(snapshot: snap) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Latest scan", systemImage: "checkmark.circle.fill").font(.headline)
                            Text(snap.tagType).font(.title3.bold())
                            Text("\(snap.records.count) record(s) • \(snap.ndefStatus) • \(snap.capacity) B").foregroundStyle(.secondary)
                            if !snap.identifierHex.isEmpty { Text(snap.identifierHex).font(.caption.monospaced()).lineLimit(1).foregroundStyle(.secondary) }
                        }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }.buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Useful limits", systemImage: "info.circle").font(.headline)
                    Text("• One foreground NFC session at a time.\n• Capacity is checked before writing.\n• Lock-to-read-only is permanent.\n• Protected payment/access credentials are not cloned.\n• Some protocol tags require matching Apple entitlements/AIDs.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary, in: RoundedRectangle(cornerRadius: 18))
            }.padding()
        }
        .navigationTitle("NFC Forge")
        .alert("NFC", isPresented: Binding(get: { nfc.errorMessage != nil }, set: { if !$0 { nfc.errorMessage = nil } })) { Button("OK") { nfc.errorMessage = nil } } message: { Text(nfc.errorMessage ?? "") }
    }
}

struct ActionCard: View {
    let title: String; let icon: String; let subtitle: String; let action: () -> Void
    var body: some View { Button(action: action) { MiniNavCard(title: title, icon: icon, subtitle: subtitle) }.buttonStyle(.plain) }
}

struct MiniNavCard: View {
    let title: String; let icon: String; let subtitle: String
    var body: some View { VStack(alignment: .leading, spacing: 10) { Image(systemName: icon).font(.title); Text(title).font(.headline); Text(subtitle).font(.caption).foregroundStyle(.secondary) }.padding().frame(maxWidth: .infinity, minHeight: 120, alignment: .leading).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18)) }
}

struct WriterView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var nfc: NFCService
    @State private var showAdd = false
    @State private var confirmLockWrite = false
    @State private var confirmErase = false

    var body: some View {
        List {
            Section {
                ForEach($store.draftRecords) { $record in
                    NavigationLink { RecordEditorView(record: $record) } label: {
                        VStack(alignment: .leading) { Text(record.kind.rawValue).font(.headline); Text(record.value.isEmpty ? "Tap to edit" : record.value).lineLimit(2).foregroundStyle(.secondary) }
                    }
                }.onDelete { store.draftRecords.remove(atOffsets: $0); if store.draftRecords.isEmpty { store.draftRecords = [.blank()] } }
                Button { showAdd = true } label: { Label("Add record", systemImage: "plus.circle") }
            } header: { Text("NDEF message") } footer: { Text("Estimated encoded size: \(NDEFCodec.byteEstimate(store.draftRecords)) bytes") }

            Section("Write options") {
                Toggle("Permanently lock after writing", isOn: $store.lockAfterWrite).onChange(of: store.lockAfterWrite) { _, _ in store.savePreferences() }
                Button { store.lockAfterWrite ? (confirmLockWrite = true) : nfc.write(records: store.draftRecords, lockAfterWrite: false) } label: { Label("Write to NFC tag", systemImage: "wave.3.right") }
                Button(role: .destructive) { confirmErase = true } label: { Label("Erase NDEF message", systemImage: "eraser") }
            }

            Section("Utilities") {
                if let last = nfc.lastSnapshot, !last.records.isEmpty {
                    Button { store.draftRecords = last.records } label: { Label("Copy latest NDEF into editor", systemImage: "doc.on.doc") }
                }
                Button { nfc.lockTag() } label: { Label("Lock an existing writable tag", systemImage: "lock.fill") }
            }
        }
        .navigationTitle("Write")
        .sheet(isPresented: $showAdd) { AddRecordSheet { store.draftRecords.append(.blank($0)); showAdd = false } }
        .confirmationDialog("Permanent lock", isPresented: $confirmLockWrite, titleVisibility: .visible) {
            Button("Write and lock permanently", role: .destructive) { nfc.write(records: store.draftRecords, lockAfterWrite: true) }
        } message: { Text("After a successful lock, the NFC tag cannot be rewritten.") }
        .confirmationDialog("Erase NDEF", isPresented: $confirmErase, titleVisibility: .visible) { Button("Erase tag", role: .destructive) { nfc.erase() } } message: { Text("This removes the writable NDEF message from the scanned tag where supported.") }
    }
}

struct AddRecordSheet: View {
    let select: (NDEFRecordModel.Kind) -> Void
    @Environment(\.dismiss) var dismiss
    var body: some View { NavigationStack { List(NDEFRecordModel.Kind.allCases) { kind in Button { select(kind) } label: { HStack { Image(systemName: icon(kind)); Text(kind.rawValue); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) } } }.navigationTitle("Add record").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } } }
    func icon(_ kind: NDEFRecordModel.Kind) -> String { switch kind { case .text: "text.alignleft"; case .url: "link"; case .phone: "phone"; case .email: "envelope"; case .sms: "message"; case .location: "location"; case .contact: "person.crop.circle"; case .wifi: "wifi"; case .json: "curlybraces"; case .mime: "doc.badge.gearshape"; case .external: "shippingbox"; case .raw: "number" } }
}

struct RecordEditorView: View {
    @Binding var record: NDEFRecordModel
    var body: some View {
        Form {
            Picker("Record type", selection: $record.kind) { ForEach(NDEFRecordModel.Kind.allCases) { Text($0.rawValue).tag($0) } }
            Section("Content") {
                if record.kind == .contact || record.kind == .json || record.kind == .mime || record.kind == .external || record.kind == .raw {
                    TextEditor(text: $record.value).frame(minHeight: 180).font(record.kind == .raw || record.kind == .json ? .system(.body, design: .monospaced) : .body)
                } else { TextField(placeholder(record.kind), text: $record.value, axis: .vertical).textInputAutocapitalization(.never) }
                if record.kind == .text { TextField("Language code (e.g. en)", text: $record.auxiliary).textInputAutocapitalization(.never) }
                if record.kind == .sms { TextField("Message body", text: $record.auxiliary, axis: .vertical) }
                if record.kind == .wifi { TextField("AUTH;password  e.g. WPA;secret", text: $record.auxiliary).textInputAutocapitalization(.never) }
                if record.kind == .mime || record.kind == .external { TextField(record.kind == .mime ? "MIME type" : "domain:type", text: $record.type).textInputAutocapitalization(.never); TextField("Identifier (hex, optional)", text: $record.identifierHex).textInputAutocapitalization(.never) }
                if record.kind == .raw { TextField("TNF raw value (0–7)", value: $record.tnfRaw, format: .number); TextField("Type bytes (hex)", text: $record.type).textInputAutocapitalization(.never); TextField("Identifier (hex)", text: $record.identifierHex).textInputAutocapitalization(.never); TextField("Payload (hex)", text: $record.payloadHex).textInputAutocapitalization(.never) }
            }
        }.navigationTitle(record.kind.rawValue)
    }
    func placeholder(_ kind: NDEFRecordModel.Kind) -> String { switch kind { case .text: "Text"; case .url: "https://…"; case .phone: "+63…"; case .email: "name@example.com"; case .sms: "+63…"; case .location: "latitude,longitude"; case .contact: "vCard"; case .wifi: "SSID"; default: "Value" } }
}

struct HistoryView: View {
    @EnvironmentObject var store: AppStore
    var body: some View { List { if store.history.isEmpty { ContentUnavailableView("No scans yet", systemImage: "clock", description: Text("Read or inspect an NFC tag and it will appear here.")) } else { ForEach(store.history) { item in NavigationLink { SnapshotDetailView(snapshot: item) } label: { VStack(alignment: .leading) { Text(item.tagType).font(.headline); Text(item.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary); Text("\(item.records.count) record(s) • \(item.ndefStatus)").font(.caption).foregroundStyle(.secondary) } } } } }.navigationTitle("History").toolbar { if !store.history.isEmpty { Button("Clear") { store.clearHistory() } } } }
}

struct SnapshotDetailView: View {
    let snapshot: NFCSnapshot
    @EnvironmentObject var store: AppStore

    var body: some View {
        List {
            Section("Tag") {
                LabeledContent("Type", value: snapshot.tagType)
                LabeledContent("NDEF", value: snapshot.ndefStatus)
                LabeledContent("Capacity", value: "\(snapshot.capacity) bytes")
                if !snapshot.identifierHex.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Identifier / UID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(snapshot.identifierHex)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            if !snapshot.protocolDetails.isEmpty {
                Section("Protocol details") {
                    ForEach(snapshot.protocolDetails.keys.sorted(), id: \.self) { key in
                        LabeledContent(key, value: snapshot.protocolDetails[key] ?? "")
                    }
                }
            }

            Section("Records") {
                if snapshot.records.isEmpty {
                    Text("No NDEF records")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.records) { record in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.kind.rawValue)
                                .font(.headline)
                            Text(record.value)
                                .font(record.kind == .raw ? .caption.monospaced() : .body)
                                .textSelection(.enabled)
                        }
                    }
                    Button {
                        store.draftRecords = snapshot.records
                    } label: {
                        Label("Copy records to writer", systemImage: "doc.on.doc")
                    }
                }
            }
        }
        .navigationTitle("Tag details")
    }
}

struct TemplatesView: View {
    @EnvironmentObject var store: AppStore
    @State private var name = ""
    @State private var savePrompt = false

    var body: some View {
        List {
            Section {
                ForEach(store.templates) { template in
                    Button {
                        store.useTemplate(template)
                    } label: {
                        HStack {
                            Image(systemName: template.icon)
                                .frame(width: 30)
                            VStack(alignment: .leading) {
                                Text(template.name)
                                Text("\(template.records.count) record(s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.down.doc")
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Tap to load into Writer")
            }

            Section {
                Button {
                    savePrompt = true
                } label: {
                    Label("Save current writer draft as template", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Templates")
        .alert("Template name", isPresented: $savePrompt) {
            TextField("Name", text: $name)
            Button("Save") {
                let final = name.trimmingCharacters(in: .whitespacesAndNewlines)
                store.saveCurrentAsTemplate(name: final.isEmpty ? "My template" : final)
                name = ""
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var nfc: NFCService

    var body: some View {
        Form {
            Section("Device") {
                LabeledContent("NFC reading", value: nfc.isAvailable ? "Available" : "Unavailable")
                Text("Core NFC requires a real supported iPhone; simulator scanning is not available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Toggle("Force dark mode", isOn: $store.forceDarkMode)
                    .onChange(of: store.forceDarkMode) { _, _ in
                        store.savePreferences()
                    }
            }

            Section("Safety") {
                Text("NFC Forge is intended for tags you own or are authorized to manage. NDEF copy duplicates standard NDEF records only; it does not extract protected sectors, access credentials or payment-card secrets.")
            }

            Section("About") {
                LabeledContent("App", value: "NFC Forge")
                LabeledContent("Version", value: "1.0.0")
                Text("Native SwiftUI + Core NFC")
            }
        }
        .navigationTitle("Settings")
    }
}
