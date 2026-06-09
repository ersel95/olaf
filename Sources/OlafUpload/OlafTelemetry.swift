import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Network)
import Network
#endif

/// Raporun alındığı andaki anlık cihaz durumunu (telemetri) toplar.
/// Tamamen cihaz-durumu — IP / SSID / konum / kişisel hiçbir veri içermez.
public enum OlafTelemetry {

    /// Erken hazırlık: pil izlemeyi açar ve network monitor'ü başlatır.
    /// Bug-reporter aktifleşince (banner kurulurken) bir kez çağrılır; böylece ilk
    /// raporda pil seviyesi/ağ tipi dolu gelir.
    @MainActor
    public static func prepare() {
        #if canImport(UIKit)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
        OlafNetworkMonitor.shared.start()
    }

    /// Anlık telemetriyi toplar. UIKit alanları için MainActor.
    @MainActor
    public static func capture() -> OlafReportPayload.Telemetry {
        let disk = diskBytes()
        return OlafReportPayload.Telemetry(
            timezone: TimeZone.current.identifier,
            screenScale: screenScale(),
            screenPoints: screenPoints(),
            networkType: OlafNetworkMonitor.shared.current,
            batteryLevel: batteryLevel(),
            batteryState: batteryState(),
            lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
            thermalState: thermalStateString(),
            orientation: orientationString(),
            freeDiskBytes: disk.free,
            totalDiskBytes: disk.total,
            totalMemoryBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            appMemoryBytes: appMemoryBytes()
        )
    }

    // MARK: - Ekran

    @MainActor
    private static func screenScale() -> Double? {
        #if canImport(UIKit)
        return Double(UIScreen.main.scale)
        #else
        return nil
        #endif
    }

    @MainActor
    private static func screenPoints() -> String? {
        #if canImport(UIKit)
        let b = UIScreen.main.bounds
        return "\(Int(b.width))x\(Int(b.height))"
        #else
        return nil
        #endif
    }

    // MARK: - Pil

    @MainActor
    private static func batteryLevel() -> Int? {
        #if canImport(UIKit)
        let level = UIDevice.current.batteryLevel
        guard level >= 0 else { return nil }   // -1 = monitoring kapalı / bilinmiyor
        return Int((level * 100).rounded())
        #else
        return nil
        #endif
    }

    @MainActor
    private static func batteryState() -> String? {
        #if canImport(UIKit)
        switch UIDevice.current.batteryState {
        case .charging: return "charging"
        case .full: return "full"
        case .unplugged: return "unplugged"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
        #else
        return nil
        #endif
    }

    // MARK: - Termal

    private static func thermalStateString() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Yön

    @MainActor
    private static func orientationString() -> String? {
        #if canImport(UIKit)
        switch UIDevice.current.orientation {
        case .portrait: return "portrait"
        case .portraitUpsideDown: return "portraitUpsideDown"
        case .landscapeLeft: return "landscapeLeft"
        case .landscapeRight: return "landscapeRight"
        case .faceUp: return "faceUp"
        case .faceDown: return "faceDown"
        case .unknown: return "unknown"
        @unknown default: return "unknown"
        }
        #else
        return nil
        #endif
    }

    // MARK: - Disk

    private static func diskBytes() -> (free: Int64?, total: Int64?) {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        guard
            let values = try? url.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey,
            ])
        else {
            return (nil, nil)
        }
        let free = values.volumeAvailableCapacityForImportantUsage
        let total = values.volumeTotalCapacity.map(Int64.init)
        return (free, total)
    }

    // MARK: - Uygulama belleği (mach phys_footprint)

    private static func appMemoryBytes() -> Int64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return Int64(info.phys_footprint)
    }
}

/// Sürekli çalışan ağ yolu izleyici. `pathUpdateHandler` en güncel arayüz tipini cache'ler;
/// telemetri toplanırken senkron okunur. IP/SSID toplamaz — yalnız arayüz tipi.
final class OlafNetworkMonitor: @unchecked Sendable {

    static let shared = OlafNetworkMonitor()

    private let lock = NSLock()
    private var _type: String = "unknown"
    private var started = false

    #if canImport(Network)
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.olaf.network.monitor")
    #endif

    var current: String {
        lock.lock(); defer { lock.unlock() }
        return _type
    }

    func start() {
        lock.lock()
        if started {
            lock.unlock()
            return
        }
        started = true
        lock.unlock()

        #if canImport(Network)
        monitor.pathUpdateHandler = { [weak self] path in
            self?.set(Self.classify(path))
        }
        monitor.start(queue: queue)
        #endif
    }

    private func set(_ value: String) {
        lock.lock(); _type = value; lock.unlock()
    }

    #if canImport(Network)
    private static func classify(_ path: NWPath) -> String {
        guard path.status == .satisfied else { return "none" }
        if path.usesInterfaceType(.wifi) { return "wifi" }
        if path.usesInterfaceType(.cellular) { return "cellular" }
        if path.usesInterfaceType(.wiredEthernet) { return "wired" }
        return "other"
    }
    #endif
}
