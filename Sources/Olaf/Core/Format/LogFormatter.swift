import Foundation

/// Bir `LogEntry`'yi metne dönüştüren strateji. Viewer düz metin formatter'ı,
/// export ise JSON formatter'ı kullanabilir.
public protocol LogFormatter: Sendable {
    func string(from entry: LogEntry) -> String
}
