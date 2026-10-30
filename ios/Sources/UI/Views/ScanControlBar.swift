import SwiftUI

struct ScanControlBar: View {
    @EnvironmentObject var vm: ScannerViewModel
    @Binding var shutterFlash: Bool
    @State private var showFolderPicker = false

    private let accentYellow = Color(red: 0.98, green: 0.82, blue: 0.35)

    var body: some View {
        VStack(spacing: 12) {
            // mode selector
            HStack(spacing: 0) {
                ForEach(["1頁","2頁","自動"], id: \.self) { m in
                    Button(action: {
                        if m == "自動" { vm.isAutoCaptureEnabled = true }
                        else { vm.isAutoCaptureEnabled = false; if m == "2頁" { vm.scanMode = .doublePage } else { vm.scanMode = .single } }
                    }) {
                        Text(m)
                            .font(.caption.bold())
                            .padding(.horizontal, 16).padding(.vertical, 8)
                            .background(Capsule().fill(isSelected(m) ? Color.white.opacity(0.2) : Color.clear))
                            .foregroundColor(isSelected(m) ? accentYellow : .white)
                    }
                }
            }
            .background(Capsule().fill(Color.white.opacity(0.1)))
            // folder
            HStack {
                Image(systemName: "folder")
                Text(UserDefaults.standard.string(forKey: "vflat_current_folder") ?? "Scan")
                Image(systemName: "chevron.down")
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(0.1)))
            // shutter row
            HStack {
                // thumbnail
                ZStack {
                    if let thumb = vm.lastThumbnail {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        Color.gray
                    }
                }
                .frame(width: 48, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white, lineWidth: 2))
                .overlay(alignment: .bottomTrailing) {
                    Text("\(vm.pageStore.count)")
                        .font(.caption2.bold())
                        .padding(2)
                        .background(Capsule().fill(accentYellow))
                        .foregroundColor(.black)
                        .offset(x: 8, y: 8)
                }
                .padding(.leading, 32)
                Spacer()
                // shutter
                Button(action: {
                    withAnimation(.easeOut(duration: 0.08)) { shutterFlash = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        withAnimation(.easeIn(duration: 0.12)) { shutterFlash = false }
                    }
                    Task { await vm.capture() }
                }) {
                    ZStack {
                        Circle().stroke(Color.white, lineWidth: 4.5).frame(width: 76, height: 76)
                        Circle().fill(Color.white).frame(width: 62, height: 62)
                        if vm.isProcessingCapture {
                            ProgressView().tint(.black)
                        } else if let c = vm.captureCountdown {
                            Text("\(c)").foregroundColor(.black)
                        }
                    }
                }
                Spacer()
                // gallery
                Button(action: {}) {
                    Image(systemName: "photo")
                        .font(.system(size: 26))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                }
                .padding(.trailing, 32)
            }
        }
        .padding(.bottom, 20)
    }

    private func isSelected(_ m: String) -> Bool {
        if m == "自動" { return vm.isAutoCaptureEnabled }
        if m == "2頁" { return vm.scanMode == .doublePage && !vm.isAutoCaptureEnabled }
        return vm.scanMode == .single && !vm.isAutoCaptureEnabled
    }
}
