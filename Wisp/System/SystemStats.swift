import AppKit
import CoreLocation
import CoreWLAN
import Darwin
import IOKit.ps

/// Battery, AirPods, CPU and storage for the System tab (board 7).
///
/// Everything is read only while the tab is visible: `setVisible(true)` reads it all
/// once and then samples the CPU every two seconds; `setVisible(false)` stops.
@MainActor
final class SystemStats: NSObject, ObservableObject {
    static let shared = SystemStats()

    struct Battery: Equatable {
        var percent: Int
        var charging: Bool
        var onAC: Bool
        /// Minutes until empty (on battery) or full (charging); nil while macOS works it out.
        var minutes: Int?
    }

    struct Buds: Equatable {
        var name: String
        var left: Int?
        var right: Int?
        var caseLevel: Int?
    }

    struct Storage: Equatable {
        var free: Int64
        var total: Int64
    }

    @Published private(set) var battery: Battery?
    @Published private(set) var hasBattery = true
    @Published private(set) var buds: Buds?
    @Published private(set) var cpu: Double?
    /// The last 20 CPU samples (40 s), oldest first.
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var topProcess: (name: String, percent: Double)?
    @Published private(set) var storage: Storage?
    @Published private(set) var wifiName: String?
    @Published private(set) var wifiOn = false
    @Published private(set) var locationAllowed = false

    private var timer: Timer?
    private var lastTicks: [UInt32]?
    private var lastProcessTimes: [pid_t: UInt64] = [:]
    private var lastSample: UInt64 = 0
    private var budsTask: Task<Void, Never>?
    private lazy var location = CLLocationManager()

    private static let cores = Double(ProcessInfo.processInfo.activeProcessorCount)

    func setVisible(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else {
            budsTask?.cancel()
            return
        }
        readBattery()
        readStorage()
        readWiFi()
        readBuds()
        sampleCPU()
        var ticks = 0
        let timer = Timer(timeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated {
                let stats = SystemStats.shared
                stats.sampleCPU()
                ticks += 1
                // The rest changes slowly: every 20 seconds is plenty.
                if ticks % 10 == 0 {
                    stats.readBattery()
                    stats.readWiFi()
                    stats.readBuds()
                }
            }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - Battery (IOKit power sources)

    private func readBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.lazy.compactMap({
                  IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
              }).first(where: { ($0[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType })
        else {
            hasBattery = false
            battery = nil
            return
        }
        let current = source[kIOPSCurrentCapacityKey] as? Int ?? 0
        let max = source[kIOPSMaxCapacityKey] as? Int ?? 100
        let charging = source[kIOPSIsChargingKey] as? Bool ?? false
        let onAC = (source[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        let minutes = charging ? source[kIOPSTimeToFullChargeKey] as? Int : source[kIOPSTimeToEmptyKey] as? Int
        battery = Battery(percent: max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current,
                          charging: charging, onAC: onAC,
                          minutes: minutes.flatMap { $0 > 0 ? $0 : nil })
    }

    // MARK: - Storage

    private func readStorage() {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys),
              let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return }
        storage = Storage(free: free, total: Int64(total))
    }

    // MARK: - Wi-Fi

    private func readWiFi() {
        let interface = CWWiFiClient.shared().interface()
        wifiOn = interface?.powerOn() ?? false
        // macOS hands out the network name only to apps with Location access.
        wifiName = interface?.ssid()
        locationAllowed = [.authorized, .authorizedAlways].contains(location.authorizationStatus)
    }

    /// Settings shows whether the name is allowed, also while the tab is closed.
    func refreshWiFi() { readWiFi() }

    /// Asks for Location access, which macOS requires before it gives the Wi-Fi name.
    func requestWiFiName() {
        location.delegate = self
        location.requestWhenInUseAuthorization()
    }

    // MARK: - AirPods (system_profiler)

    /// AirPods report their batteries to macOS, and `system_profiler` passes them on;
    /// there's no public API for it. Best effort: only connected headphones with levels.
    private func readBuds() {
        budsTask?.cancel()
        budsTask = Task.detached(priority: .utility) {
            let found = Self.connectedBuds()
            await MainActor.run {
                guard !Task.isCancelled else { return }
                SystemStats.shared.buds = found
            }
        }
    }

    nonisolated private static func connectedBuds() -> Buds? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let controllers = json["SPBluetoothDataType"] as? [[String: Any]] else { return nil }
        for controller in controllers {
            for device in controller["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in device {
                    guard let info = value as? [String: Any] else { continue }
                    func level(_ key: String) -> Int? {
                        (info[key] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) }
                    }
                    let buds = Buds(name: name, left: level("device_batteryLevelLeft"),
                                    right: level("device_batteryLevelRight"),
                                    caseLevel: level("device_batteryLevelCase"))
                    if buds.left != nil || buds.right != nil { return buds }
                }
            }
        }
        return nil
    }

    // MARK: - CPU

    private func sampleCPU() {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var load = host_cpu_load_info_data_t()
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else { return }
        let ticks = [load.cpu_ticks.0, load.cpu_ticks.1, load.cpu_ticks.2, load.cpu_ticks.3]
        if let last = lastTicks {
            let delta = zip(ticks, last).map { Double($0 &- $1) }
            // user, system, idle, nice
            let busy = delta[0] + delta[1] + delta[3]
            let all = busy + delta[2]
            if all > 0 {
                let value = busy / all * 100
                cpu = value
                cpuHistory = Array((cpuHistory + [value]).suffix(20))
            }
        }
        lastTicks = ticks
        sampleProcesses()
    }

    /// The busiest app since the last sample, counting helper processes with their app.
    private func sampleProcesses() {
        let now = mach_absolute_time()
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return }
        var pids = [pid_t](repeating: 0, count: Int(count) + 32)
        let filled = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard filled > 0 else { return }

        var times: [pid_t: UInt64] = [:]
        var usage: [String: UInt64] = [:]
        for pid in pids.prefix(Int(filled)) where pid > 0 {
            var info = rusage_info_v2()
            let ok = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                    proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
                }
            }
            guard ok == 0 else { continue }
            let total = info.ri_user_time + info.ri_system_time
            times[pid] = total
            if let before = lastProcessTimes[pid], total > before {
                usage[Self.appName(pid), default: 0] += total - before
            }
        }
        let elapsed = now - lastSample
        if lastSample > 0, elapsed > 0, let top = usage.max(by: { $0.value < $1.value }) {
            // Process times and mach_absolute_time share the same units.
            let percent = Double(top.value) / Double(elapsed) / Self.cores * 100
            topProcess = (top.key, percent)
        }
        lastProcessTimes = times
        lastSample = now
    }

    private static func appName(_ pid: pid_t) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), let name = app.localizedName {
            return name
        }
        var buffer = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buffer, UInt32(buffer.count))
        let name = String(cString: buffer)
        // "Google Chrome Helper (Renderer)" counts as "Google Chrome".
        if let range = name.range(of: " Helper") { return String(name[..<range.lowerBound]) }
        return name.isEmpty ? "?" : name
    }
}

extension SystemStats: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in SystemStats.shared.readWiFi() }
    }
}
