import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

enum DownloadQR {
    static func url(appID: String?) -> URL {
        if let appID, !appID.isEmpty, appID.utf8.allSatisfy({ (48...57).contains($0) }) {
            return URL(string: "https://apps.apple.com/app/id\(appID)")!
        }
        return URL(string: "https://apps.apple.com/us/genre/ios/id36")!
    }

    static func image(for url: URL) -> CIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage else { return nil }
        let extent = image.extent.insetBy(dx: -4, dy: -4)
        let white = CIImage(color: .white).cropped(to: extent)
        return image.composited(over: white).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    }
}
