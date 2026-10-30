import SwiftUI
import UIKit
#if canImport(MetalKit)
import MetalKit
#endif

struct MetalDewarpViewRepresentable: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        #if canImport(MetalKit) && !targetEnvironment(simulator)
        let v = MTKView()
        v.backgroundColor = .black
        return v
        #else
        let v = UIView()
        v.backgroundColor = .black
        let label = UILabel()
        label.text = "Metal 預覽 (模擬器不支援)"
        label.textColor = .white
        label.textAlignment = .center
        label.frame = v.bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        v.addSubview(label)
        return v
        #endif
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
