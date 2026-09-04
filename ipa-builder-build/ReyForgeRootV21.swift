import SwiftUI

struct ReyForgeRootV21: View {
    @EnvironmentObject private var store: StudioStore
    @EnvironmentObject private var github: GitHubBuildManager
    @EnvironmentObject private var signer: BuiltInSigningManager

    @State private var showVibe = false
    @State private var showSigning = false
    @State private var showLocalInstall = false
    @State private var previewProject: StudioProject?

    var body: some View {
        Studio2View()
            .overlay(alignment: .bottomTrailing) {
                Menu {
                    Button {
                        showVibe = true
                    } label: {
                        Label("Vibe Code", systemImage: "sparkles")
                    }

                    Button {
                        previewProject = store.selected
                    } label: {
                        Label("Run Preview", systemImage: "play.rectangle.fill")
                    }

                    Button {
                        showSigning = true
                    } label: {
                        Label("Sign IPA", systemImage: "signature")
                    }

                    Button {
                        showLocalInstall = true
                    } label: {
                        Label("Install Signed IPA", systemImage: "iphone.and.arrow.forward")
                    }
                } label: {
                    Image(systemName: "hammer.circle.fill")
                        .font(.system(size: 46, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .indigo)
                        .shadow(radius: 8, y: 4)
                }
                .padding(.trailing, 16)
                .padding(.bottom, 18)
                .accessibilityLabel("ReyForge Tools")
            }
            .sheet(isPresented: $showVibe) {
                QuickVibeSheet()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showSigning) {
                NavigationStack {
                    ReyForgeSigningPanel()
                        .environmentObject(store)
                        .environmentObject(github)
                        .environmentObject(signer)
                        .navigationTitle("Sign & Export")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showSigning = false }
                            }
                        }
                }
            }
            .sheet(isPresented: $showLocalInstall) {
                ReyForgeLocalInstallSheet()
                    .environmentObject(signer)
            }
            .sheet(item: $previewProject) { project in
                StudioLivePreview(project: project)
            }
    }
}
