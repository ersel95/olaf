import Foundation

/// Görünen network kayıtlarından hesaplanan özet istatistikler (saf hesap — test edilebilir).
/// Viewer'daki "İstatistikler" ekranı bunu, o an görünen (filtreli) liste üzerinden üretir.
struct NetworkStats {

    let totalRequests: Int
    let failureCount: Int            // 4xx/5xx veya taşıma hatası (iptal hariç)
    let cancelledCount: Int
    let averageDurationMs: Int?
    let medianDurationMs: Int?
    let p95DurationMs: Int?
    let totalRequestBytes: Int
    let totalResponseBytes: Int
    /// HTTP metotları — çoktan aza.
    let methodCounts: [(name: String, count: Int)]
    /// Durum sınıfları ("2xx".."5xx", "Hata", "İptal") — sabit sırayla, sıfırlar atlanır.
    let statusClassCounts: [(name: String, count: Int)]
    /// En çok istek yapılan host'lar — ilk 5.
    let hostCounts: [(name: String, count: Int)]
    /// En yavaş istekler — ilk 5 (path + süre).
    let slowest: [(path: String, durationMs: Int)]

    var failurePercent: Int {
        totalRequests > 0 ? Int((Double(failureCount) / Double(totalRequests) * 100).rounded()) : 0
    }

    static func compute(from entries: [LogEntry]) -> NetworkStats {
        let infos = entries.compactMap(NetworkLogInfo.init)

        var methodTally: [String: Int] = [:]
        var statusTally: [String: Int] = [:]
        var hostTally: [String: Int] = [:]
        var durations: [Int] = []
        var slow: [(path: String, durationMs: Int)] = []
        var failures = 0, cancelled = 0, reqBytes = 0, respBytes = 0

        for info in infos {
            methodTally[(info.method ?? "GET").uppercased(), default: 0] += 1
            statusTally[Self.statusClass(of: info), default: 0] += 1
            if !info.host.isEmpty { hostTally[info.host, default: 0] += 1 }
            if info.cancelled {
                cancelled += 1
            } else if info.isFailure {
                failures += 1
            }
            reqBytes += info.requestBytes ?? 0
            respBytes += info.responseBytes ?? 0
            if let ms = info.durationMs {
                durations.append(ms)
                slow.append((path: info.path, durationMs: ms))
            }
        }

        durations.sort()
        return NetworkStats(
            totalRequests: infos.count,
            failureCount: failures,
            cancelledCount: cancelled,
            averageDurationMs: durations.isEmpty
                ? nil : durations.reduce(0, +) / durations.count,
            medianDurationMs: durations.isEmpty
                ? nil : durations[durations.count / 2],
            p95DurationMs: durations.isEmpty
                ? nil : durations[min(durations.count - 1, Int(Double(durations.count) * 0.95))],
            totalRequestBytes: reqBytes,
            totalResponseBytes: respBytes,
            methodCounts: methodTally.sorted { $0.value > $1.value }.map { (name: $0.key, count: $0.value) },
            statusClassCounts: Self.statusOrder.compactMap { name in
                statusTally[name].map { (name: name, count: $0) }
            },
            hostCounts: Array(
                hostTally.sorted { $0.value > $1.value }.map { (name: $0.key, count: $0.value) }.prefix(5)
            ),
            slowest: Array(slow.sorted { $0.durationMs > $1.durationMs }.prefix(5))
        )
    }

    // MARK: - Sınıflandırma

    private static let statusOrder = ["2xx", "3xx", "4xx", "5xx", "Hata", "İptal"]

    private static func statusClass(of info: NetworkLogInfo) -> String {
        if info.cancelled { return "İptal" }
        guard let status = info.statusCode else { return "Hata" }
        switch status {
        case 200..<300: return "2xx"
        case 300..<400: return "3xx"
        case 400..<500: return "4xx"
        case 500...: return "5xx"
        default: return "Hata"
        }
    }
}
