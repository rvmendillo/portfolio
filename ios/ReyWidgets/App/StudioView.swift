import SwiftUI
import UniformTypeIdentifiers

struct StudioView: View {
    @EnvironmentObject private var studio: StudioModel
    @Binding var path: [UUID]
    @State private var creating = false
    @State private var importing = false
    @State private var pendingDelete: WidgetDocument?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Label("REYWIDGETS", systemImage: "square.grid.2x2.fill")
                        .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2)
                    Spacer()
                    Text("STUDIO 01").font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.muted)
                }.foregroundStyle(Palette.mint)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Your space.\nYour rules.").font(.system(size: 45, weight: .semibold, design: .rounded)).tracking(-2)
                    Text("Create a little window into your world.")
                        .font(.subheadline).foregroundStyle(Palette.muted)
                }
                HStack(spacing: 8) {
                    chip("Native", symbol: "square.stack.3d.up")
                    chip("HTML + CSS", symbol: "chevron.left.forwardslash.chevron.right")
                    chip("Local AI", symbol: "sparkles")
                }
                if !studio.storageReady {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Finish shared storage setup").font(.headline)
                        Text("The app and widget extension need matching App Group entitlements. See the build guide included with this project.").font(.caption).foregroundStyle(Palette.muted)
                        Button("Retry") { studio.open() }.buttonStyle(.bordered)
                    }.padding().background(Palette.card, in: RoundedRectangle(cornerRadius: 20))
                }
                HStack {
                    Text("Your collection").font(.title3.weight(.semibold))
                    Text("\(studio.documents.count)").font(.caption.monospacedDigit()).foregroundStyle(Palette.muted)
                    Spacer()
                    Button { creating = true } label: { Image(systemName: "plus").font(.title3.weight(.medium)) }
                        .accessibilityLabel("Create widget").disabled(!studio.storageReady)
                }.padding(.top, 8)
                if studio.documents.isEmpty && studio.storageReady {
                    ContentUnavailableView("A fresh canvas", systemImage: "square.dashed", description: Text("Tap + to create your first widget."))
                }
                LazyVStack(spacing: 18) {
                    ForEach(studio.documents) { document in
                        Button { path.append(document.id) } label: { CollectionCard(document: document, store: studio.store) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Duplicate", systemImage: "plus.square.on.square") { studio.duplicate(document) }
                                Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = document }
                            }
                    }
                }
                Text("Long-press a design to duplicate or delete it.").font(.caption).foregroundStyle(Palette.muted)
            }.padding(22)
        }
        .background(Palette.background)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import", systemImage: "square.and.arrow.down") { importing = true }.disabled(!studio.storageReady)
            }
        }
        .sheet(isPresented: $creating) { NewDesignSheet { document in
            do { try studio.save(document); creating = false; path.append(document.id) }
            catch { studio.error = error.localizedDescription }
        } }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url): studio.importProject(url)
            case .failure(let error): studio.error = error.localizedDescription
            }
        }
        .confirmationDialog("Delete this widget?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { if let pendingDelete { studio.remove(pendingDelete) }; pendingDelete = nil }
        } message: { Text("Any Home Screen copies will ask you to choose another design.") }
        .navigationTitle("").navigationBarTitleDisplayMode(.inline)
    }
    private func chip(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.system(size: 9, weight: .medium)).padding(.horizontal, 9).padding(.vertical, 8)
            .background(Palette.card, in: Capsule()).foregroundStyle(Palette.muted)
    }
}

struct CollectionCard: View {
    let document: WidgetDocument
    let store: SharedStore?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                if document.mode == .native {
                    NativeWidgetView(design: document.native,
                                     data: store?.cache(document)?.json ?? Data(document.sampleJSON.utf8))
                } else if let revision = document.snapshotRevision,
                          let url = store?.snapshotURL(document.id, revision: revision, size: .medium),
                          let image = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("HTML CANVAS").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2)
                            Text(document.name).font(.title2.weight(.medium))
                            Text("Open the editor to run your design").font(.caption).opacity(0.6)
                        }
                        Spacer()
                        Image(systemName: "curlybraces").font(.system(size: 36, weight: .ultraLight))
                    }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(Color(hex: "#DACBFF"))
                        .background(Color(hex: "#262039"))
                }
            }.frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 24))
            HStack {
                Text(document.name).font(.subheadline.weight(.semibold))
                Spacer()
                Text(document.mode.label.uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.muted)
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Palette.mint)
            }.padding(.horizontal, 4)
        }
    }
}

struct NewDesignSheet: View {
    let create: (WidgetDocument) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = "My widget"
    @State private var mode: WidgetMode = .native
    var body: some View {
        NavigationStack {
            Form {
                Section("A new canvas") {
                    TextField("Name", text: $name)
                    Picker("Renderer", selection: $mode) { ForEach(WidgetMode.allCases) { Text($0.label).tag($0) } }
                        .pickerStyle(.segmented)
                }
                Section {
                    Label(mode == .native ? "Fast, crisp SwiftUI layouts with background API refresh." : "Design in HTML, CSS and JavaScript. Publish a Home Screen snapshot.",
                          systemImage: mode == .native ? "square.stack.3d.up" : "curlybraces")
                }
                Button("Create widget") { var doc = WidgetDocument(); doc.name = name; doc.mode = mode; create(doc) }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .navigationTitle("Make something yours")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct TemplateGallery: View {
    @EnvironmentObject private var studio: StudioModel
    @State private var templates = Templates.all
    @State private var selected: WidgetDocument?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("A place to start.").font(.largeTitle.weight(.semibold))
                Text("Six editable designs. Every detail is yours to change.").foregroundStyle(Palette.muted)
                ForEach(templates) { doc in
                    Button { selected = doc } label: { CollectionCard(document: doc, store: nil) }.buttonStyle(.plain)
                }
            }.padding(22)
        }.background(Palette.background).navigationTitle("Discover").navigationBarTitleDisplayMode(.inline)
            .sheet(item: $selected) { document in
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 20) {
                            if document.mode == .html {
                                HTMLPreview(page: HTMLRuntime.page(document, data: Data(document.sampleJSON.utf8), size: .medium))
                                    .frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 24))
                            } else { CollectionCard(document: document, store: nil) }
                            Text("Includes editable source and sample data. API templates start with networking turned off.").font(.subheadline).foregroundStyle(Palette.muted)
                            Button("Add to my studio", systemImage: "plus") {
                                var copy = document; copy.id = UUID(); copy.api.credentialID = UUID().uuidString
                                do { try studio.save(copy); selected = nil }
                                catch { studio.error = error.localizedDescription }
                            }.buttonStyle(.borderedProminent).foregroundStyle(.black).disabled(!studio.storageReady)
                        }.padding(22)
                    }.navigationTitle(document.name)
                        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { selected = nil } } }
                }
            }
    }
}
