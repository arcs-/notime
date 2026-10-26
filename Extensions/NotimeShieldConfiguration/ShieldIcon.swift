import NotimeCore
import UIKit

/// The shield's icon: the app icon's shield at about 55% of a transparent canvas. An image
/// can't follow light/dark, so it is theme-neutral: a mid-grey shield with the hands
/// transparent, which reads on both the light and the dark shield background.
enum ShieldIcon {
    static let canvasSide: CGFloat = 180
    /// `systemGray`, fixed so nothing is resolved against the extension's traits.
    static let shieldGrey = UIColor(white: 0.55, alpha: 1)

    static func image() -> UIImage {
        let canvas = CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(bounds: canvas, format: format)
        guard let mark = UIImage(named: "ShieldMark") else {
            NotimeLog.screenTime.error("ShieldMark image missing; shield shows no icon")
            return renderer.image { _ in }.withRenderingMode(.alwaysOriginal)
        }
        let tinted = mark.withTintColor(shieldGrey, renderingMode: .alwaysOriginal)
        let markRect = aspectFit(mark.size, in: canvas.insetBy(dx: canvasSide * 0.225, dy: canvasSide * 0.225))
        return renderer.image { _ in tinted.draw(in: markRect) }.withRenderingMode(.alwaysOriginal)
    }

    private static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(
            x: rect.midX - fitted.width / 2,
            y: rect.midY - fitted.height / 2,
            width: fitted.width,
            height: fitted.height
        )
    }
}
