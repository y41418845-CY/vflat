import SwiftUI
import UIKit

struct CameraScanView: View {
    @EnvironmentObject var vm: ScannerViewModel
    @State private var showingSettings = false
    @State private var showingDetail = false
    @State private var shutterFlash = false
    @State private var errorMessage: String?

    private let accentYellow = Color(red: 0.98, green: 0.82, blue: 0.35)
    private let accentGreen = Color(red: 0.22, green: 0.85, blue: 0.45)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            MetalDewarpViewRepresentable().ignoresSafeArea()
            ScanGuideOverlay(detectedDocument: vm.detectedDocument, motion: vm.motionSensor)
            // auto capture progress
            if vm.isAutoCaptureEnabled {
                Circle()
                    .trim(from: 0, to: vm.autoCaptureProgress)
                    .stroke(accentGreen, lineWidth: 6)
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(-90))
                    .position(x: UIScreen.main.bounds.width/2, y: UIScreen.main.bounds.height - 260)
            }
            // countdown
            if let c = vm.captureCountdown {
                Text("\(c)")
                    .font(.system(size: 120, weight: .thin))
                    .foregroundColor(.white)
            }
            // barcode capsule
            if let bc = vm.detectedBarcode {
                HStack {
                    Image(systemName: bc.iconName)
                    Text(bc.payloadString).lineLimit(1)
                }
                .padding(10)
                .background(Capsule().fill(Color.white.opacity(0.2)))
                .foregroundColor(.white)
                .padding(.top, 100)
            }
            // toolbars
            VStack {
                HStack {
                    Button(action: { showingDetail = true }) {
                        HStack { Image(systemName: "square.and.arrow.up"); Text("PDF \(vm.pageStore.count)") }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.15)))
                            .foregroundColor(.white)
                    }
                    Spacer()
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .padding(10)
                            .background(Circle().fill(Color.white.opacity(0.15)))
                            .foregroundColor(.white)
                    }
                }.padding()
                HStack {
                    // flash
                    Button(action: { vm.cameraManager.setTorch(on: !vm.cameraManager.isTorchOn) }) {
                        Image(systemName: vm.cameraManager.isTorchOn ? "bolt.fill" : "bolt")
                            .foregroundColor(vm.cameraManager.isTorchAvailable ? .white : .gray)
                    }
                    // timer
                    Text("timer").foregroundColor(.white)
                    // auto scan toggle
                    Button(action: { vm.isAutoCaptureEnabled.toggle(); UserDefaults.standard.set(vm.isAutoCaptureEnabled, forKey: "vflat_auto_capture") }) {
                        Text("AUTO SCAN")
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Capsule().fill(vm.isAutoCaptureEnabled ? accentGreen : Color.white.opacity(0.15)))
                            .foregroundColor(.white)
                    }
                    // filter quick
                    Button(action: {}) {
                        HStack { Image(systemName: "slider.horizontal.3").foregroundColor(accentYellow); Text(vm.selectedFilterMode.rawValue) }
                            .foregroundColor(.white)
                    }
                }.padding(.horizontal)
                Spacer()
                ScanControlBar(shutterFlash: $shutterFlash)
            }
            // error banner
            if let msg = vm.errorMessage {
                Text(msg)
                    .foregroundColor(.white)
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(red:0.75,green:0.2,blue:0.2).opacity(0.92)))
                    .padding(.bottom, 40)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            // shutter flash
            if shutterFlash {
                Color.white.ignoresSafeArea().opacity(0.8)
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(isPresented: $showingDetail) { DocumentDetailView() }
    }
}
