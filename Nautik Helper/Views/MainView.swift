import SwiftUI
import ServiceManagement

struct MainView: View {
    @Bindable var state: AppState
    
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow
    
    @State private var launchAppAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var isShowingAboutPopover = false
    
    @State private var loading = false
    @State private var error: String? = nil
    
    var body: some View {
        VStack {
            titleBar
            clusterList
        }
        .background(.thinMaterial)
        .onChange(of: launchAppAtLogin) { _, newVal in
            newVal ? try? SMAppService.mainApp.register() : try? SMAppService.mainApp.unregister()
        }
    }
    
    @MainActor
    @ViewBuilder
    var clusterList: some View {
        Form {
            if state.clusters.isEmpty {
                Section {
                    Text("No clusters added.")
                    
                    Button {
                        // We have to create a new window for this because
                        // attaching the file importer to the menu bar extra
                        // directly is glitchy on close of the menu bar window.
                        openWindow(id: "manage-clusters")
                    } label: {
                        Label("Add Cluster", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                Section(
                    header: Text("Clusters").padding(.leading, -10),
                    footer: Text("The order of the clusters can be changed on the main app.")
                ) {
                    List($state.clusters, id: \.id) { cluster in
                        ClusterItem(cluster)
                    }
                }
            }
            
            if !state.invalidKubeConfigs.isEmpty {
                Section {
                    Text("\(state.invalidKubeConfigs.count) of your kubeconfig files \(state.invalidKubeConfigs.count > 1 ? "are" : "is") invalid. Visit the cluster settings to resolve the issues.")
                    
                    Button {
                        openWindow(id: "manage-clusters")
                    } label: {
                        Label("Manage Clusters", systemImage: "gear")
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
    func ClusterItem(_ cluster: Binding<StoredCluster>) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Label(cluster.wrappedValue.name, image: "NautikHelm")
                    .labelStyle(ClusterLabelStyle())
                
                Spacer()
                
                ClusterCloudSwitcher(state: state, cluster: cluster)
            }
            
            VStack(spacing: 4) {
                LabeledContent("Path", value: cluster.wrappedValue.kubeConfigPath.path)
                LabeledContent("Context", value: cluster.wrappedValue.kubeConfigContextName)
                if let evaluationExpiration = cluster.wrappedValue.evaluationExpiration {
                    LabeledContent("Expiration") {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            Text(evaluationExpiration, style: .relative)
                        }
                    }
                }
                LabeledContent("Last Evaluation") {
                    Text(cluster.wrappedValue.lastEvaluation, style: .relative)
                }
                
                if let error = cluster.wrappedValue.error {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
            .padding(.leading, 33)
            .font(.callout)
            .opacity(0.75)
        }
        .padding(.vertical, 4)
    }
    
    struct ClusterCloudSwitcher: View {
        @Bindable var state: AppState
        
        @Binding var cluster: StoredCluster
        
        @State private var showCloudSwitcherMenu = false
        
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        
        var body: some View {
            Button {
                showCloudSwitcherMenu.toggle()
            } label: {
                Label({
                    switch cluster.keychain {
                    case .localHelper: return "Local"
                    case .iCloudHelper: return "iCloud"
                    }
                }(), systemImage: "icloud")
                .symbolVariant({
                    switch cluster.keychain {
                    case .localHelper:
                        return .slash
                    case .iCloudHelper:
                        return .none
                    }
                }())
                .frame(height: 12)
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.secondary)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .contentTransition(.symbolEffect(.replace))
            .popover(isPresented: $showCloudSwitcherMenu) {
                Picker("Keychain", selection: $cluster.keychain) {
                    Text("Local").tag(Keychain.KeychainType.localHelper)
                    Text("iCloud").tag(Keychain.KeychainType.iCloudHelper)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .onChange(of: cluster.keychain) { _, _ in
                    Task.detached {
                        try? await Keychain.standard.saveCluster(cluster)
                    }
                }
                .padding(10)
            }
        }
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
                .help("About")
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
                    Button("Manage Clusters") {
                        openWindow(id: "manage-clusters")
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
                .help("Options")
                .labelStyle(.iconOnly)
                .buttonStyle(.accessoryBar)
            }
            
            Divider()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
    }
}
