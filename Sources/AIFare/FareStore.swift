import Foundation
import SwiftUI

struct UsageSnapshot: Sendable {
    let title: String
    let model: String
    let sessionTokens: Int
    let todayTokens: Int
    let lastUpdated: Date
    let quota: QuotaSnapshot?

    static let empty = UsageSnapshot(title: "等待 Codex 任务", model: "—", sessionTokens: 0, todayTokens: 0, lastUpdated: .distantPast, quota: nil)
}

struct QuotaSnapshot: Sendable {
    let fiveHourUsedPercent: Double
    let weeklyUsedPercent: Double
}

enum CodexUsageReader {
    private static let database = "/Users/xu/.codex/state_5.sqlite"

    static func read() -> UsageSnapshot? {
        guard FileManager.default.fileExists(atPath: database) else { return nil }
        let startOfDay = Int(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970 * 1000)
        let sql = """
        SELECT COALESCE(title, ''), COALESCE(model, 'gpt-5.3-codex'), tokens_used,
               COALESCE(updated_at_ms, updated_at * 1000),
               (SELECT COALESCE(SUM(tokens_used), 0) FROM threads
                WHERE archived = 0 AND COALESCE(updated_at_ms, updated_at * 1000) >= \(startOfDay))
        FROM threads WHERE archived = 0
        ORDER BY COALESCE(updated_at_ms, updated_at * 1000) DESC LIMIT 1;
        """
        guard let line = runSQLite(sql) else { return nil }
        let fields = line.split(separator: "\u{1F}", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 5,
              let sessionTokens = Int(fields[2]),
              let updatedAt = Double(fields[3]),
              let todayTokens = Int(fields[4]) else { return nil }
        return UsageSnapshot(
            title: fields[0].isEmpty ? "未命名 Codex 任务" : fields[0],
            model: fields[1],
            sessionTokens: sessionTokens,
            todayTokens: todayTokens,
            lastUpdated: Date(timeIntervalSince1970: updatedAt / 1000),
            quota: CodexQuotaReader.latest()
        )
    }

    private static func runSQLite(_ sql: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-separator", "\u{1F}", database, sql]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .split(whereSeparator: \.isNewline).first.map(String.init)
        } catch { return nil }
    }
}

enum CodexQuotaReader {
    private static let sessions = URL(fileURLWithPath: "/Users/xu/.codex/sessions")

    static func latest() -> QuotaSnapshot? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(at: sessions, includingPropertiesForKeys: Array(keys)) else { return nil }
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
        let newest = files.sorted { modificationDate(of: $0) > modificationDate(of: $1) }.prefix(3)
        for file in newest {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.split(whereSeparator: \.isNewline).reversed() {
                guard let data = line.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data),
                      let quota = findQuota(in: object) else { continue }
                return quota
            }
        }
        return nil
    }

    private static func findQuota(in value: Any) -> QuotaSnapshot? {
        guard let dictionary = value as? [String: Any] else {
            if let array = value as? [Any] { return array.lazy.compactMap(findQuota).first }
            return nil
        }
        if let limits = dictionary["rate_limits"] as? [String: Any],
           let primary = limits["primary"] as? [String: Any],
           let secondary = limits["secondary"] as? [String: Any],
           let fiveHour = primary["used_percent"] as? NSNumber,
           let weekly = secondary["used_percent"] as? NSNumber {
            return QuotaSnapshot(fiveHourUsedPercent: fiveHour.doubleValue, weeklyUsedPercent: weekly.doubleValue)
        }
        return dictionary.values.lazy.compactMap(findQuota).first
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

struct Rate {
    let inputPerMillionUSD: Double
    let outputPerMillionUSD: Double
}

enum Pricing {
    static let plusMonthlyCNY = 144.0
    // API-equivalent list price. A session only exposes combined tokens, so the MVP uses a visible 70/30 blend.
    static func rate(for model: String) -> Rate {
        let name = model.lowercased()
        if name.contains("gpt-5.3-codex") { return Rate(inputPerMillionUSD: 1.75, outputPerMillionUSD: 14) }
        if name.contains("terra") { return Rate(inputPerMillionUSD: 0.5, outputPerMillionUSD: 2.5) }
        if name.contains("luna") { return Rate(inputPerMillionUSD: 0.05, outputPerMillionUSD: 0.25) }
        if name.contains("astra") { return Rate(inputPerMillionUSD: 5, outputPerMillionUSD: 25) }
        return Rate(inputPerMillionUSD: 1.75, outputPerMillionUSD: 14)
    }

    static func cny(tokens: Int, model: String) -> Double {
        let rate = rate(for: model)
        let blendedUSDPerMillion = rate.inputPerMillionUSD * 0.7 + rate.outputPerMillionUSD * 0.3
        return Double(tokens) / 1_000_000 * blendedUSDPerMillion * 7.20
    }
}

@MainActor
final class FareStore: ObservableObject {
    @Published private(set) var snapshot = UsageSnapshot.empty
    @Published private(set) var displayedSessionFare = 0.0
    @Published private(set) var isMetering = false
    @Published private(set) var readError: String?

    private var timer: Timer?
    private var lastRefresh = Date.distantPast

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    var weeklySubscriptionFare: Double {
        Pricing.plusMonthlyCNY * (snapshot.quota?.weeklyUsedPercent ?? 0) / 100
    }
    var settledSessionFare: Double {
        guard snapshot.todayTokens > 0 else { return 0 }
        return weeklySubscriptionFare * min(1, Double(snapshot.sessionTokens) / Double(snapshot.todayTokens))
    }
    var sessionFareText: String { displayedSessionFare.formatted(.currency(code: "CNY").precision(.fractionLength(4))) }
    var weeklyFareText: String { weeklySubscriptionFare.formatted(.currency(code: "CNY").precision(.fractionLength(2))) }
    var tokenText: String { snapshot.sessionTokens.formatted() }
    var quotaText: String {
        guard let quota = snapshot.quota else { return "读取中" }
        return "本周剩余 \((100 - quota.weeklyUsedPercent).formatted(.number.precision(.fractionLength(0))))%"
    }
    var activeDescription: String { isMetering ? "计价中 · \(activityLabel)" : "已结算 · 等待下一次调用" }
    var activityLabel: String {
        let seconds = Date().timeIntervalSince(snapshot.lastUpdated)
        return seconds < 8 ? "模型响应" : "工具执行 / 等待结果"
    }

    private func tick() {
        if Date().timeIntervalSince(lastRefresh) >= 5 { refresh() }
        let age = Date().timeIntervalSince(snapshot.lastUpdated)
        isMetering = age < 90
        let target = settledSessionFare
        if isMetering {
            // Continuous visual meter. A refresh always reconciles to the recorded Token total.
            displayedSessionFare = max(displayedSessionFare + 0.00008, target)
        } else {
            displayedSessionFare += (target - displayedSessionFare) * 0.18
        }
    }

    private func refresh() {
        lastRefresh = Date()
        guard let latest = CodexUsageReader.read() else {
            readError = "未读取到 Codex 本地用量。请确认 Codex 已登录，并允许此应用访问 ~/.codex。"
            return
        }
        readError = nil
        snapshot = latest
        let settled = settledSessionFare
        if displayedSessionFare == 0 || displayedSessionFare < settled { displayedSessionFare = settled }
    }
}
