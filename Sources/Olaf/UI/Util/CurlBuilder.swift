import Foundation

/// `.network` kaydından cURL temsili üretir. Header/gövde değerleri **ham**dır (maskeleme yok);
/// `Authorization`/`Cookie` dahil sırlar çıktıya aynen girer — paylaşmadan önce gözden geçirin.
enum CurlBuilder {
    static func curl(from info: NetworkLogInfo) -> String {
        var lines = ["curl -X \(info.method ?? "GET") \(quote(info.url ?? ""))"]
        for header in info.requestHeaders {
            lines.append("-H \(quote("\(header.key): \(header.value)"))")
        }
        if let body = info.requestBody, !body.isEmpty {
            lines.append("-d \(quote(body))")
        }
        return lines.joined(separator: " \\\n  ")
    }

    /// Tek tırnaklı shell argümanı; içteki tek tırnakları güvenli kaçışla sarar.
    private static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
