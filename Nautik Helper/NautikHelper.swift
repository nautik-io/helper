import SwiftUI

@main
struct NautikHelperApp: App {
    @State var model = KubeConfigModel()
    
    var body: some Scene {
        MenuBarExtra("Nautik Helper", image: "NautikHelm") {
            MainView(model: model)
        }
        .menuBarExtraStyle(.window)
        
        Window("Manage Kubeconfigs", id: "manage-kubeconfigs") {
            ManageKubeConfigsView(model: model)
        }
        .defaultSize(CGSize(width: 360, height: 400))
    }
}
