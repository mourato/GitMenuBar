import Foundation
#if canImport(Darwin)
    import Darwin
#endif

enum AntigravityProcessDetector {
    struct DetectedServer: Sendable, Equatable {
        let pid: Int
        let port: Int
        let csrfToken: String?
    }

    /// Finds running Antigravity instances (IDE, App, or CLI) and their listening localhost ports.
    static func detectRunningServers() -> [DetectedServer] {
        #if canImport(Darwin)
            let pids = allPIDs()
            var servers: [DetectedServer] = []

            for pid in pids {
                guard let exePath = executablePath(pid: pid),
                      isAntigravityCandidatePath(exePath)
                else {
                    continue
                }

                let cmdLine = commandLine(pid: pid) ?? exePath
                guard isAntigravityCommand(cmdLine: cmdLine, exePath: exePath) else {
                    continue
                }

                let csrfToken = extractCSRFToken(from: cmdLine)
                let ports = listeningTCPPorts(pid: pid)

                for port in ports {
                    servers.append(DetectedServer(
                        pid: Int(pid),
                        port: port,
                        csrfToken: csrfToken
                    ))
                }
            }

            return servers
        #else
            return []
        #endif
    }

    static func isAntigravityCandidatePath(_ path: String) -> Bool {
        let lower = path.lowercased()
        if lower.contains("antigravity") {
            return true
        }
        let basename = URL(fileURLWithPath: lower).lastPathComponent
        return basename.hasPrefix("language_server") ||
            basename.hasPrefix("language-server") ||
            ["agy", "antigravity-cli", "antigravity_cli"].contains(basename)
    }

    static func isAntigravityCommand(cmdLine: String, exePath: String) -> Bool {
        let lowerCmd = cmdLine.lowercased()
        let lowerPath = exePath.lowercased()

        if lowerCmd.contains("antigravity") || lowerPath.contains("antigravity") {
            return true
        }

        if lowerCmd.contains("language_server"), lowerCmd.contains("codeium") || lowerCmd.contains("exa") {
            return true
        }

        return false
    }

    static func extractCSRFToken(from commandLine: String) -> String? {
        let patterns = [
            #"--csrf_token\s+([A-Za-z0-9\-_]+)"#,
            #"--csrf-token\s+([A-Za-z0-9\-_]+)"#,
            #"--csrf_token=([A-Za-z0-9\-_]+)"#,
            #"--csrf-token=([A-Za-z0-9\-_]+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(commandLine.startIndex..., in: commandLine)
            if let match = regex.firstMatch(in: commandLine, range: range),
               let tokenRange = Range(match.range(at: 1), in: commandLine)
            {
                return String(commandLine[tokenRange])
            }
        }
        return nil
    }

    #if canImport(Darwin)
        private static func allPIDs() -> [Int32] {
            let count = proc_listallpids(nil, 0)
            guard count > 0 else { return [] }
            var pids = [Int32](repeating: 0, count: Int(count) + 32)
            let actual = pids.withUnsafeMutableBytes { buffer in
                proc_listallpids(buffer.baseAddress, Int32(buffer.count))
            }
            guard actual > 0 else { return [] }
            return Array(pids.prefix(Int(actual))).filter { $0 > 0 }
        }

        private static func executablePath(pid: Int32) -> String? {
            var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
            let byteCount = buffer.withUnsafeMutableBytes { rawBuffer in
                proc_pidpath(pid, rawBuffer.baseAddress, UInt32(rawBuffer.count))
            }
            guard byteCount > 0 else { return nil }
            return buffer.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return nil }
                let bytes = UnsafeRawBufferPointer(start: baseAddress, count: Int(byteCount))
                let pathBytes = bytes.prefix { $0 != 0 }
                guard !pathBytes.isEmpty else { return nil }
                return String(bytes: pathBytes, encoding: .utf8)
            }
        }

        private static func commandLine(pid: Int32) -> String? {
            var mib = [CTL_KERN, KERN_PROCARGS2, pid]
            var byteCount = 0
            guard sysctl(&mib, u_int(mib.count), nil, &byteCount, nil, 0) == 0,
                  byteCount >= MemoryLayout<Int32>.size
            else { return nil }

            var data = Data(count: byteCount)
            let result = data.withUnsafeMutableBytes { rawBuffer in
                sysctl(&mib, u_int(mib.count), rawBuffer.baseAddress, &byteCount, nil, 0)
            }
            guard result == 0 else { return nil }

            let argumentCountSize = MemoryLayout<Int32>.size
            guard data.count >= argumentCountSize else { return nil }
            let argumentCount = data.withUnsafeBytes { rawBuffer in
                Int(Int32(littleEndian: rawBuffer.loadUnaligned(as: Int32.self)))
            }
            guard argumentCount >= 0 else { return nil }

            let bytes = [UInt8](data)
            var offset = argumentCountSize
            guard let executableTerminator = bytes[offset...].firstIndex(of: 0) else { return nil }
            offset = executableTerminator + 1
            while offset < bytes.count, bytes[offset] == 0 {
                offset += 1
            }

            var arguments: [String] = []
            arguments.reserveCapacity(argumentCount)
            for _ in 0 ..< argumentCount {
                guard offset < bytes.count,
                      let terminator = bytes[offset...].firstIndex(of: 0),
                      let argument = String(bytes: bytes[offset ..< terminator], encoding: .utf8)
                else { break }
                arguments.append(argument)
                offset = terminator + 1
            }
            return arguments.joined(separator: " ")
        }

        private static func listeningTCPPorts(pid: Int32) -> [Int] {
            let requiredBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
            guard requiredBytes > 0 else { return [] }
            let descriptorStride = MemoryLayout<proc_fdinfo>.stride
            var descriptors = [proc_fdinfo](
                repeating: proc_fdinfo(),
                count: Int(requiredBytes) / descriptorStride + 8
            )
            let actualBytes = descriptors.withUnsafeMutableBytes { buffer in
                proc_pidinfo(
                    pid,
                    PROC_PIDLISTFDS,
                    0,
                    buffer.baseAddress,
                    Int32(buffer.count)
                )
            }
            guard actualBytes > 0 else { return [] }

            var ports: Set<Int> = []
            for descriptor in descriptors.prefix(Int(actualBytes) / descriptorStride)
                where descriptor.proc_fdtype == PROX_FDTYPE_SOCKET
            {
                var info = socket_fdinfo()
                let byteCount = proc_pidfdinfo(
                    pid,
                    descriptor.proc_fd,
                    PROC_PIDFDSOCKETINFO,
                    &info,
                    Int32(MemoryLayout<socket_fdinfo>.size)
                )
                guard byteCount == MemoryLayout<socket_fdinfo>.size,
                      info.psi.soi_kind == SOCKINFO_TCP,
                      info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN
                else { continue }
                let networkPort = UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)
                ports.insert(Int(UInt16(bigEndian: networkPort)))
            }
            return ports.sorted()
        }
    #endif
}
