import SwiftUI
import CoreLocation

// ノートに貼った写真1枚
struct TripPhoto: Codable, Identifiable, Equatable {
    var id = UUID()
    var latitude: Double?
    var longitude: Double?
    var taken: Date?
    var prefecture = ""          // 例：福島県
    var city = ""                // 例：いわき市
    var added = Date()           // ノートに入れた日時（撮影日時がないときの並び順）
    var transport: Int?          // 1つ前の写真からここまでの移動手段（Transport の番号）

    var transportMode: Transport { Transport(rawValue: transport ?? 0) ?? .car }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var fileName: String { id.uuidString + ".photo" }        // 元の写真
    var thumbName: String { id.uuidString + "_thumb.jpg" }   // ノートに表示する画像

    // 並べる順番（撮影日時の順）
    var sortDate: Date { taken ?? added }
}

// 移動手段
enum Transport: Int, CaseIterable {
    case car, train, shinkansen, bus, bike, plane, ship, walk

    var name: String {
        switch self {
        case .car: return "車"
        case .train: return "電車"
        case .shinkansen: return "新幹線"
        case .bus: return "バス"
        case .bike: return "バイク"
        case .plane: return "飛行機"
        case .ship: return "船"
        case .walk: return "徒歩"
        }
    }

    var emoji: String {
        switch self {
        case .car: return "🚗"
        case .train: return "🚃"
        case .shinkansen: return "🚄"
        case .bus: return "🚌"
        case .bike: return "🏍️"
        case .plane: return "✈️"
        case .ship: return "🚢"
        case .walk: return "🚶"
        }
    }
}

// 紙の色
enum PaperColor: Int, CaseIterable {
    case cork, kraft, cream, white, sky, sakura

    var name: String {
        switch self {
        case .cork: return "コルクボード"
        case .kraft: return "黄色"
        case .cream: return "クリーム"
        case .white: return "白"
        case .sky: return "水色"
        case .sakura: return "桜色"
        }
    }

    var isCork: Bool { self == .cork }

    var color: Color {
        switch self {
        case .cork: return Color(red: 0.80, green: 0.62, blue: 0.42)
        case .kraft: return Color(red: 0.93, green: 0.81, blue: 0.38)
        case .cream: return Color(red: 0.97, green: 0.95, blue: 0.91)
        case .white: return Color(white: 0.99)
        case .sky: return Color(red: 0.86, green: 0.92, blue: 0.96)
        case .sakura: return Color(red: 0.97, green: 0.89, blue: 0.89)
        }
    }
}

// 旅ノート1冊
struct Trip: Codable, Identifiable, Equatable {
    var id = UUID()
    var created = Date()
    var coverIndex = 0
    var paperIndex = 0
    var fontName = HandFont.klee.rawValue
    var photos: [TripPhoto] = []

    static let coverColors: [Color] = [
        Color(red: 0.24, green: 0.42, blue: 0.56),
        Color(red: 0.71, green: 0.33, blue: 0.25),
        Color(red: 0.37, green: 0.48, blue: 0.29),
        Color(red: 0.42, green: 0.36, blue: 0.54),
        Color(red: 0.62, green: 0.47, blue: 0.20),
        Color(red: 0.25, green: 0.50, blue: 0.50)
    ]

    var coverColor: Color { Self.coverColors[coverIndex % Self.coverColors.count] }
    var paper: PaperColor { PaperColor(rawValue: paperIndex) ?? .cork }
    var font: HandFont { HandFont(rawValue: fontName) ?? .klee }

    // 撮影日時の順に並べた写真
    var sortedPhotos: [TripPhoto] { photos.sorted { $0.sortDate < $1.sortDate } }

    // 行った県（行った順、重複なし）
    var prefectures: [String] {
        var seen: [String] = []
        for p in sortedPhotos where !p.prefecture.isEmpty && !seen.contains(p.prefecture) {
            seen.append(p.prefecture)
        }
        return seen
    }

    var sortedDates: [Date] { photos.compactMap { $0.taken }.sorted() }

    // 題名は写真から自動で付ける（例：2026年5月 福島・宮城）
    var title: String {
        if photos.isEmpty { return "新しい旅" }
        let prefs = prefectures.map(Trip.shortPrefecture).joined(separator: "・")
        guard let first = sortedDates.first else { return prefs.isEmpty ? "旅の記録" : prefs }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月"
        return prefs.isEmpty ? f.string(from: first) : f.string(from: first) + " " + prefs
    }

    // ノートの左上に書く日付（例：2026年5月29日〜5月31日）
    var dateRangeJa: String {
        let dates = sortedDates
        guard let first = dates.first, let last = dates.last else { return "" }
        let cal = Calendar(identifier: .gregorian)
        let f = DateFormatter()
        f.locale = Locale(identifier: "ja_JP")
        f.dateFormat = "yyyy年M月d日"
        let a = f.string(from: first)
        if cal.isDate(first, inSameDayAs: last) { return a }
        if cal.component(.year, from: first) == cal.component(.year, from: last) {
            f.dateFormat = "M月d日"
        }
        return a + "〜" + f.string(from: last)
    }

    var dateRangeText: String {
        let dates = sortedDates
        guard let first = dates.first, let last = dates.last else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        let a = f.string(from: first), b = f.string(from: last)
        return a == b ? a : a + " – " + b
    }

    static func shortPrefecture(_ s: String) -> String {
        if s == "北海道" { return s }
        if s.hasSuffix("県") || s.hasSuffix("府") || s.hasSuffix("都") { return String(s.dropLast()) }
        return s
    }
}

// 旅ノートの保存と読み込み（端末の中の「書類」フォルダに保存）
final class TripStore: ObservableObject {
    static let shared = TripStore()

    @Published private(set) var trips: [Trip] = []
    private let imageCache = NSCache<NSString, UIImage>()

    private var root: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("TripLog", isDirectory: true)
    }

    init() {
        load()
    }

    func folder(_ id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func load() {
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dirs = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var list: [Trip] = []
        for dir in dirs {
            if let data = try? Data(contentsOf: dir.appendingPathComponent("trip.json")),
               let trip = try? JSONDecoder().decode(Trip.self, from: data) {
                list.append(trip)
            }
        }
        trips = list.sorted { $0.created > $1.created }
    }

    func trip(_ id: UUID) -> Trip? {
        trips.first { $0.id == id }
    }

    func save(_ trip: Trip) {
        let dir = folder(trip.id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(trip) {
            try? data.write(to: dir.appendingPathComponent("trip.json"))
        }
        if let i = trips.firstIndex(where: { $0.id == trip.id }) {
            trips[i] = trip
        } else {
            trips.insert(trip, at: 0)
        }
    }

    func setTransport(_ mode: Transport, photoIDs: [UUID], in tripID: UUID) {
        update(tripID) { t in
            for i in t.photos.indices where photoIDs.contains(t.photos[i].id) {
                t.photos[i].transport = mode.rawValue
            }
        }
    }

    func update(_ id: UUID, _ change: (inout Trip) -> Void) {
        guard var t = trip(id) else { return }
        change(&t)
        save(t)
    }

    func newTrip() -> Trip {
        var t = Trip()
        t.coverIndex = trips.count % Trip.coverColors.count
        save(t)
        return t
    }

    func delete(_ trip: Trip) {
        try? FileManager.default.removeItem(at: folder(trip.id))
        trips.removeAll { $0.id == trip.id }
    }

    // MARK: - 写真

    func thumbnail(_ tripID: UUID, _ photo: TripPhoto) -> UIImage? {
        let key = photo.id.uuidString as NSString
        if let img = imageCache.object(forKey: key) { return img }
        let url = folder(tripID).appendingPathComponent(photo.thumbName)
        guard let img = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache.setObject(img, forKey: key)
        return img
    }

    func removePhoto(_ photo: TripPhoto, from tripID: UUID) {
        let dir = folder(tripID)
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(photo.fileName))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(photo.thumbName))
        imageCache.removeObject(forKey: photo.id.uuidString as NSString)
        update(tripID) { t in t.photos.removeAll { $0.id == photo.id } }
    }

    @MainActor
    func addPhoto(data: Data, to tripID: UUID) async {
        guard let info = PhotoLoader.load(data) else { return }
        var photo = TripPhoto()
        photo.latitude = info.coordinate?.latitude
        photo.longitude = info.coordinate?.longitude
        photo.taken = info.date?.asDate
        if let c = info.coordinate {
            let names = await PhotoLoader.placeNames(for: c)
            photo.prefecture = names.prefJa
            photo.city = names.cityJa
        }

        let dir = folder(tripID)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(to: dir.appendingPathComponent(photo.fileName))
        if let thumb = Self.makeThumbnail(info.image, maxSide: 1200),
           let jpg = thumb.jpegData(compressionQuality: 0.85) {
            try? jpg.write(to: dir.appendingPathComponent(photo.thumbName))
        }

        update(tripID) { t in t.photos.append(photo) }
    }

    static func makeThumbnail(_ image: UIImage, maxSide: CGFloat) -> UIImage? {
        let w = image.size.width, h = image.size.height
        guard w > 0, h > 0 else { return nil }
        let s = min(1, maxSide / max(w, h))
        let size = CGSize(width: (w * s).rounded(), height: (h * s).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

extension PhotoDate {
    var asDate: Date? {
        var c = DateComponents()
        c.year = Int(year)
        c.month = Int(month)
        c.day = Int(day)
        c.hour = hour
        c.minute = Int(minute)
        return Calendar(identifier: .gregorian).date(from: c)
    }
}
