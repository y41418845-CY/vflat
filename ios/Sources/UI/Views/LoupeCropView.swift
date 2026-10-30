import SwiftUI

#if canImport(UIKit)
import UIKit

/// 手動裁切角點枚舉
public enum CornerPointPosition {
    case topLeft, topRight, bottomRight, bottomLeft
}

/// 帶有放大鏡 (Loupe Magnifier) 的手動 4 角點微調裁切視圖 (對齊 OpenScan 裁切體驗)
public struct LoupeCropView: View {
    public let originalImage: UIImage
    @Binding public var currentDocument: DetectedDocument
    public let onComplete: (DetectedDocument) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var tl: CGPoint
    @State private var tr: CGPoint
    @State private var br: CGPoint
    @State private var bl: CGPoint

    @State private var activeDraggingCorner: CornerPointPosition? = nil

    /// 拖曳手勢使用的具名座標系。
    /// 舊版直接使用預設 `.local`，但角點控制點是以 `.position()` 放在全螢幕 ZStack 內，
    /// 手勢座標會隨控制點自身位移而漂移，導致拖曳時角點「追不上手指」甚至反向跳動。
    private let cropSpaceName = "LoupeCropSpace"

    public init(
        image: UIImage,
        document: Binding<DetectedDocument>,
        onComplete: @escaping (DetectedDocument) -> Void
    ) {
        self.originalImage = image
        self._currentDocument = document
        self.onComplete = onComplete
        let doc = document.wrappedValue
        self._tl = State(initialValue: doc.topLeft)
        self._tr = State(initialValue: doc.topRight)
        self._br = State(initialValue: doc.bottomRight)
        self._bl = State(initialValue: doc.bottomLeft)
    }

    public init(
        sourceImage: UIImage,
        initialDocument: DetectedDocument,
        onApply: @escaping (DetectedDocument) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.originalImage = sourceImage
        self._currentDocument = .constant(initialDocument)
        self.onComplete = onApply
        self._tl = State(initialValue: initialDocument.topLeft)
        self._tr = State(initialValue: initialDocument.topRight)
        self._br = State(initialValue: initialDocument.bottomRight)
        self._bl = State(initialValue: initialDocument.bottomLeft)
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let frame = geo.frame(in: .local)
                let imageAspect = originalImage.size.width / max(originalImage.size.height, 1)
                let viewAspect = frame.width / max(frame.height, 1)

                let renderSize: CGSize = {
                    if imageAspect > viewAspect {
                        return CGSize(width: frame.width, height: frame.width / imageAspect)
                    } else {
                        return CGSize(width: frame.height * imageAspect, height: frame.height)
                    }
                }()

                let renderOrigin = CGPoint(
                    x: (frame.width - renderSize.width) / 2.0,
                    y: (frame.height - renderSize.height) / 2.0
                )

                ZStack {
                    // 1. 底圖
                    Image(uiImage: originalImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: renderSize.width, height: renderSize.height)
                        .position(x: frame.midX, y: frame.midY)

                    // 2. 四邊形外覆蓋半透明遮罩與綠色框線
                    CropPolygonShape(
                        tl: denormalize(tl, in: renderSize, origin: renderOrigin),
                        tr: denormalize(tr, in: renderSize, origin: renderOrigin),
                        br: denormalize(br, in: renderSize, origin: renderOrigin),
                        bl: denormalize(bl, in: renderSize, origin: renderOrigin)
                    )
                    .stroke(Color(red: 0.22, green: 0.85, blue: 0.45), lineWidth: 2.5)

                    // 3. 四個角落控制點 (大觸控範圍)
                    cornerControl(position: .topLeft, normalizedPoint: $tl, renderSize: renderSize, origin: renderOrigin)
                    cornerControl(position: .topRight, normalizedPoint: $tr, renderSize: renderSize, origin: renderOrigin)
                    cornerControl(position: .bottomRight, normalizedPoint: $br, renderSize: renderSize, origin: renderOrigin)
                    cornerControl(position: .bottomLeft, normalizedPoint: $bl, renderSize: renderSize, origin: renderOrigin)

                    // 4. 浮動放大鏡 (Loupe Magnifier)
                    if let active = activeDraggingCorner {
                        let activeNormPoint = pointForCorner(active)
                        let activeScreenPoint = denormalize(activeNormPoint, in: renderSize, origin: renderOrigin)
                        LoupeView(image: originalImage, normalizedCenter: activeNormPoint)
                            .position(x: min(max(activeScreenPoint.x, 60), frame.width - 60), y: max(activeScreenPoint.y - 75, 75))
                    }
                }
                .coordinateSpace(name: cropSpaceName)
            }

            // 頂部導航控制列
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Text("取消")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Text("微調文件角點")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: {
                        let newDoc = DetectedDocument(
                            topLeft: tl,
                            topRight: tr,
                            bottomRight: br,
                            bottomLeft: bl,
                            confidence: 1.0
                        )
                        currentDocument = newDoc
                        onComplete(newDoc)
                        dismiss()
                    }) {
                        Text("完成")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color(red: 0.98, green: 0.82, blue: 0.35))
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()
            }
        }
    }

    private func pointForCorner(_ corner: CornerPointPosition) -> CGPoint {
        switch corner {
        case .topLeft: return tl
        case .topRight: return tr
        case .bottomRight: return br
        case .bottomLeft: return bl
        }
    }

    @ViewBuilder
    private func cornerControl(
        position: CornerPointPosition,
        normalizedPoint: Binding<CGPoint>,
        renderSize: CGSize,
        origin: CGPoint
    ) -> some View {
        let screenPoint = denormalize(normalizedPoint.wrappedValue, in: renderSize, origin: origin)

        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.4), radius: 4)

            Circle()
                .stroke(Color(red: 0.22, green: 0.85, blue: 0.45), lineWidth: 3.5)
                .frame(width: 22, height: 22)
        }
        // 只讓角點本身（含 44pt 觸控熱區）接收手勢，避免四個全螢幕圖層互相搶事件
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .position(screenPoint)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named(cropSpaceName))
                .onChanged { value in
                    activeDraggingCorner = position
                    guard renderSize.width > 0, renderSize.height > 0 else { return }
                    let clampedX = max(origin.x, min(origin.x + renderSize.width, value.location.x))
                    let clampedY = max(origin.y, min(origin.y + renderSize.height, value.location.y))
                    let normX = (clampedX - origin.x) / renderSize.width
                    let normY = (clampedY - origin.y) / renderSize.height
                    normalizedPoint.wrappedValue = CGPoint(x: normX, y: normY)
                }
                .onEnded { _ in
                    activeDraggingCorner = nil
                }
        )
    }

    private func denormalize(_ point: CGPoint, in size: CGSize, origin: CGPoint) -> CGPoint {
        CGPoint(x: origin.x + point.x * size.width, y: origin.y + point.y * size.height)
    }
}

/// 繪製四邊形路徑
struct CropPolygonShape: Shape {
    let tl: CGPoint
    let tr: CGPoint
    let br: CGPoint
    let bl: CGPoint

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: tl)
        path.addLine(to: tr)
        path.addLine(to: br)
        path.addLine(to: bl)
        path.closeSubpath()
        return path
    }
}

/// 圓形放大鏡組件 (2x 局部放大 + 十字準心，消除手指遮擋)
public struct LoupeView: View {
    public let image: UIImage
    public let normalizedCenter: CGPoint
    private let loupeSize: CGFloat = 84.0
    private let zoomFactor: CGFloat = 2.2

    public var body: some View {
        ZStack {
            // 局部放大底圖
            GeometryReader { _ in
                let imgWidth = image.size.width
                let imgHeight = image.size.height
                let scaledWidth = loupeSize * zoomFactor
                let scaledHeight = (loupeSize * zoomFactor) * (imgHeight / max(imgWidth, 1))

                Image(uiImage: image)
                    .resizable()
                    .frame(width: scaledWidth, height: scaledHeight)
                    .offset(
                        x: -(normalizedCenter.x * scaledWidth) + loupeSize / 2,
                        y: -(normalizedCenter.y * scaledHeight) + loupeSize / 2
                    )
            }
            .frame(width: loupeSize, height: loupeSize)
            .clipShape(Circle())

            // 準心
            Rectangle()
                .fill(Color(red: 0.22, green: 0.85, blue: 0.45).opacity(0.8))
                .frame(width: 1, height: loupeSize)
            Rectangle()
                .fill(Color(red: 0.22, green: 0.85, blue: 0.45).opacity(0.8))
                .frame(width: loupeSize, height: 1)

            // 外白邊框
            Circle()
                .stroke(Color.white, lineWidth: 3)
                .frame(width: loupeSize, height: loupeSize)
                .shadow(color: .black.opacity(0.35), radius: 6)
        }
        .frame(width: loupeSize, height: loupeSize)
    }
}
#endif
