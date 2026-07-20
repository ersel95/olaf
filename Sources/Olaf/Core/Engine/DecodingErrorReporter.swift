import Foundation

extension Olaf {

    /// Bir `Codable` decode hatasını, **hatalı alanın yolunu** (`user.accounts[0].iban` gibi)
    /// çıkararak loglar. Sunucu şeması ile modelin uyuşmadığı yeri, ham yanıt gövdesiyle yan
    /// yana görmeyi sağlar (viewer'da "Decode Hatası" bölümü).
    ///
    /// - Parameters:
    ///   - error: Yakalanan hata (`DecodingError` ise yol/derinlik çıkarılır; değilse açıklaması).
    ///   - url: Yanıtın geldiği URL (varsa) — kaydın hangi isteğe ait olduğunu bağlar.
    ///   - data: Decode edilmeye çalışılan ham gövde (ilk 8000 karakteri kayda eklenir).
    ///   - typeName: Decode edilmek istenen tip adı (`OlafDecoding` otomatik geçirir).
    public static func logDecodingError(
        _ error: Error,
        url: URL? = nil,
        data: Data? = nil,
        typeName: String? = nil,
        category: LogCategory = .decoding,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) {
        let described = DecodingErrorDescriber.describe(error)
        var metadata: [String: String] = ["decoding.detail": described.detail]
        if let path = described.path { metadata["decoding.path"] = path }
        if let typeName { metadata["decoding.type"] = typeName }
        if let url { metadata["url"] = url.absoluteString }
        if let data, !data.isEmpty {
            metadata["responseBody"] = String(decoding: data.prefix(8000), as: UTF8.self)
        }

        var message = "Decode hatası"
        if let typeName { message += " (\(typeName))" }
        if let path = described.path { message += ": \(path)" }
        log(.error, message, category: category, metadata: metadata, file: file, line: line, function: function)
    }
}

/// `JSONDecoder` sarmalayıcısı: başarısız decode'u otomatik loglar ve hatayı **aynen** fırlatır.
///
/// ```swift
/// // try decoder.decode(User.self, from: data) yerine:
/// let user = try OlafDecoding.decode(User.self, from: data, url: response.url)
/// ```
public enum OlafDecoding {

    public static func decode<T: Decodable>(
        _ type: T.Type,
        from data: Data,
        decoder: JSONDecoder = JSONDecoder(),
        url: URL? = nil,
        file: String = #fileID,
        line: Int = #line,
        function: String = #function
    ) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            Olaf.logDecodingError(
                error, url: url, data: data, typeName: String(describing: type),
                file: file, line: line, function: function
            )
            throw error
        }
    }
}

/// `DecodingError`'dan insan-okur yol + açıklama çıkarır. (internal: test edilir.)
enum DecodingErrorDescriber {

    static func describe(_ error: Error) -> (path: String?, detail: String) {
        guard let decodingError = error as? DecodingError else {
            return (nil, (error as NSError).localizedDescription)
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return (
                path(context.codingPath + [key]),
                "Anahtar bulunamadı: '\(key.stringValue)' — \(context.debugDescription)"
            )
        case .typeMismatch(let type, let context):
            return (path(context.codingPath), "Tip uyuşmazlığı: \(type) bekleniyordu — \(context.debugDescription)")
        case .valueNotFound(let type, let context):
            return (path(context.codingPath), "Değer yok (null): \(type) bekleniyordu — \(context.debugDescription)")
        case .dataCorrupted(let context):
            return (path(context.codingPath), "Bozuk veri — \(context.debugDescription)")
        @unknown default:
            return (nil, String(describing: decodingError))
        }
    }

    /// `[user, accounts, 0, iban]` → `"user.accounts[0].iban"`
    private static func path(_ codingPath: [CodingKey]) -> String? {
        guard !codingPath.isEmpty else { return nil }
        var result = ""
        for key in codingPath {
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return result
    }
}
