import SwiftUI
import CoreText

// ノートに使う手書き風フォント（どれも Google Fonts の SIL Open Font License で、商用でも無料）
enum HandFont: String, CaseIterable {
    case klee, kurenaido, yomogi, yusei, hachimaru

    var name: String {
        switch self {
        case .klee: return "Klee One"
        case .kurenaido: return "Zen Kurenaido"
        case .yomogi: return "Yomogi"
        case .yusei: return "Yusei Magic"
        case .hachimaru: return "Hachi Maru Pop"
        }
    }

    var note: String {
        switch self {
        case .klee: return "ていねいな字"
        case .kurenaido: return "ボールペン風"
        case .yomogi: return "細くてかわいい"
        case .yusei: return "マジック風"
        case .hachimaru: return "丸くてポップ"
        }
    }

    private var path: String {
        switch self {
        case .klee: return "kleeone/KleeOne-SemiBold.ttf"
        case .kurenaido: return "zenkurenaido/ZenKurenaido-Regular.ttf"
        case .yomogi: return "yomogi/Yomogi-Regular.ttf"
        case .yusei: return "yuseimagic/YuseiMagic-Regular.ttf"
        case .hachimaru: return "hachimarupop/HachiMaruPop-Regular.ttf"
        }
    }

    var downloadURL: URL? {
        URL(string: "https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/" + path)
    }

    var fileName: String { "font_" + rawValue + ".ttf" }
}

// フォントの読み込みと登録（一度読み込んだら端末に保存して次回から使い回す）
final class FontStore: ObservableObject {
    static let shared = FontStore()

    @Published private(set) var registeredNames: [HandFont: String] = [:]
    @Published private(set) var loading: Set<HandFont> = []
    @Published var errorMessage = ""

    private var cacheDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    func load(_ font: HandFont) async {
        guard let url = font.downloadURL, registeredNames[font] == nil, !loading.contains(font) else { return }
        await MainActor.run { _ = loading.insert(font) }
        let file = cacheDir.appendingPathComponent(font.fileName)
        do {
            if !FileManager.default.fileExists(atPath: file.path) {
                let (data, _) = try await URLSession.shared.data(from: url)
                try data.write(to: file)
            }
            guard let provider = CGDataProvider(url: file as CFURL),
                  let cgFont = CGFont(provider),
                  let psName = cgFont.postScriptName as String? else {
                try? FileManager.default.removeItem(at: file)
                throw URLError(.cannotDecodeContentData)
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterGraphicsFont(cgFont, &error)   // 登録済みでも続けて使える
            await MainActor.run {
                registeredNames[font] = psName
                loading.remove(font)
                errorMessage = ""
            }
        } catch {
            await MainActor.run {
                loading.remove(font)
                errorMessage = "フォント「\(font.name)」を読み込めませんでした。通信状態を確認してください。"
            }
        }
    }

    // 完成画像や地図の文字用
    func uiFont(_ font: HandFont, size: CGFloat) -> UIFont {
        if let name = registeredNames[font], let f = UIFont(name: name, size: size) {
            return f
        }
        // 読み込むまでは丸い標準の文字
        let base = UIFont.systemFont(ofSize: size, weight: .medium)
        if let rounded = base.fontDescriptor.withDesign(.rounded) {
            return UIFont(descriptor: rounded, size: size)
        }
        return base
    }

    // 画面の文字用
    func font(_ font: HandFont, size: CGFloat) -> Font {
        Font(uiFont(font, size: size) as CTFont)
    }
}
