import SwiftUI
import ServiceManagement

struct MainView: View {
    @Bindable var model: KubeConfigModel
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    
    @State private var launchAppAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var isShowingAboutPopover = false
    
    @State private var loading = false
    @State private var error: String? = nil
    
    var body: some View {
        VStack {
            titleBar
            kubeconfigList
        }
        .background(.thinMaterial)
        .onChange(of: launchAppAtLogin) { _, newVal in
            newVal ? try? SMAppService.mainApp.register() : try? SMAppService.mainApp.unregister()
        }
    }
    
    @MainActor
    @ViewBuilder
    var kubeconfigList: some View {
        Form {
            if model.kubeConfigPaths.isEmpty {
                Section {
                    Text("No kubeconfig files added.")
                    
                    Button {
                        // We have to create a new window for this because
                        // attaching the file importer to the menu bar extra
                        // directly is glitchy on close of the menu bar window.
                        openWindow(id: "manage-kubeconfigs")
                    } label: {
                        Label("Add Kubeconfig File", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                ForEach(model.kubeConfigs, id: \.path) { kubeConfig in
                    Section(header: Text(kubeConfig.path.path).padding(.top, -12)) {
                        Text("test")
                    }
                }
            }
            
            if !model.invalidKubeConfigs.isEmpty {
                Section {
                    Text("\(model.invalidKubeConfigs.count) of your kubeconfig files \(model.invalidKubeConfigs.count > 1 ? "are" : "is") invalid. Visit the kubeconfig settings to resolve the issues.")
                    
                    Button {
                        openWindow(id: "manage-kubeconfigs")
                    } label: {
                        Label("Manage Kubeconfigs", systemImage: "gear")
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(-6)
    }
    
    @MainActor
    @ViewBuilder
    var titleBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nautik Helper")
                    .bold()
                
                Spacer()
                
                Button {
                    isShowingAboutPopover.toggle()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
                .foregroundColor(.primary)
                .labelStyle(.iconOnly)
                .buttonStyle(.accessoryBar)
                .popover(isPresented: $isShowingAboutPopover) {
                    VStack {
                        Text("""
                        Nautik Helper continuously evaluates
                        kubeconfig files on your Mac that
                        contain exec plugins and other things
                        incompatible with a sandboxed app
                        to share the resulting auth information
                        with the sandboxed main app.
                        """)
                        .frame(maxWidth: 200)
                        .font(.footnote)
                        .multilineTextAlignment(.leading)
                        
                        Divider()
                        
                        Link("View the source code", destination: URL(string: "https://github.com/nautik-io/helper")!)
                            .font(.callout)
                    }
                    .padding(10)
                }
                
                Menu("Options", systemImage: "switch.2") {
                    Button("Manage Kubeconfigs") {
                        openWindow(id: "manage-kubeconfigs")
                    }
                    Divider()
                    Button("Check for Updates") {
                        
                    }
                    Divider()
                    Toggle("Launch at Login", isOn: $launchAppAtLogin)
                    Button("Quit Nautik Helper") {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.accessoryBar)
            }
            
            Divider()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }
}
