import Foundation
import CoreMotion

/// 負責即時監控 iPhone 水平與傾斜姿態之感測器管理器
/// 取代原版 vFlat libnative-scan.so 中依賴二進位矩陣推算之 calcEulerAngleFromMatrix
public final class MotionSensor: ObservableObject {
    private let motionManager = CMMotionManager()
    private let updateInterval: TimeInterval = 1.0 / 60.0 // 60Hz 採樣率

    @Published public private(set) var rollDegrees: Double = 0.0
    @Published public private(set) var pitchDegrees: Double = 0.0
    @Published public private(set) var tiltAngle: Double = 0.0
    @Published public private(set) var isLevel: Bool = true

    /// 判定手機為水平對齊書本之容許閥值 (單位：度)
    public var levelThresholdDegrees: Double = 8.0

    public init() {}

    /// 啟動裝置姿態偵測
    public func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("[MotionSensor] 此裝置不支援 DeviceMotion 感測")
            return
        }

        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion, error == nil else { return }

            let attitude = motion.attitude
            let roll = attitude.roll * 180.0 / .pi
            let pitch = attitude.pitch * 180.0 / .pi

            // 計算距離純水平俯拍 (Pitch = -90 度 或 90 度) 之偏角
            let pitchOffset = abs(abs(pitch) - 90.0)
            let rollOffset = abs(roll)
            let totalTilt = sqrt(pitchOffset * pitchOffset + rollOffset * rollOffset)

            self.rollDegrees = roll
            self.pitchDegrees = pitch
            self.tiltAngle = totalTilt
            self.isLevel = totalTilt <= self.levelThresholdDegrees
        }
    }

    /// 停止裝置姿態偵測
    public func stopUpdates() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }
}
