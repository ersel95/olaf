import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Security)
import Security
#endif

/// Raporu gönderen cihaz/kişi kimliği.
///
/// - **id**: cihaza özel kalıcı kimlik. Önce Keychain'de saklanan UUID (uninstall'a dayanıklı),
///   yoksa `identifierForVendor` ile üretilip Keychain'e yazılır.
/// - **name**: rapor sheet'inde **bir kerelik** girilen isim. Bir kez girilince saklanır,
///   sonraki gönderimlerde sorulmaz.
/// - Model / OS sürümü / locale / ekran her raporda otomatik toplanır.
///
/// Hiçbir gerçek servis adı / sır içermez; tamamen jenerik.
public struct OlafDeviceIdentity: Sendable {

    public let id: String
    public let name: String?
    public let model: String
    public let osVersion: String
    public let locale: String
    public let screen: String

    /// Geçerli kimliği (kalıcı id + saklı isim + cihaz meta) toplar.
    @MainActor
    public static func current() -> OlafDeviceIdentity {
        OlafDeviceIdentity(
            id: persistentDeviceID(),
            name: storedName(),
            model: deviceModel(),
            osVersion: osVersionString(),
            locale: localeIdentifier(),
            screen: screenSize()
        )
    }

    /// Saklanan tester ismi var mı? (sheet'in ilk açılışta isim sorup sormayacağını belirler)
    public static var hasStoredName: Bool {
        storedName()?.isEmpty == false
    }

    /// Bir kerelik tester ismini saklar. Boş/whitespace ise yok sayar.
    /// Cihaz id'si gibi **Keychain'de** saklanır → uygulama silinip yeniden
    /// kurulsa bile isim korunur (UserDefaults reinstall'da silinirdi → isim
    /// her kurulumda yeniden sorulurdu).
    public static func storeName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.write(trimmed, account: nameAccount)
    }

    static func storedName() -> String? {
        if let value = KeychainStore.read(account: nameAccount)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return value
        }
        // Geriye dönük: eski UserDefaults değerini Keychain'e taşı (tek seferlik migrasyon).
        if let legacy = UserDefaults.standard.string(forKey: nameDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !legacy.isEmpty {
            KeychainStore.write(legacy, account: nameAccount)
            return legacy
        }
        return nil
    }

    // MARK: - Kalıcı cihaz kimliği (Keychain → idfv → rastgele)

    private static func persistentDeviceID() -> String {
        if let existing = KeychainStore.read(account: deviceIDAccount), !existing.isEmpty {
            return existing
        }
        let generated = vendorIdentifier() ?? UUID().uuidString
        KeychainStore.write(generated, account: deviceIDAccount)
        return generated
    }

    private static func vendorIdentifier() -> String? {
        #if canImport(UIKit)
        return UIDevice.current.identifierForVendor?.uuidString
        #else
        return nil
        #endif
    }

    // MARK: - Cihaz meta

    private static func deviceModel() -> String {
        // `utsname.machine` donanım modelini verir (örn. "iPhone15,3"). Simülatörde env'den okunur.
        #if targetEnvironment(simulator)
        if let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return identifier
        }
        #endif
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafeBytes(of: &systemInfo.machine) { rawBuffer -> String in
            let bytes = rawBuffer.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return machine.isEmpty ? "unknown" : machine
    }

    private static func osVersionString() -> String {
        #if canImport(UIKit)
        return UIDevice.current.systemVersion
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }

    private static func localeIdentifier() -> String {
        Locale.current.identifier
    }

    @MainActor
    private static func screenSize() -> String {
        #if canImport(UIKit)
        let bounds = UIScreen.main.nativeBounds
        return "\(Int(bounds.width))x\(Int(bounds.height))"
        #else
        return "0x0"
        #endif
    }

    // MARK: - App meta (bundle'dan)

    /// Bundle identifier'ı.
    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "unknown"
    }

    /// Sürüm (`CFBundleShortVersionString`).
    public static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Build (`CFBundleVersion`).
    public static var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    // MARK: - Keys

    private static let nameDefaultsKey = "com.olaf.upload.testerName"
    private static let nameAccount = "com.olaf.upload.testerName"
    private static let deviceIDAccount = "com.olaf.upload.deviceID"
}

// MARK: - Keychain (jenerik, bağımlılıksız)

/// Minimal Keychain sarmalayıcı — sadece string yaz/oku. Hiçbir dış bağımlılık yok.
enum KeychainStore {

    private static let service = "com.olaf.upload"

    static func read(account: String) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #else
        return UserDefaults.standard.string(forKey: service + "." + account)
        #endif
    }

    static func write(_ value: String, account: String) {
        #if canImport(Security)
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
        #else
        UserDefaults.standard.set(value, forKey: service + "." + account)
        #endif
    }
}
