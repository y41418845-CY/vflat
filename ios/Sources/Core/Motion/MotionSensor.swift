import Foundation
import CoreMotion
import Combine

@MainActor
final class MotionSensor: ObservableObject {
    @Published var roll: Double = 0
    @Published var pitch: Double = 0

    private let manager = CMMotionManager()
    private var timer: Timer?

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let m = motion else { return }
            self.roll = m.attitude.roll
            self.pitch = m.attitude.pitch
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
