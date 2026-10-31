// Read-only footprint sample of this development app; does not read user text.
import AppKit
import Darwin

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "im.voicetext.inputmethod.VoiceText")
guard !apps.isEmpty else { print("VoiceText 未运行。"); exit(1) }
for app in apps {
    var usage = rusage_info_v4()
    let status = withUnsafeMutablePointer(to: &usage) { pointer in
        pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
            proc_pid_rusage(app.processIdentifier, RUSAGE_INFO_V4, $0)
        }
    }
    guard status == 0 else { print("无法读取 PID \(app.processIdentifier) 的内存（\(errno)）。"); continue }
    print(String(format: "PID %d phys_footprint %.2f MiB, resident %.2f MiB", app.processIdentifier,
                 Double(usage.ri_phys_footprint) / 1048576, Double(usage.ri_resident_size) / 1048576))
}
