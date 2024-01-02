import SwiftUI

struct ManageClustersView: View {
    @Bindable var state: AppState
    
    @State private var isShowingFileImporter = false

    @State private var loading = false
    @State private var error: String? = nil
    @State private var selection = Set<URL>()
    @State private var clusterErrors: [String: String] = [:]
    
    var body: some View {
        Form {
            if !state.kubeConfigs.isEmpty {
                Section("Clusters") {
                    List($state.kubeConfigs, id: \.path, editActions: [.move], selection: $selection) { kubeConfig in
                        VStack(alignment: .leading) {
                            Label(kubeConfig.wrappedValue.path.path, systemImage: "doc")
                            
                            if case let .error(error) = kubeConfig.wrappedValue {
                                Text(error.error)
                                    .font(.footnote)
                                    .foregroundColor(.red)
                                    .padding(.leading, 26)
                            }
                            
                            if case let .ok(watchedKubeConfig) = kubeConfig.wrappedValue {
                                if !watchedKubeConfig.clusters.isEmpty {
                                    List(watchedKubeConfig.clusters, id: \.context.name) { cluster in
                                        VStack {
                                            HStack {
                                                Label(cluster.context.name, image: "NautikHelm")
                                                    .foregroundColor(.primary)
                                                
                                                Spacer()
                                                
                                                Toggle("", isOn: Binding(
                                                    get: {
                                                        state.clusters.contains(where: {
                                                            $0.kubeConfigPath == watchedKubeConfig.path &&
                                                            $0.kubeConfigContextName == cluster.context.name
                                                        })
                                                    },
                                                    set: { addCluster in
                                                        loading = true
                                                        
                                                        if addCluster {
                                                            do {
                                                                clusterErrors["\(watchedKubeConfig.path):\(cluster.context.name)"] = nil
                                                                try state.addCluster(cluster, path: watchedKubeConfig.path)
                                                            } catch {
                                                                clusterErrors["\(watchedKubeConfig.path):\(cluster.context.name)"] = "Error adding cluster: \(error)"
                                                            }
                                                        } else {
                                                            state.removeCluster(path: watchedKubeConfig.path, name: cluster.context.name)
                                                        }
                                                        
                                                        loading = false
                                                    }
                                                ))
                                                .toggleStyle(.checkbox)
                                                .labelsHidden()
                                            }
                                            
                                            if let clusterError = clusterErrors["\(watchedKubeConfig.path):\(cluster.context.name)"] {
                                                Text(clusterError)
                                                    .foregroundColor(.red)
                                                    .font(.footnote)
                                            }
                                        }
                                    }
                                } else {
                                    Text("No Clusters")
                                        .foregroundColor(.secondary)
                                        .padding(.leading, 14)
                                        .padding(.top, 2)
                                }
                            }
                        }
                        .padding(.vertical, 6) // Without this, the form spacing is glitchy.
                        .opacity(kubeConfig.wrappedValue.isOK ? 1 : 0.75)
                    }
                    .contextMenu(forSelectionType: URL.self) { localSelection in
                        Button(action: {
                            state.kubeConfigs = state.kubeConfigs.filter { !localSelection.contains($0.path) }
                        }) {
                            Text("Remove File\(localSelection.count > 1 ? "s" : "") From App")
                        }
                    }
                }
            }
            
            if let error {
                Section {
                    Text(error)
                        .font(.callout)
                        .foregroundColor(.red)
                }
            }
            
            Section(footer: Text("Add kubeconfig files with the file picker. Drag and drop to reorder them. Right-click to remove them.")) {
                Button {
                    self.isShowingFileImporter = true
                } label: {
                    Label("Add Kubeconfig File", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $isShowingFileImporter, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let fileURL):
                self.error = nil
                
                if !state.kubeConfigPaths.contains(fileURL) {
                    state.kubeConfigPaths.append(fileURL)
                }
            case .failure(let error):
                self.error = "Error opening the kubeconfig file: \(error)"
            }
        }
        .overlay {
            if loading {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
