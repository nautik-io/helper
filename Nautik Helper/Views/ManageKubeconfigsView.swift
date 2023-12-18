import SwiftUI

struct ManageKubeConfigsView: View {
    @Bindable var model: KubeConfigModel
    
    @State private var isShowingFileImporter = false

    @State private var error: String? = nil
    @State private var selection = Set<URL>()
    
    var body: some View {
        Form {
            if !model.kubeConfigs.isEmpty {
                Section("Clusters") {
                    List($model.kubeConfigs, id: \.path, editActions: [.move], selection: $selection) { kubeConfig in
                        VStack(alignment: .leading) {
                            Label(kubeConfig.wrappedValue.path.path, systemImage: "doc")
                            
                            if case let .error(error) = kubeConfig.wrappedValue {
                                Text(error.error)
                                    .font(.footnote)
                                    .foregroundColor(.red)
                            }
                            
                            if case let .ok(watchedKubeConfig) = kubeConfig.wrappedValue {
                                List(watchedKubeConfig.clusters, id: \.context.name) { cluster in
                                    HStack {
                                        Label(cluster.context.name, image: "NautikHelm")
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        Toggle("", isOn: Binding(
                                            get: { true },
                                            set: { _, _ in }
                                        ))
                                        .toggleStyle(.checkbox)
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6) // Without this, the form spacing is glitchy.
                        .opacity(kubeConfig.wrappedValue.isOK ? 1 : 0.75)
                    }
                    .contextMenu(forSelectionType: URL.self) { localSelection in
                        Button(action: {
                            model.kubeConfigs = model.kubeConfigs.filter { !localSelection.contains($0.path) }
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
            
            Section(footer: Text("Add your kubeconfig files with the file picker. Drag and drop to reorder them. Right-click to delete them.")) {
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
                
                if !model.kubeConfigPaths.contains(fileURL) {
                    model.kubeConfigPaths.append(fileURL)
                }
            case .failure(let error):
                self.error = "Error opening the kubeconfig file: \(error)"
            }
        }
    }
}
