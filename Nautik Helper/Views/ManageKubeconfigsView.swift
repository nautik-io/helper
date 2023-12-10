import SwiftUI

struct ManageKubeConfigsView: View {
    @Bindable var model: KubeConfigModel
    
    @State private var isShowingFileImporter = false

    @State private var error: String? = nil
    @State private var selection = Set<URL>()
    
    var body: some View {
        Form {
            if !model.kubeConfigPaths.isEmpty {
                Section("Kubeconfig Files") {
                    List($model.kubeConfigPaths, id: \.self, editActions: [.move], selection: $selection) { kubeConfig in
                        VStack(alignment: .leading) {
                            Label(kubeConfig.wrappedValue.path, systemImage: "doc")
                            
                            if let error = kubeConfig.wrappedValue.kubeConfigError {
                                Text(error)
                                    .font(.footnote)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 6) // Without this, the form spacing is glitchy.
                        .opacity(kubeConfig.wrappedValue.kubeConfigError == nil ? 1 : 0.75)
                    }
                    .contextMenu(forSelectionType: URL.self) { localSelection in
                        Button(action: {
                            model.kubeConfigPaths = model.kubeConfigPaths.filter { !localSelection.contains($0) }
                        }) {
                            Text("Remove File\(localSelection.count > 1 ? "s" : "")")
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
