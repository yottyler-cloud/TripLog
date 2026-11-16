import SwiftUI

// コルクボードの模様（毎回同じ模様になるように、決まった順の乱数で点を打つ）
enum CorkTexture {
    private static var cache: [String: UIImage] = [:]

    static func image(size: CGSize) -> UIImage {
        let w = max(1, size.width.rounded()), h = max(1, size.height.rounded())
        let key = "\(Int(w))x\(Int(h))"
        if let img = cache[key] { return img }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let img = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
            let cg = ctx.cgContext
            UIColor(red: 0.80, green: 0.62, blue: 0.42, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: w, height: h))

            var seed: UInt64 = 20261116
            func rand() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat((seed >> 33) % 10000) / 10000
            }

            // 細かいつぶつぶ
            let count = Int(w * h / 22)
            for _ in 0..<count {
                let x = rand() * w, y = rand() * h
                let r = 0.6 + rand() * 1.8
                let t = rand()
                let color: UIColor
                if t < 0.45 {
                    color = UIColor(red: 0.55, green: 0.38, blue: 0.22, alpha: 0.35 + rand() * 0.3)
                } else if t < 0.8 {
                    color = UIColor(red: 0.92, green: 0.78, blue: 0.58, alpha: 0.35 + rand() * 0.3)
                } else {
                    color = UIColor(red: 0.42, green: 0.27, blue: 0.14, alpha: 0.3 + rand() * 0.3)
                }
                color.setFill()
                cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 1.6))
            }

            // 木の枠
            UIColor(red: 0.45, green: 0.29, blue: 0.16, alpha: 1).setStroke()
            cg.setLineWidth(14)
            cg.stroke(CGRect(x: 7, y: 7, width: w - 14, height: h - 14))
            UIColor(red: 0.60, green: 0.41, blue: 0.24, alpha: 1).setStroke()
            cg.setLineWidth(3)
            cg.stroke(CGRect(x: 15.5, y: 15.5, width: w - 31, height: h - 31))
        }
        cache[key] = img
        return img
    }
}

// 写真を留める押しピン
struct PushPin: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.82, green: 0.17, blue: 0.16))
            Circle()
                .fill(Color.white.opacity(0.55))
                .frame(width: size * 0.32, height: size * 0.32)
                .offset(x: -size * 0.16, y: -size * 0.16)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: size * 0.12, x: size * 0.08, y: size * 0.15)
    }
}
