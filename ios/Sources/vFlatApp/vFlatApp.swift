import SwiftUI

@main
struct vFlatApp: App {
    @StateObject private var viewModel = ScannerViewModel()

    var body: some Scene {
        WindowGroup {
            CameraScanView()
                .environmentObject(viewModel)
        }
    }
}
