import Foundation
import OlafCore

/// Paylaşım metinlerini üretir (Basit/Tam log formatları). Saf fonksiyonlar → test edilebilir.
/// İçerik zaten redakte edilmiş `LogEntry`/`NetworkLogInfo`'dan üretilir → paylaşıma güvenli.
enum ShareFormatter {

    // MARK: - Network

    /// "Basit Log": özet + header'lar (gövde yok).
    static func simpleNetworkLog(entry: LogEntry, info: NetworkLogInfo) -> String {
        var lines: [String] = []
        lines.append("\(info.method ?? "GET") \(info.url ?? "-")")
        if let status = info.statusCode { lines.append("Durum: \(status)") }
        if let error = info.error { lines.append("Hata: \(error)") }
        if let ms = info.durationMs { lines.append("Süre: \(ms) ms") }
        if let b = info.requestBytes { lines.append("İstek boyutu: \(Formatting.byteCount(b))") }
        if let b = info.responseBytes { lines.append("Yanıt boyutu: \(Formatting.byteCount(b))") }
        lines.append("Zaman: \(entry.date.formatted(date: .numeric, time: .standard))")

        if !info.requestHeaders.isEmpty {
            lines.append("\n-- İstek Header'ları --")
            lines.append(contentsOf: info.requestHeaders.map { "\($0.key): \($0.value)" })
        }
        if !info.responseHeaders.isEmpty {
            lines.append("\n-- Yanıt Header'ları --")
            lines.append(contentsOf: info.responseHeaders.map { "\($0.key): \($0.value)" })
        }
        return lines.joined(separator: "\n")
    }

    /// "Tam Log": Basit + istek/yanıt gövdeleri + cURL.
    static func fullNetworkLog(entry: LogEntry, info: NetworkLogInfo) -> String {
        var text = simpleNetworkLog(entry: entry, info: info)
        if let body = info.requestBody, !body.isEmpty {
            text += "\n\n-- İstek Gövdesi --\n" + body
        }
        if let body = info.responseBody, !body.isEmpty {
            text += "\n\n-- Yanıt Gövdesi --\n" + body
        }
        text += "\n\n-- cURL --\n" + CurlBuilder.curl(from: info)
        return text
    }

    // MARK: - Log

    /// Network olmayan kayıt için tam metin (çok satır).
    static func logDetail(entry: LogEntry) -> String {
        var lines: [String] = []
        lines.append("[\(entry.level.name)] [\(entry.category.rawValue)] \(entry.message)")
        lines.append("Zaman: \(entry.date.formatted(date: .numeric, time: .standard))")
        lines.append("Thread: \(entry.thread)")
        lines.append("Kaynak: \(entry.fileName):\(entry.line) — \(entry.function)")
        if !entry.metadata.isEmpty {
            lines.append("\n-- Metadata --")
            lines.append(contentsOf: entry.metadata.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" })
        }
        return lines.joined(separator: "\n")
    }
}
