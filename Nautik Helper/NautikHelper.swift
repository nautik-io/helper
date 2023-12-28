import SwiftUI

@main
@MainActor
struct NautikHelperApp: App {
    @State var state = AppState()
    
    var body: some Scene {
        MenuBarExtra("Nautik Helper", image: "NautikHelm") {
            MainView(state: state)
        }
        .menuBarExtraStyle(.window)
        
        Window("Manage Clusters", id: "manage-clusters") {
            ManageClustersView(state: state)
        }
        .defaultSize(CGSize(width: 360, height: 400))
    }
}
