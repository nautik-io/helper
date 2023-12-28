import SwiftUI

@main
@MainActor
struct NautikHelperApp: App {
    @State var state = AppState()
    
    // https://damian.fyi/swift/2022/12/29/detecting-when-a-swiftui-menubarextra-with-window-style-is-opened.html
    @State var observer: NSKeyValueObservation?
    
    var body: some Scene {
        MenuBarExtra("Nautik Helper", image: "NautikHelm") {
            MainView(state: state)
                .onAppear {
                    observer = NSApplication.shared.observe(\.keyWindow) { [weak state] x, y in
                        // Refresh clusters when the main window is opened.
                        if NSApplication.shared.keyWindow != nil {
                            Task { [weak state] in
                                await MainActor.run { [weak state] in
                                    state?.refreshClusters()
                                }
                            }
                        }
                    }
                }
        }
        .menuBarExtraStyle(.window)
        
        Window("Manage Clusters", id: "manage-clusters") {
            ManageClustersView(state: state)
        }
        .defaultSize(CGSize(width: 360, height: 400))
    }
}
