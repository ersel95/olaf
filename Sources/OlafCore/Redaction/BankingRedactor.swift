import Foundation

/// Bankacılık seviyesinde varsayılan redaksiyon. Kart numarası, IBAN, e-posta, telefon
/// gibi örüntüleri ve `password/pin/cvv/otp/token/seal...` gibi hassas metadata anahtarlarını
/// maskeler. Maskeleme geri döndürülemez (yıldızlama).
public struct BankingRedactor: Redactor {

    /// Değeri tamamen maskelenecek metadata anahtarları (küçük harf, "içerir" eşleşmesi).
    private let sensitiveKeyTokens: [String]
    private let mask = "***"

    public init(additionalSensitiveKeys: [String] = []) {
        self.sensitiveKeyTokens = ([
            "password", "passwd", "pwd", "pin", "cvv", "cvc", "cvc2",
            "otp", "token", "secret", "authorization", "auth",
            "seal", "pan", "iban", "apikey", "api_key", "accesstoken",
            "refreshtoken", "session", "cookie", "signature"
        ] + additionalSensitiveKeys).map { $0.lowercased() }
    }

    // MARK: - Redactor

    public func redact(_ text: String) -> String {
        var result = text
        result = Self.maskCardNumbers(in: result)
        result = Self.maskIBANs(in: result)
        result = Self.maskEmails(in: result)
        return result
    }

    public func redact(metadata: [String: String]) -> [String: String] {
        var output: [String: String] = [:]
        output.reserveCapacity(metadata.count)
        for (key, value) in metadata {
            if isSensitiveKey(key) {
                output[key] = mask
            } else {
                output[key] = redact(value)
            }
        }
        return output
    }

    private func isSensitiveKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return sensitiveKeyTokens.contains { lowered.contains($0) }
    }

    // MARK: - Örüntü maskeleme

    /// 13–19 haneli kart numaraları (boşluk/tire ile ayrılmış olabilir) → son 4 hane görünür.
    static func maskCardNumbers(in text: String) -> String {
        let pattern = #"\b\d(?:[ -]?\d){12,18}\b"#
        return replaceMatches(of: pattern, in: text) { match in
            let digits = match.filter(\.isNumber)
            guard digits.count >= 13, digits.count <= 19 else { return match }
            let last4 = String(digits.suffix(4))
            return "**** **** **** \(last4)"
        }
    }

    /// IBAN (2 harf + 2 kontrol hanesi + 11–30 alfasayısal) → ilk 4 + son 4 görünür.
    static func maskIBANs(in text: String) -> String {
        let pattern = #"\b[A-Z]{2}\d{2}[A-Z0-9]{11,30}\b"#
        return replaceMatches(of: pattern, in: text) { match in
            let compact = match.replacingOccurrences(of: " ", with: "")
            guard compact.count >= 12 else { return match }
            let prefix = compact.prefix(4)
            let suffix = compact.suffix(4)
            return "\(prefix)****\(suffix)"
        }
    }

    /// E-posta → local kısmının ilk karakteri görünür: `e***@domain`.
    static func maskEmails(in text: String) -> String {
        let pattern = #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#
        return replaceMatches(of: pattern, in: text) { match in
            guard let atIndex = match.firstIndex(of: "@") else { return match }
            let local = match[match.startIndex..<atIndex]
            let domain = match[atIndex...]
            let firstChar = local.first.map(String.init) ?? ""
            return "\(firstChar)***\(domain)"
        }
    }

    // MARK: - Regex yardımcısı

    private static func replaceMatches(
        of pattern: String,
        in text: String,
        transform: (String) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: fullRange)
        guard !matches.isEmpty else { return text }

        var result = text
        // Sondan başa doğru değiştir ki aralıklar kaymasın.
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let original = String(result[range])
            result.replaceSubrange(range, with: transform(original))
        }
        return result
    }
}
