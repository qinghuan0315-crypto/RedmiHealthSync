import SwiftUI
import HealthKit

@main
struct HealthApp: App {
    var body: some Scene {
        WindowGroup {
            DashboardView()
        }
    }
}

@MainActor
final class HealthStoreModel: ObservableObject {
    @Published var heartRate: Double?
    @Published var steps: Double?
    @Published var distance: Double?
    @Published var activeEnergy: Double?
    @Published var oxygen: Double?
    @Published var sleepHours: Double?
    @Published var lastUpdated: Date?
    @Published var status = "尚未连接 Apple 健康"
    @Published var isLoading = false

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        let quantityIDs: [HKQuantityTypeIdentifier] = [
            .heartRate, .stepCount, .distanceWalkingRunning,
            .activeEnergyBurned, .oxygenSaturation
        ]
        quantityIDs.forEach {
            if let type = HKObjectType.quantityType(forIdentifier: $0) {
                types.insert(type)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let workouts = HKObjectType.workoutType() as HKObjectType? {
            types.insert(workouts)
        }
        return types
    }

    func requestAccessAndRefresh() {
        guard isAvailable else {
            status = "此设备暂不支持 Apple 健康数据"
            return
        }
        isLoading = true
        status = "正在请求健康数据权限…"
        store.requestAuthorization(toShare: [], read: readTypes) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.status = "授权请求失败：\(error.localizedDescription)"
                    self.isLoading = false
                    return
                }
                self.status = success ? "已提交授权请求，正在读取数据" : "授权请求未完成"
                self.refresh()
            }
        }
    }

    func refresh() {
        guard isAvailable else { return }
        isLoading = true
        let group = DispatchGroup()

        group.enter()
        fetchLatestQuantity(.heartRate, unit: HKUnit.count().unitDivided(by: .minute)) { value in
            DispatchQueue.main.async {
                self.heartRate = value
                group.leave()
            }
        }

        group.enter()
        fetchTodaySum(.stepCount, unit: .count()) { value in
            DispatchQueue.main.async {
                self.steps = value
                group.leave()
            }
        }

        group.enter()
        fetchTodaySum(.distanceWalkingRunning, unit: .meter()) { value in
            DispatchQueue.main.async {
                self.distance = value
                group.leave()
            }
        }

        group.enter()
        fetchTodaySum(.activeEnergyBurned, unit: .kilocalorie()) { value in
            DispatchQueue.main.async {
                self.activeEnergy = value
                group.leave()
            }
        }

        group.enter()
        fetchLatestQuantity(.oxygenSaturation, unit: .percent()) { value in
            DispatchQueue.main.async {
                self.oxygen = value.map { $0 * 100.0 }
                group.leave()
            }
        }

        group.enter()
        fetchTodaySleep { value in
            DispatchQueue.main.async {
                self.sleepHours = value
                group.leave()
            }
        }

        group.notify(queue: .main) {
            Task { @MainActor in
                self.lastUpdated = Date()
                self.status = "已从 Apple 健康读取可用数据"
                self.isLoading = false
            }
        }
    }

    private func fetchLatestQuantity(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        completion: @escaping (Double?) -> Void
    ) {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            completion(nil); return
        }
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                  sortDescriptors: [sort]) { _, samples, _ in
            let sample = samples?.first as? HKQuantitySample
            completion(sample?.quantity.doubleValue(for: unit))
        }
        store.execute(query)
    }

    private func fetchTodaySum(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        completion: @escaping (Double?) -> Void
    ) {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else {
            completion(nil); return
        }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                      options: .cumulativeSum) { _, statistics, _ in
            completion(statistics?.sumQuantity()?.doubleValue(for: unit))
        }
        store.execute(query)
    }

    private func fetchTodaySleep(completion: @escaping (Double?) -> Void) {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            completion(nil); return
        }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: [])
        let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: nil) { _, samples, _ in
            let asleepValues: Set<Int> = [
                HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                HKCategoryValueSleepAnalysis.asleepREM.rawValue
            ]
            let seconds = (samples as? [HKCategorySample] ?? [])
                .filter { asleepValues.contains($0.value) }
                .reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            completion(seconds > 0 ? seconds / 3600.0 : nil)
        }
        store.execute(query)
    }
}

struct DashboardView: View {
    @StateObject private var model = HealthStoreModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    statusCard
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        MetricCard(title: "心率", value: model.heartRate.map { "\(Int($0.rounded()))" } ?? "—",
                                   unit: "次/分钟", symbol: "heart.fill", tint: .pink)
                        MetricCard(title: "步数", value: model.steps.map { Int($0).formatted() } ?? "—",
                                   unit: "步 · 今日", symbol: "figure.walk", tint: .green)
                        MetricCard(title: "睡眠", value: model.sleepHours.map { String(format: "%.1f", $0) } ?? "—",
                                   unit: "小时 · 今日", symbol: "bed.double.fill", tint: .indigo)
                        MetricCard(title: "血氧", value: model.oxygen.map { String(format: "%.0f", $0) } ?? "—",
                                   unit: "% · 最近记录", symbol: "lungs.fill", tint: .cyan)
                        MetricCard(title: "活动距离", value: model.distance.map { String(format: "%.2f", $0 / 1000) } ?? "—",
                                   unit: "公里 · 今日", symbol: "figure.run", tint: .orange)
                        MetricCard(title: "活动能量", value: model.activeEnergy.map { "\(Int($0.rounded()))" } ?? "—",
                                   unit: "千卡 · 今日", symbol: "flame.fill", tint: .red)
                    }
                    privacyNote
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                Button {
                    model.refresh()
                } label: {
                    Label(model.isLoading ? "正在同步…" : "立即同步数据", systemImage: "arrow.clockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .disabled(model.isLoading)
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .background(.ultraThinMaterial)
            }
            .onAppear {
                if model.isAvailable { model.requestAccessAndRefresh() }
            }
        }
        .tint(.pink)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "heart.text.square.fill")
                    .font(.title2)
                    .foregroundStyle(.pink)
                Text("健康")
                    .font(.headline)
                Spacer()
                Image(systemName: "apple.logo")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Text("健康，尽在掌握。")
                .font(.largeTitle.bold())
            Text(Date.now.formatted(date: .complete, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(.pink)
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple 健康数据")
                    .font(.headline)
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let date = model.lastUpdated {
                    Text("更新于 \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.isLoading { ProgressView() }
            else { Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
        }
        .padding(16)
        .modifier(GlassCardStyle())
    }

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("数据与隐私", systemImage: "lock.shield")
                .font(.headline)
            Text("本版本只从 Apple 健康读取你授权的数据，不会把健康数据上传到第三方服务器。你可以在 iPhone「健康」App 的数据访问与设备设置中随时调整权限。")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("数据仅供日常健康管理参考，不能用于疾病诊断或替代医疗设备。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(GlassCardStyle())
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .padding(16)
        .modifier(GlassCardStyle())
    }
}


struct GlassCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 22))
        } else {
            content.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }
}
