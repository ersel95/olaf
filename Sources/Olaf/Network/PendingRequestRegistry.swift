import Foundation

/// Devam eden (henüz tamamlanmamış) bir network yakalaması.
public struct PendingNetworkRequest: Identifiable, Sendable {
    public let id: UUID
    public let method: String
    public let url: String
    public let startDate: Date

    /// Başlangıçtan bu yana geçen süre (saniye).
    public var elapsedSeconds: Int {
        max(0, Int(Date().timeIntervalSince(startDate)))
    }
}

/// In-flight yakalamaların kilitle korunan kaydı. `OlafURLProtocol` isteği başlatırken kaydeder,
/// tamamlanınca (başarı/hata/iptal) düşürür. Viewer "Aktif istekler" bölümünü buradan besler —
/// 1 sn'lik `TimelineView` tick'i ile anlık görüntü okunur; ayrı yayın mekanizması gerekmez.
final class PendingRequestRegistry: @unchecked Sendable {

    static let shared = PendingRequestRegistry()

    private let lock = NSLock()
    private var items: [UUID: PendingNetworkRequest] = [:]

    func register(method: String, url: String) -> UUID {
        let request = PendingNetworkRequest(id: UUID(), method: method, url: url, startDate: Date())
        lock.lock(); items[request.id] = request; lock.unlock()
        return request.id
    }

    func unregister(_ id: UUID) {
        lock.lock(); items[id] = nil; lock.unlock()
    }

    /// Başlangıç zamanına göre (en eski üstte) sıralı anlık görüntü.
    var snapshot: [PendingNetworkRequest] {
        lock.lock(); defer { lock.unlock() }
        return items.values.sorted { $0.startDate < $1.startDate }
    }

    /// Test izolasyonu için: tüm kayıtları düşürür.
    func removeAll() {
        lock.lock(); items.removeAll(); lock.unlock()
    }
}
