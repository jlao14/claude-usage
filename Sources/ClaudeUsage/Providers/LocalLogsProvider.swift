import Foundation

/// Estimates usage from Claude Code's own session logs (`~/.claude/projects/**/*.jsonl`).
/// Works offline and needs no credentials. Files are read incrementally: only
/// bytes appended since the previous refresh are parsed.
actor LocalLogsProvider: UsageProvider {
    nonisolated let id = ProviderID.localLogs

    private let roots: [URL]
    private let lookback: TimeInterval
    private var offsets: [String: UInt64] = [:]
    private var seen: Set<String> = []
    private var entries: [UsageEntry] = []

    /// - Parameter lookback: how far back to keep entries; older files and entries are ignored.
    init(roots: [URL] = LocalLogsProvider.defaultRoots(), lookback: TimeInterval = 31 * 86400) {
        self.roots = roots
        self.lookback = lookback
    }

    static func defaultRoots(environment: [String: String] = ProcessInfo.processInfo.environment) -> [URL] {
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return custom.split(separator: ",").map {
                URL(fileURLWithPath: String($0).trimmingCharacters(in: .whitespaces)).appending(path: "projects")
            }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appending(path: ".claude/projects"),
            home.appending(path: ".config/claude/projects"),
        ]
    }

    static let historyDays = 30

    var entryCount: Int { entries.count }

    func fetch(now: Date) async throws -> UsageSnapshot {
        let existingRoots = roots.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existingRoots.isEmpty else { throw ProviderError.noLogsFound }

        let cutoff = now.addingTimeInterval(-lookback)
        for file in Self.logFiles(in: existingRoots, modifiedSince: cutoff) {
            ingest(file)
        }
        entries.removeAll { $0.timestamp < cutoff }

        let series = LogAggregator.dailySeries(entries: entries, now: now, days: Self.historyDays)
        let windowStart = series.first?.date ?? now
        let startOfToday = Calendar.current.startOfDay(for: now)
        let today = UsageTotals(entries: entries.filter { $0.timestamp >= startOfToday && $0.timestamp <= now })
        let window = UsageTotals(entries: entries.filter { $0.timestamp >= windowStart && $0.timestamp <= now })

        let session = LogAggregator.activeBlock(entries: entries, now: now).map { Format.summary($0.totals) }
        let metrics = [
            Metric(title: "Session", value: session ?? "none active"),
            Metric(title: "Today", value: Format.summary(today)),
            Metric(title: "Last \(Self.historyDays) days", value: Format.summary(window)),
        ]
        return UsageSnapshot(gauges: [], metrics: metrics, fetchedAt: now, series: series)
    }

    // MARK: - Reading

    private static func logFiles(in roots: [URL], modifiedSince cutoff: Date) -> [URL] {
        var files: [URL] = []
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isRegularFileKey]
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { continue }
            while let url = walker.nextObject() as? URL {
                guard url.pathExtension == "jsonl",
                      let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let modified = values.contentModificationDate, modified >= cutoff
                else { continue }
                files.append(url)
            }
        }
        return files
    }

    private func ingest(_ url: URL) {
        let path = url.path
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        var offset = offsets[path] ?? 0
        guard let size = try? handle.seekToEnd() else { return }
        if size < offset { offset = 0 } // file was truncated or rewritten; `seen` prevents double counting
        guard size > offset else { return }

        guard (try? handle.seek(toOffset: offset)) != nil,
              let chunk = try? handle.readToEnd(),
              // Only consume complete lines; a half-written trailing line is picked up next time.
              let lastNewline = chunk.lastIndex(of: 0x0A)
        else { return }

        for line in chunk[chunk.startIndex...lastNewline].split(separator: 0x0A) {
            guard let entry = LogParser.parse(line: Data(line)), seen.insert(entry.key).inserted else { continue }
            entries.append(entry)
        }
        offsets[path] = offset + UInt64(lastNewline - chunk.startIndex + 1)
    }
}
