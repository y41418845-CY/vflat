import SwiftUI

#if canImport(vFlatUI)
import vFlatUI
#endif

@main
public struct vFlatApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            CameraScanView()
                .preferredColorScheme(.dark)
        }
    }
}
