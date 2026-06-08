#if canImport(UIKit)
import UIKit
import OlafCore
import OlafUpload

/// Rapor sheet'inden gelen 2 alanı + çekilen screenshot'ı + cihaz/app meta'sını toplayıp
/// `OlafUpload`'ın `OlafBugReportService`'ine devreden köprü.
///
/// `Olaf.snapshot()` (tüm kategoriler) servis tarafında toplanır; burada yalnız UI'dan gelen
/// veriyi (screenshot + alanlar + isim) hazırlar.
@MainActor
enum BugReportComposer {

    /// Raporu gönderir.
    /// - Returns: `true` başarıyla yüklendi; `false` kuyruğa düştü / hata.
    static func send(
        whatHappened: String,
        whatExpected: String,
        testerName: String?,
        screenshot: UIImage?
    ) async -> Bool {
        guard let service = OlafUpload.bugReportService else { return false }

        let quality = service.screenshotJPEGQuality
        let maxBytes = service.maxScreenshotBytes
        let jpeg = screenshot.flatMap { encodeJPEG($0, quality: quality, maxBytes: maxBytes) }

        let identity = OlafDeviceIdentity.current()

        return await service.sendReport(
            whatHappened: whatHappened,
            whatExpected: whatExpected,
            testerName: testerName,
            screenshotJPEG: jpeg,
            identity: identity
        )
    }

    /// JPEG'e sıkıştırır; `maxBytes`'ı aşarsa kaliteyi/boyutu kademeli düşürür.
    private static func encodeJPEG(_ image: UIImage, quality: Double, maxBytes: Int) -> Data? {
        var currentQuality = CGFloat(quality)
        var data = image.jpegData(compressionQuality: currentQuality)

        // Önce kaliteyi düşürerek dene.
        while let d = data, maxBytes > 0, d.count > maxBytes, currentQuality > 0.2 {
            currentQuality -= 0.15
            data = image.jpegData(compressionQuality: currentQuality)
        }

        // Hâlâ büyükse ölçeği küçült.
        var scaledImage = image
        while let d = data, maxBytes > 0, d.count > maxBytes,
              scaledImage.size.width > 320, scaledImage.size.height > 320 {
            let newSize = CGSize(width: scaledImage.size.width * 0.7, height: scaledImage.size.height * 0.7)
            scaledImage = resize(scaledImage, to: newSize)
            data = scaledImage.jpegData(compressionQuality: currentQuality)
        }
        return data
    }

    private static func resize(_ image: UIImage, to size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
#endif
