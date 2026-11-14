import Darwin
import Foundation
import SymbiodockCore

/// Lists the running processes. Read-only, and nothing here asks for a permission.
/// Every process is listed with its parent, because the way from a tool up to its terminal
/// app passes through `login`, which belongs to root; the details (path, arguments,
/// folder) are read only for the current user's own processes.
///
/// An actor, because the path of a process is asked for only once and remembered: the
/// scan runs off the main actor, one scan at a time, and the memory belongs to it.
actor ProcessScanner {
    private static let pathBufferSize = 4096
    /// No command line of an agent tool needs more than its first arguments.
    private static let maximumArguments = 16

    /// A process is told apart from a later one that got its pid by the pair of both.
    private struct Identity: Hashable {
        let pid: pid_t
        let seconds: Int
        let microseconds: Int
    }

    /// Executable paths already read, for the processes still running.
    private var paths: [Identity: String] = [:]

    func snapshot() -> [ProcessSnapshot] {
        let uid = getuid()
        var processes: [ProcessSnapshot] = []
        var seen: Set<Identity> = []
        for entry in Self.processTable() {
            let pid = entry.kp_proc.p_pid
            guard pid > 0 else { continue }
            let isOwn = entry.kp_eproc.e_ucred.cr_uid == uid
            let device = entry.kp_eproc.e_tdev
            let started = entry.kp_proc.p_un.__p_starttime
            let identity = Identity(
                pid: pid, seconds: Int(started.tv_sec), microseconds: Int(started.tv_usec))
            var path = ""
            if isOwn {
                seen.insert(identity)
                if let known = paths[identity] {
                    path = known
                } else if let read = Self.executablePath(of: pid) {
                    paths[identity] = read
                    path = read
                }
            }
            processes.append(
                ProcessSnapshot(
                    pid: pid,
                    parentPID: entry.kp_eproc.e_ppid,
                    executablePath: path,
                    startTime: Date(
                        timeIntervalSince1970: TimeInterval(started.tv_sec)
                            + TimeInterval(started.tv_usec) / 1_000_000),
                    // -1 is NODEV: no controlling terminal.
                    terminal: isOwn && device != -1 && device != 0 ? device : nil))
        }
        // Forget the processes that are gone.
        if paths.count > seen.count {
            paths = paths.filter { seen.contains($0.key) }
        }

        // The expensive parts only where they can matter.
        for index in processes.indices where !processes[index].executablePath.isEmpty {
            if processes[index].terminal != nil,
               AgentProcessMatcher.isInterpreter(processes[index].executablePath) {
                processes[index].arguments = Self.arguments(of: processes[index].pid)
            }
            if AgentProcessMatcher.tool(for: processes[index]) != nil {
                processes[index].workingDirectory = Self.workingDirectory(of: processes[index].pid)
            }
        }
        return processes
    }

    /// The kernel's process table, as `ps` reads it.
    private static func processTable() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL]
        let stride = MemoryLayout<kinfo_proc>.stride
        // If many processes start between asking for the size and asking for the table,
        // the second call fails with ENOMEM. Ask again once, with more room, rather than
        // report an empty list, which would make every session vanish for a scan.
        for attempt in 0..<2 {
            var size = 0
            guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
            // Room for processes that start between the two calls.
            var table = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 32 + attempt * 256)
            var used = table.count * stride
            if sysctl(&mib, UInt32(mib.count), &table, &used, nil, 0) == 0 {
                return Array(table.prefix(used / stride))
            }
        }
        return []
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: pathBufferSize)
        let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(length), as: UTF8.self)
    }

    private static func workingDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: &info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }

    /// `argv` of a process, from `KERN_PROCARGS2`: argc, the executable path, padding,
    /// then the arguments, each ending in a zero byte.
    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size
        else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0,
              size > MemoryLayout<Int32>.size
        else { return [] }

        let count = Int(buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }

        var arguments: [String] = []
        while index < size, arguments.count < min(count, maximumArguments) {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
