import AppKit
import Combine
import Foundation
import SwiftUI

struct SubscriptionSnapshot: Equatable, Sendable {
    let usedPercent: Double?
    let resetsAt: Date?
    let recentUsage: [DailySubscriptionUsage]
    let todayQuotaUsedPercent: Double?

    var weeklyProgress: Double? { usedPercent.map { $0 / 100 } }

    func allocation(for selectedWeekdays: Set<Int>, now: Date = Date()) -> QuotaAllocation? {
        guard let resetsAt else { return nil }
        guard !selectedWeekdays.isEmpty else { return nil }
        let calendar = Calendar.current
        let firstDate = calendar.startOfDay(for: resetsAt.addingTimeInterval(-7 * 24 * 60 * 60))
        let currentDate = calendar.startOfDay(for: now)
        guard firstDate <= currentDate else {
            return QuotaAllocation(
                selectedWeekdays: selectedWeekdays,
                elapsedSelectedDays: 0,
                isTodaySelected: selectedWeekdays.contains(Self.mondayFirstWeekdayIndex(for: now, calendar: calendar))
            )
        }

        var count = 0
        var date = firstDate
        while date <= currentDate {
            if selectedWeekdays.contains(Self.mondayFirstWeekdayIndex(for: date, calendar: calendar)) {
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        return QuotaAllocation(
            selectedWeekdays: selectedWeekdays,
            elapsedSelectedDays: min(selectedWeekdays.count, count),
            isTodaySelected: selectedWeekdays.contains(Self.mondayFirstWeekdayIndex(for: now, calendar: calendar))
        )
    }

    func paceState(for selectedWeekdays: Set<Int>) -> PaceState {
        guard let allocation = allocation(for: selectedWeekdays), let usedPercent else { return .unavailable }
        if usedPercent <= allocation.allowedPercent { return .white }
        if usedPercent <= allocation.allowedPercent + allocation.dailyPercent { return .red }
        return .purple
    }

    func todayQuotaRemaining(for selectedWeekdays: Set<Int>) -> Double? {
        guard let dailyAllocationProgress = dailyAllocationProgress(for: selectedWeekdays) else { return nil }
        let stageOffset: Double
        switch paceState(for: selectedWeekdays) {
        case .white: stageOffset = 0
        case .red: stageOffset = 100
        case .purple: stageOffset = 200
        case .unavailable: return nil
        }
        let consumption = stageOffset + min(1, max(0, dailyAllocationProgress)) * 100
        return 100 - consumption
    }

    // Today's actual increase expressed against the fixed daily allocation.
    func dailyAllocationProgress(for selectedWeekdays: Set<Int>) -> Double? {
        guard let allocation = allocation(for: selectedWeekdays), allocation.isTodaySelected,
              let todayQuotaUsedPercent else { return nil }
        return todayQuotaUsedPercent / allocation.dailyPercent
    }

    func dailyPaceState(for selectedWeekdays: Set<Int>) -> PaceState {
        guard let dailyAllocationProgress = dailyAllocationProgress(for: selectedWeekdays) else { return .unavailable }
        if dailyAllocationProgress <= 1 { return .white }
        if dailyAllocationProgress <= 2 { return .red }
        return .purple
    }
    // The daily overlay is based on today's actual increase and repeats inside
    // its active 100% color band.
    func dailyCycleProgress(for selectedWeekdays: Set<Int>) -> Double? {
        guard let dailyAllocationProgress = dailyAllocationProgress(for: selectedWeekdays) else { return nil }
        let remainder = dailyAllocationProgress.truncatingRemainder(dividingBy: 1)
        return remainder == 0 && dailyAllocationProgress > 0 ? 1 : remainder
    }

    func isStaticPurpleArc(for selectedWeekdays: Set<Int>) -> Bool {
        guard paceState(for: selectedWeekdays) == .purple,
              let dailyAllocationProgress = dailyAllocationProgress(for: selectedWeekdays)
        else { return false }
        return dailyAllocationProgress >= 1
    }

    private static func mondayFirstWeekdayIndex(for date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }
}

struct QuotaAllocation: Equatable, Sendable {
    let selectedWeekdays: Set<Int>
    let elapsedSelectedDays: Int
    let isTodaySelected: Bool

    var dailyPercent: Double { 100 / Double(selectedWeekdays.count) }
    var allowedPercent: Double { Double(elapsedSelectedDays) * dailyPercent }
}

struct DailySubscriptionUsage: Identifiable, Equatable, Sendable {
    let date: Date
    let consumedTokens: Int64
    let paceState: PaceState
    let hasLocalData: Bool

    var id: Date { date }
}

enum PaceState: Equatable {
    case unavailable
    case white
    case red
    case purple

    var color: Color {
        switch self {
        case .unavailable: .secondary
        case .white: .white
        case .red: .red
        case .purple: .purple
        }
    }

    // Keep the heatmap's original white/red/purple palette above, while the
    // single-day ring uses green/red/purple to distinguish a healthy day.
    var dailyArcStartColor: Color {
        switch self {
        case .white: Color(red: 0.62, green: 1.0, blue: 0.82)
        case .red: Color(red: 1.0, green: 0.66, blue: 0.69)
        case .purple: Color(red: 0.87, green: 0.68, blue: 1.0)
        case .unavailable: .secondary
        }
    }

    var dailyArcEndColor: Color {
        switch self {
        case .white: Color(red: 0.20, green: 0.94, blue: 0.56)
        case .red: Color(red: 1.0, green: 0.29, blue: 0.38)
        case .purple: Color(red: 0.62, green: 0.33, blue: 0.94)
        case .unavailable: .secondary
        }
    }

    var heatmapColor: Color {
        switch self {
        case .white: Color(red: 0.20, green: 0.94, blue: 0.56)
        case .red: .red
        case .purple: .purple
        case .unavailable: .secondary
        }
    }

    var description: String {
        switch self {
        case .unavailable: "未找到订阅限额"
        case .white: "在可用额度范围内"
        case .red: "超出可用额度一格"
        case .purple: "超出可用额度两格以上"
        }
    }
}

@MainActor
final class SubscriptionMonitor: ObservableObject {
    @Published private(set) var snapshot = SubscriptionSnapshot(
        usedPercent: nil,
        resetsAt: nil,
        recentUsage: [],
        todayQuotaUsedPercent: nil,
    )
    @Published private(set) var refreshedAt = Date.distantPast
    @Published private(set) var selectedWeekdays: Set<Int>

    private var refreshTimer: Timer?
    private var isRefreshing = false
    private static let selectedWeekdaysKey = "CodexQuotaMeterV2.selectedWeekdays"

    init() {
        selectedWeekdays = Self.loadSelectedWeekdays()
        refresh()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    deinit { refreshTimer?.invalidate() }

    func toggleWeekday(_ weekdayIndex: Int) {
        guard (0..<7).contains(weekdayIndex) else { return }
        if selectedWeekdays.contains(weekdayIndex) {
            guard selectedWeekdays.count > 1 else { return }
            selectedWeekdays.remove(weekdayIndex)
        } else {
            selectedWeekdays.insert(weekdayIndex)
        }
        let serialized = selectedWeekdays.sorted().map(String.init).joined(separator: ",")
        UserDefaults.standard.set(serialized, forKey: Self.selectedWeekdaysKey)
    }

    private static func loadSelectedWeekdays() -> Set<Int> {
        let saved = UserDefaults.standard.string(forKey: selectedWeekdaysKey)
        let decoded = Set((saved ?? "").split(separator: ",").compactMap { Int($0) }.filter { (0..<7).contains($0) })
        // Preserve the original Monday–Saturday pacing until the user selects
        // a different schedule in V2.
        return decoded.isEmpty ? Set(0..<6) : decoded
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { [weak self] in
            let next = await Task.detached(priority: .utility) {
                SubscriptionLimitReader.loadSnapshot()
            }.value
            guard let self else { return }
            snapshot = next
            refreshedAt = Date()
            isRefreshing = false
        }
    }
}

enum SubscriptionLimitReader {
    private struct PrimaryLimit: Decodable {
        let usedPercent: Double
        let windowMinutes: Int
        let resetsAt: Int64?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case windowMinutes = "window_minutes"
            case resetsAt = "resets_at"
        }
    }

    private struct TokenUsage: Decodable {
        let totalTokens: Int64
        enum CodingKeys: String, CodingKey { case totalTokens = "total_tokens" }
    }
    private struct TokenInfo: Decodable {
        let lastTokenUsage: TokenUsage?
        enum CodingKeys: String, CodingKey { case lastTokenUsage = "last_token_usage" }
    }
    private struct RateLimits: Decodable { let primary: PrimaryLimit? }
    private struct Payload: Decodable {
        let rateLimits: RateLimits?
        let info: TokenInfo?
        enum CodingKeys: String, CodingKey {
            case rateLimits = "rate_limits"
            case info
        }
    }
    private struct EventLine: Decodable {
        let timestamp: String?
        let payload: Payload?
    }

    private struct FileStamp: Equatable {
        let size: Int64
        let modifiedAt: Date
    }
    private struct CacheRecord {
        let stamp: FileStamp
        let sample: SubscriptionSnapshot?
    }
    private struct LimitEvent: Sendable {
        let timestamp: Date
        let usedPercent: Double
        let resetsAt: Date?
        let tokenCount: Int64
    }
    private struct HistoryCacheRecord {
        let stamp: FileStamp
        let events: [LimitEvent]
    }
    private struct RecentUsageSummary {
        let days: [DailySubscriptionUsage]
        let todayQuotaUsedPercent: Double?
    }

    private static let fileManager = FileManager.default
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let cacheLock = NSLock()
    private static var fileCache: [String: CacheRecord] = [:]
    private static var historyFileCache: [String: HistoryCacheRecord] = [:]
    private static let sevenDayWindowMinutes = 10_080
    private static let tailByteCount: UInt64 = 8 * 1024 * 1024

    static func loadSnapshot() -> SubscriptionSnapshot {
        let files = candidateFiles().sorted { $0.modifiedAt > $1.modifiedAt }
        let history = loadRecentUsage()

        for item in files {
            let sample: SubscriptionSnapshot?
            cacheLock.lock()
            if let cached = fileCache[item.url.path], cached.stamp == item.stamp {
                sample = cached.sample
                cacheLock.unlock()
            } else {
                cacheLock.unlock()
                let scanned = autoreleasepool { sampleInTail(of: item.url) }
                cacheLock.lock()
                fileCache[item.url.path] = CacheRecord(stamp: item.stamp, sample: scanned)
                cacheLock.unlock()
                sample = scanned
            }
            if let sample {
                let current = SubscriptionSnapshot(
                    usedPercent: sample.usedPercent,
                    resetsAt: sample.resetsAt,
                    recentUsage: history.days,
                    todayQuotaUsedPercent: history.todayQuotaUsedPercent
                )
                return normalizedForReset(current)
            }
        }
        return SubscriptionSnapshot(
            usedPercent: nil,
            resetsAt: nil,
            recentUsage: history.days,
            todayQuotaUsedPercent: history.todayQuotaUsedPercent
        )
    }

    // The local event stream normally supplies a fresh used_percent after a
    // reset. Until that next event arrives, advance an expired 7-day window to
    // zero so the meter resets together with Codex rather than showing stale use.
    private static func normalizedForReset(_ snapshot: SubscriptionSnapshot, now: Date = Date()) -> SubscriptionSnapshot {
        guard let reset = snapshot.resetsAt, now >= reset else { return snapshot }
        let windowDuration = TimeInterval(sevenDayWindowMinutes * 60)
        let elapsedWindows = floor(now.timeIntervalSince(reset) / windowDuration) + 1
        return SubscriptionSnapshot(
            usedPercent: 0,
            resetsAt: reset.addingTimeInterval(windowDuration * elapsedWindows),
            recentUsage: snapshot.recentUsage,
            todayQuotaUsedPercent: snapshot.todayQuotaUsedPercent
        )
    }

    private struct CandidateFile {
        let url: URL
        let stamp: FileStamp
        var modifiedAt: Date { stamp.modifiedAt }
    }

    private static func candidateFiles(daysBack: Int = 7) -> [CandidateFile] {
        let calendar = Calendar.current
        let now = Date()
        var results: [CandidateFile] = []

        for offset in 0..<daysBack {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let dayPath = dayPath(for: date)
            let prefix = "rollout-\(dayPath.replacingOccurrences(of: "/", with: "-"))"
            let sessions = home.appendingPathComponent(".codex/sessions/\(dayPath)")
            let archived = home.appendingPathComponent(".codex/archived_sessions")
            results += files(in: sessions, matchingPrefix: prefix)
            results += files(in: archived, matchingPrefix: prefix)
        }
        return results
    }

    private static func dayPath(for date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d/%02d/%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private static func files(in directory: URL, matchingPrefix prefix: String) -> [CandidateFile] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.compactMap { url in
            guard url.pathExtension == "jsonl", url.lastPathComponent.hasPrefix(prefix),
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize,
                  let modifiedAt = values.contentModificationDate
            else { return nil }
            return CandidateFile(url: url, stamp: FileStamp(size: Int64(size), modifiedAt: modifiedAt))
        }
    }

    private static func loadRecentUsage() -> RecentUsageSummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let startDate = calendar.date(byAdding: .day, value: -89, to: today) ?? today
        let files = candidateFiles(daysBack: 93)
        let events = files.flatMap { item -> [LimitEvent] in
            cacheLock.lock()
            if let cached = historyFileCache[item.url.path], cached.stamp == item.stamp {
                cacheLock.unlock()
                return cached.events
            }
            cacheLock.unlock()
            let scanned = autoreleasepool { eventsInTail(of: item.url) }
            cacheLock.lock()
            historyFileCache[item.url.path] = HistoryCacheRecord(stamp: item.stamp, events: scanned)
            cacheLock.unlock()
            return scanned
        }.sorted { $0.timestamp < $1.timestamp }

        var daily: [Date: DailySubscriptionUsage] = [:]
        var previousByWindow: [Int64: Double] = [:]
        var todayQuotaUsedPercent = 0.0
        var hasTodayQuotaEvent = false

        for event in events {
            let day = calendar.startOfDay(for: event.timestamp)
            // Codex may vary resets_at by a few seconds within the same limit
            // window. Group by reset hour so repeated snapshots are not counted
            // as separate daily consumption.
            let windowKey = event.resetsAt.map { Int64($0.timeIntervalSince1970 / 3_600) } ?? -1
            let delta = previousByWindow[windowKey].map { max(0, event.usedPercent - $0) } ?? 0
            previousByWindow[windowKey] = event.usedPercent
            if day == today {
                todayQuotaUsedPercent += delta
                hasTodayQuotaEvent = true
            }
            guard day >= startDate, day <= today else { continue }
            let previousDay = daily[day]
            daily[day] = DailySubscriptionUsage(
                date: day,
                consumedTokens: (previousDay?.consumedTokens ?? 0) + event.tokenCount,
                paceState: paceState(for: event),
                hasLocalData: true
            )
        }

        let days: [DailySubscriptionUsage] = (0..<90).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else { return nil }
            return daily[date] ?? DailySubscriptionUsage(date: date, consumedTokens: 0, paceState: .unavailable, hasLocalData: false)
        }
        return RecentUsageSummary(days: days, todayQuotaUsedPercent: hasTodayQuotaEvent ? todayQuotaUsedPercent : nil)
    }

    private static func paceState(for event: LimitEvent) -> PaceState {
        guard let reset = event.resetsAt else { return .unavailable }
        let calendar = Calendar.current
        let windowStart = reset.addingTimeInterval(-7 * 24 * 60 * 60)
        let elapsedDays = Int(floor(max(0, event.timestamp.timeIntervalSince(windowStart)) / (24 * 60 * 60)))
        let dayNumber = min(7, elapsedDays + 1)
        let canUseSunday = calendar.component(.weekday, from: event.timestamp) == 7
        let allowed = min(7, dayNumber + (canUseSunday ? 1 : 0))
        let usedSegments = event.usedPercent * 7 / 100
        if usedSegments <= Double(allowed) { return .white }
        if usedSegments <= Double(allowed + 1) { return .red }
        return .purple
    }

    private static func eventsInTail(of url: URL) -> [LimitEvent] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let tailSize = min(fileSize, UInt64(1 * 1024 * 1024))
        try? handle.seek(toOffset: fileSize - tailSize)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { return [] }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let string = String(line)
            guard string.contains("\"used_percent\""),
                  let event = try? JSONDecoder().decode(EventLine.self, from: Data(string.utf8)),
                  let timestampText = event.timestamp,
                  let timestamp = formatter.date(from: timestampText),
                  let primary = event.payload?.rateLimits?.primary,
                  primary.windowMinutes == sevenDayWindowMinutes
            else { return nil }
            return LimitEvent(
                timestamp: timestamp,
                usedPercent: max(0, primary.usedPercent),
                resetsAt: primary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                tokenCount: event.payload?.info?.lastTokenUsage?.totalTokens ?? 0
            )
        }
    }

    private static func sampleInTail(of url: URL) -> SubscriptionSnapshot? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let start = size > tailByteCount ? size - tailByteCount : 0
        try? handle.seek(toOffset: start)
        guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        for line in text.split(whereSeparator: \.isNewline).reversed() {
            let string = String(line)
            guard string.contains("\"used_percent\""), string.contains("\"window_minutes\":10080") || string.contains("\"window_minutes\": 10080"),
                  let event = try? JSONDecoder().decode(EventLine.self, from: Data(string.utf8)),
                  let primary = event.payload?.rateLimits?.primary,
                  primary.windowMinutes == sevenDayWindowMinutes
            else { continue }

            return SubscriptionSnapshot(
                usedPercent: max(0, primary.usedPercent),
                resetsAt: primary.resetsAt.map { Date(timeIntervalSince1970: TimeInterval($0)) },
                recentUsage: [],
                todayQuotaUsedPercent: nil
            )
        }
        return nil
    }
}

struct MeterRing: View {
    let progress: Double?
    let dailyCycleProgress: Double?
    let dailyTotalProgress: Double?
    let mainText: String
    let diameter: CGFloat
    let dailyArcStartColor: Color
    let dailyArcEndColor: Color
    let isStaticPurpleArc: Bool

    private var clampedProgress: Double { min(1, max(0, progress ?? 0)) }
    private let lineWidthRatio: CGFloat = 0.10

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.12), lineWidth: diameter * lineWidthRatio)
            if progress != nil {
                Circle()
                    .trim(from: 0, to: clampedProgress)
                    .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: diameter * lineWidthRatio, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color.white.opacity(0.14), radius: diameter * 0.025)
            }
            if dailyCycleProgress != nil {
                LoopingDailyArc(
                    targetProgress: dailyCycleProgress ?? 0,
                    diameter: diameter,
                    lineWidth: diameter * lineWidthRatio,
                    startColor: dailyArcStartColor,
                    endColor: dailyArcEndColor,
                    isStaticPurple: isStaticPurpleArc
                )
            }
            Text(mainText)
                .font(.system(size: diameter * 0.25, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("7天消耗 \(mainText)；今日消耗 \(PercentFormatter.whole(dailyTotalProgress.map { $0 * 100 }))")
    }
}

struct DailyGradientArc: View {
    let progress: CGFloat
    let diameter: CGFloat
    let lineWidth: CGFloat
    let startColor: Color
    let endColor: Color

    var body: some View {
        let visibleProgress = min(1, max(0, progress))
        Circle()
            .trim(from: 0, to: visibleProgress)
            .stroke(
                AngularGradient(
                    colors: [startColor.opacity(0.22), startColor.opacity(0.65), endColor],
                    center: .center,
                    startAngle: .zero,
                    endAngle: .degrees(360 * Double(max(0.01, visibleProgress)))
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(-90))
            .shadow(color: endColor.opacity(0.42), radius: lineWidth * 0.48)
            .frame(width: diameter, height: diameter)
    }
}

struct LoopingDailyArc: View {
    let targetProgress: Double
    let diameter: CGFloat
    let lineWidth: CGFloat
    let startColor: Color
    let endColor: Color
    let isStaticPurple: Bool

    @State private var startedAt = Date()

    var body: some View {
        Group {
            if isStaticPurple {
                Circle()
                    .stroke(Color(red: 0.42, green: 0.12, blue: 0.78), lineWidth: lineWidth)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: Color(red: 0.42, green: 0.12, blue: 0.78).opacity(0.45), radius: lineWidth * 0.48)
                    .frame(width: diameter, height: diameter)
            } else {
                TimelineView(.animation) { timeline in
                    let elapsed = max(0, timeline.date.timeIntervalSince(startedAt))
                    let animationDuration = 1.45
                    let holdDuration = 0.5
                    let cycleDuration = animationDuration + holdDuration
                    let cycleElapsed = elapsed.truncatingRemainder(dividingBy: cycleDuration)
                    let phase = min(1, cycleElapsed / animationDuration)
                    DailyGradientArc(
                        progress: CGFloat(min(1, max(0, targetProgress)) * phase),
                        diameter: diameter,
                        lineWidth: lineWidth,
                        startColor: startColor,
                        endColor: endColor
                    )
                }
            }
        }
        .onChange(of: targetProgress) { _, _ in startedAt = Date() }
    }
}

struct MenuSingleRing: View {
    let weeklyProgress: Double?
    let dailyCycleProgress: Double?
    let dailyArcStartColor: Color
    let dailyArcEndColor: Color
    let isStaticPurpleArc: Bool
    private let trackWidth: CGFloat = 3.0

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.30), lineWidth: trackWidth)
            if let weeklyProgress {
                Circle().trim(from: 0, to: min(1, max(0, weeklyProgress)))
                    .stroke(Color.white.opacity(0.92), style: StrokeStyle(lineWidth: trackWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            if dailyCycleProgress != nil {
                LoopingDailyArc(
                    targetProgress: dailyCycleProgress ?? 0,
                    diameter: 18,
                    lineWidth: trackWidth,
                    startColor: dailyArcStartColor,
                    endColor: dailyArcEndColor,
                    isStaticPurple: isStaticPurpleArc
                )
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityElement(children: .ignore)
    }
}

struct MenuBarLabel: View {
    let snapshot: SubscriptionSnapshot
    let selectedWeekdays: Set<Int>

    var body: some View {
        MenuSingleRing(
            weeklyProgress: snapshot.weeklyProgress,
            dailyCycleProgress: snapshot.dailyCycleProgress(for: selectedWeekdays),
            dailyArcStartColor: snapshot.paceState(for: selectedWeekdays).dailyArcStartColor,
            dailyArcEndColor: snapshot.paceState(for: selectedWeekdays).dailyArcEndColor,
            isStaticPurpleArc: snapshot.isStaticPurpleArc(for: selectedWeekdays)
        )
        .accessibilityLabel("Codex 7天订阅额度与今日用量")
    }
}

@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var iconView: NSHostingView<MenuBarLabel>?
    private var snapshotSubscription: AnyCancellable?

    func configure(with monitor: SubscriptionMonitor) {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: 28)
        guard let button = item.button else { return }
        button.title = ""
        button.target = self
        button.action = #selector(togglePopover(_:))

        let view = NSHostingView(rootView: MenuBarLabel(snapshot: monitor.snapshot, selectedWeekdays: monitor.selectedWeekdays))
        view.frame = NSRect(x: 4, y: 1, width: 20, height: 20)
        view.autoresizingMask = [.width, .height]
        let click = NSClickGestureRecognizer(target: self, action: #selector(togglePopover(_:)))
        view.addGestureRecognizer(click)
        button.addSubview(view)

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 340, height: 500)
        popover.contentViewController = NSHostingController(rootView: MeterPanel(monitor: monitor))

        iconView = view
        statusItem = item
        snapshotSubscription = monitor.$snapshot.combineLatest(monitor.$selectedWeekdays)
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot, selectedWeekdays in
                self?.iconView?.rootView = MenuBarLabel(snapshot: snapshot, selectedWeekdays: selectedWeekdays)
            }
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusBarController = StatusBarController()

    func configureStatusItem(with monitor: SubscriptionMonitor) {
        statusBarController.configure(with: monitor)
    }
}

struct UsageHeatmapCell: View {
    let usage: DailySubscriptionUsage?
    let maximumTokens: Int64
    @Binding var hoveredDate: Date?

    @State private var glowing = false

    private var isHovered: Bool { usage.map { hoveredDate == $0.date } ?? false }
    private var fillColor: Color {
        guard let usage, usage.hasLocalData else { return Color.primary.opacity(0.14) }
        let ratio = maximumTokens > 0 ? min(1, Double(usage.consumedTokens) / Double(maximumTokens)) : 0
        let brightness = 0.28 + 0.72 * sqrt(ratio)
        return usage.paceState.heatmapColor.opacity(brightness)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(fillColor)
            .frame(width: 14, height: 14)
            .overlay {
                if isHovered {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.white.opacity(0.95), lineWidth: 1.3)
                }
            }
            .shadow(color: isHovered ? fillColor.opacity(glowing ? 1 : 0.35) : .clear, radius: glowing ? 8 : 2)
            .scaleEffect(isHovered && glowing ? 1.18 : 1)
            .onHover { isHovering in
                guard let usage else { return }
                hoveredDate = isHovering ? usage.date : nil
                withAnimation(.easeInOut(duration: 0.48).repeatForever(autoreverses: true)) {
                    glowing = isHovering
                }
            }
            .animation(.easeOut(duration: 0.16), value: isHovered)
    }
}

struct UsageHeatmap: View {
    let entries: [DailySubscriptionUsage]
    let currentDailyPaceState: PaceState

    @State private var hoveredDate: Date?

    private let weekdayNames = ["一", "二", "三", "四", "五", "六", "日"]

    private var weeks: [[DailySubscriptionUsage?]] {
        guard let first = entries.first else { return [] }
        let calendar = Calendar.current
        let leadBlanks = (calendar.component(.weekday, from: first.date) + 5) % 7
        var result: [[DailySubscriptionUsage?]] = []
        for _ in 0..<max(1, Int(ceil(Double(leadBlanks + entries.count) / 7.0))) {
            result.append(Array(repeating: nil, count: 7))
        }
        for (index, entry) in entries.enumerated() {
            let absoluteIndex = leadBlanks + index
            result[absoluteIndex / 7][absoluteIndex % 7] = entry
        }
        return result
    }

    private var hoveredUsage: DailySubscriptionUsage? {
        guard let hoveredDate else { return nil }
        return entries.first { $0.date == hoveredDate }
    }

    private var totalConsumed: Int64 { entries.reduce(0) { $0 + $1.consumedTokens } }

    private func maximumTokens(for state: PaceState) -> Int64 {
        entries.filter { $0.hasLocalData && $0.paceState == state }
            .map(\.consumedTokens)
            .max() ?? 0
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("近 90 天用量", systemImage: "calendar")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
            }

            HStack(alignment: .top, spacing: 7) {
                VStack(spacing: 3) {
                    Color.clear.frame(width: 14, height: 14)
                    ForEach(weekdayNames, id: \.self) { name in
                        Text(name)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: 14)
                    }
                }
                HStack(spacing: 3) {
                    ForEach(weeks.indices, id: \.self) { weekIndex in
                        VStack(spacing: 3) {
                            Color.clear.frame(width: 14, height: 14)
                            ForEach(0..<7, id: \.self) { dayIndex in
                                UsageHeatmapCell(
                                    usage: weeks[weekIndex][dayIndex],
                                    maximumTokens: maximumTokens(for: weeks[weekIndex][dayIndex]?.paceState ?? .unavailable),
                                    hoveredDate: $hoveredDate
                                )
                            }
                        }
                    }
                }
            }

            HStack {
                Text(footerText)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer()
                legend
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(currentDailyPaceState.heatmapColor.opacity(0.48), lineWidth: 1)
        }
    }

    private var footerText: String {
        if let usage = hoveredUsage {
            let date = usage.date.formatted(.dateTime.month().day())
            return usage.hasLocalData ? "\(date) · \(TokenFormatter.compact(usage.consumedTokens)) tokens" : "\(date) · 无本机记录"
        }
        return "近 90 天累计 \(TokenFormatter.compact(totalConsumed)) tokens"
    }

    private var legend: some View {
        HStack(spacing: 4) {
            ForEach([PaceState.white, .red, .purple], id: \.description) { state in
                RoundedRectangle(cornerRadius: 2).fill(state.heatmapColor).frame(width: 9, height: 9)
            }
        }
    }
}

struct WeekdayQuotaSelector: View {
    let selectedWeekdays: Set<Int>
    let toggleWeekday: (Int) -> Void

    private let weekdayNames = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    private var dailyPercent: Double { 100 / Double(selectedWeekdays.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("额度分配")
                    .font(.subheadline.weight(.bold))
                Spacer()
                Text("已选 \(selectedWeekdays.count) 天 · 每天 \(PercentFormatter.oneDecimal(dailyPercent))")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 4) {
                ForEach(weekdayNames.indices, id: \.self) { index in
                    let isSelected = selectedWeekdays.contains(index)
                    Button {
                        toggleWeekday(index)
                    } label: {
                        Text(weekdayNames[index])
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity, minHeight: 30)
                            .foregroundStyle(isSelected ? Color.black.opacity(0.84) : Color.secondary)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? Color.green.opacity(0.88) : Color.primary.opacity(0.075))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? Color.green.opacity(0.96) : Color.primary.opacity(0.12), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(isSelected && selectedWeekdays.count == 1 ? "至少保留一天" : "点击\(isSelected ? "取消" : "选中")\(weekdayNames[index])")
                    .accessibilityLabel("\(weekdayNames[index])，\(isSelected ? "已选中" : "未选中")")
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.green.opacity(0.28), lineWidth: 1)
        }
    }
}

struct MeterPanel: View {
    @ObservedObject var monitor: SubscriptionMonitor

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Text("ChatGPT 订阅额度").font(.headline)
                Spacer()
                Text("今日额度剩余：\(PercentFormatter.whole(monitor.snapshot.todayQuotaRemaining(for: monitor.selectedWeekdays)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: monitor.refresh) { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("立即刷新")
            }

            VStack(spacing: 12) {
                MeterRing(
                    progress: monitor.snapshot.weeklyProgress,
                    dailyCycleProgress: monitor.snapshot.dailyCycleProgress(for: monitor.selectedWeekdays),
                    dailyTotalProgress: monitor.snapshot.dailyAllocationProgress(for: monitor.selectedWeekdays),
                    mainText: PercentFormatter.whole(monitor.snapshot.usedPercent),
                    diameter: 164,
                    dailyArcStartColor: monitor.snapshot.paceState(for: monitor.selectedWeekdays).dailyArcStartColor,
                    dailyArcEndColor: monitor.snapshot.paceState(for: monitor.selectedWeekdays).dailyArcEndColor,
                    isStaticPurpleArc: monitor.snapshot.isStaticPurpleArc(for: monitor.selectedWeekdays)
                )
            }

            WeekdayQuotaSelector(
                selectedWeekdays: monitor.selectedWeekdays,
                toggleWeekday: monitor.toggleWeekday
            )

            UsageHeatmap(
                entries: monitor.snapshot.recentUsage,
                currentDailyPaceState: monitor.snapshot.paceState(for: monitor.selectedWeekdays)
            )

            Divider()
            HStack {
                Text("每 30 秒自动刷新").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless)
            }
        }
        .padding(18)
        .frame(width: 340)
    }

}

enum PercentFormatter {
    static func whole(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    static func oneDecimal(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }
}

enum TokenFormatter {
    static func compact(_ value: Int64) -> String {
        let number = Double(value)
        if number >= 1_000_000_000 { return String(format: "%.2fB", number / 1_000_000_000) }
        if number >= 1_000_000 { return String(format: "%.1fM", number / 1_000_000) }
        if number >= 1_000 { return String(format: "%.1fK", number / 1_000) }
        return "\(value)"
    }
}

@main
struct CodexQuotaMeterApp: App {
    @StateObject private var monitor = SubscriptionMonitor()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("CodexQuotaMeter") {
            MeterPanel(monitor: monitor)
                .onAppear { appDelegate.configureStatusItem(with: monitor) }
        }
            .defaultSize(width: 340, height: 500)
    }
}
