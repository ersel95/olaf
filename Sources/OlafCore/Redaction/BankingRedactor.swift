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
            "otp", "token", "accesstoken", "refreshtoken", "secret",
            "authorization", "auth", "seal", "pan", "iban", "apikey",
            "api_key", "session", "cookie", "signature",
            // Bankacılık gövdesi: bakiye ve kart bilgileri (kısmi, case-insensitive eşleşme).
            "balance", "cardnumber", "card_no", "cardno", "cardnum"
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
                output[key] = redactBodyOrValue(value)
            }
        }
        return output
    }

    private func isSensitiveKey(_ key: String) -> Bool {
        let lowered = key.lowercased()
        return sensitiveKeyTokens.contains { lowered.contains($0) }
    }

    // MARK: - Gövde (JSON) redaksiyonu

    /// Bir metadata değerini redakte eder. Değer geçerli bir JSON gövdesi (object/array) ise
    /// **derin, key-bazlı recursive** redaksiyon uygulanır (token/balance/iban… anahtarları
    /// maskelenir, string yaprakları örüntü-maskelemeden geçer). Parse edilemezse mevcut
    /// value-pattern redaksiyonu (kart/IBAN/email) uygulanır.
    func redactBodyOrValue(_ value: String) -> String {
        if let redactedJSON = redactJSONBody(value) {
            return redactedJSON
        }
        return redact(value)
    }

    /// String bir JSON gövdesiyse (object/array) parse edip recursive redakte eder ve yeniden
    /// serialize eder. JSON değilse (veya skaler JSON ise) `nil` döner → çağıran value-pattern
    /// redaksiyonuna düşer.
    func redactJSONBody(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Yalnız object/array gövdelerini JSON olarak ele al; skaler ("42", "true", "\"x\"")
        // metinleri value-pattern redaksiyonuna bırak.
        guard let first = trimmed.first, first == "{" || first == "[" else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }

        let redacted = redactJSONValue(object, keyIsSensitive: false)

        guard JSONSerialization.isValidJSONObject(redacted),
              let out = try? JSONSerialization.data(
                  withJSONObject: redacted,
                  options: [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
              ),
              let text = String(data: out, encoding: .utf8)
        else { return nil }
        return text
    }

    /// JSON ağacını recursive redakte eder.
    /// - Parameter keyIsSensitive: Üst anahtar hassas ise bu değerin TAMAMI maskelenir
    ///   (nested object/array dahil — örn. `"card": { "pan": ..., "cvv": ... }`).
    private func redactJSONValue(_ value: Any, keyIsSensitive: Bool) -> Any {
        if keyIsSensitive {
            return mask
        }
        switch value {
        case let dict as [String: Any]:
            var output: [String: Any] = [:]
            output.reserveCapacity(dict.count)
            for (key, child) in dict {
                output[key] = redactJSONValue(child, keyIsSensitive: isSensitiveKey(key))
            }
            return output
        case let array as [Any]:
            return array.map { redactJSONValue($0, keyIsSensitive: false) }
        case let string as String:
            return redact(string)
        default:
            // Sayı / bool / null: anahtar hassas değilse olduğu gibi bırak (yukarıda maskelendi).
            return value
        }
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
