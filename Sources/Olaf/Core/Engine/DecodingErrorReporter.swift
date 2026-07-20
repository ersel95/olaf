import Foundation

extension Olaf {

    /// Logs a `Codable` decoding error, extracting **the path of the offending field**
    /// (e.g. `user.accounts[0].iban`). Lets you see where the server schema and the model
    /// disagree side-by-side with the raw response body (the "Decoding Error" section in the viewer).
    ///
    /// - Parameters:
    ///   - error: The caught error (path/detail are extracted if it's a `DecodingError`; otherwise its description).
    ///   - url: The URL the response came from (if any) — ties the entry to the request it belongs to.
    ///   - data: The raw body that failed to decode (its first 8000 characters are added to the entry).
    ///   - typeName: The name of the type that was being decoded (`OlafDecoding` passes this automatically).
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

        var message = "Decoding error"
        if let typeName { message += " (\(typeName))" }
        if let path = described.path { message += ": \(path)" }
        log(.error, message, category: category, metadata: metadata, file: file, line: line, function: function)
    }
}

/// `JSONDecoder` wrapper: automatically logs a failed decode and rethrows the error **as-is**.
///
/// ```swift
/// // Instead of try decoder.decode(User.self, from: data):
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

/// Extracts a human-readable path + description from a `DecodingError`. (internal: tested.)
enum DecodingErrorDescriber {

    static func describe(_ error: Error) -> (path: String?, detail: String) {
        guard let decodingError = error as? DecodingError else {
            return (nil, (error as NSError).localizedDescription)
        }
        switch decodingError {
        case .keyNotFound(let key, let context):
            return (
                path(context.codingPath + [key]),
                "Key not found: '\(key.stringValue)' — \(context.debugDescription)"
            )
        case .typeMismatch(let type, let context):
            return (path(context.codingPath), "Type mismatch: expected \(type) — \(context.debugDescription)")
        case .valueNotFound(let type, let context):
            return (path(context.codingPath), "Value not found (null): expected \(type) — \(context.debugDescription)")
        case .dataCorrupted(let context):
            return (path(context.codingPath), "Corrupted data — \(context.debugDescription)")
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
