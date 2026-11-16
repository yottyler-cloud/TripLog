import SwiftUI
import PhotosUI
import PencilKit
import CoreLocation

// ノートの色
enum NoteInk {
    static let ink = Color(red: 0.20, green: 0.20, blue: 0.19)
    static let ink2 = Color(red: 0.36, green: 0.34, blue: 0.31)
    static let red = Color(red: 0.86, green: 0.25, blue: 0.24)
    static let fills: [Color] = [
        Color(red: 0.47, green: 0.75, blue: 0.95),
        Color(red: 0.60, green: 0.84, blue: 0.70),
        Color(red: 0.97, green: 0.70, blue: 0.62),
        Color(red: 0.78, green: 0.70, blue: 0.93),
        Color(red: 0.98, green: 0.86, blue: 0.55)
    ]
}

// 手書きのペンの種類
enum PenChoice: String, CaseIterable {
    case black, red, blue, marker, eraser

    var name: String {
        switch self {
        case .black: return "黒"
        case .red: return "赤"
        case .blue: return "青"
        case .marker: return "蛍光ペン"
        case .eraser: return "消しゴム"
        }
    }

    var swatch: Color {
        switch self {
        case .black: return .black
        case .red: return Color(red: 0.84, green: 0.2, blue: 0.17)
        case .blue: return Color(red: 0.18, green: 0.37, blue: 0.66)
        case .marker: return .yellow
        case .eraser: return .gray
        }
    }

    var pkTool: PKTool {
        switch self {
        case .black: return PKInkingTool(.pen, color: .black, width: 4)
        case .red: return PKInkingTool(.pen, color: UIColor(red: 0.84, green: 0.2, blue: 0.17, alpha: 1), width: 4)
        case .blue: return PKInkingTool(.pen, color: UIColor(red: 0.18, green: 0.37, blue: 0.66, alpha: 1), width: 4)
        case .marker: return PKInkingTool(.marker, color: UIColor.systemYellow, width: 18)
        case .eraser: return PKEraserTool(.vector)
        }
    }
}

// MARK: - 旅ノートの画面

struct NotebookView: View {
    let tripID: UUID
    let onClose: () -> Void

    @ObservedObject private var store = TripStore.shared
    @ObservedObject private var maps = MapStore.shared
    @ObservedObject private var fonts = FontStore.shared

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var adding = false
    @State private var selectedID: UUID?
    @State private var removing: TripPhoto?
    @State private var penMode = false
    @State private var pen: PenChoice = .black
    @State private var drawing = PKDrawing()
    @State private var drawingLoaded = false
    @State private var undoTick = 0
    @State private var pageSize: CGSize = .zero
    @State private var exported: RenderResult?

    var trip: Trip? { store.trip(tripID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if penMode { penBar }
            if !fonts.errorMessage.isEmpty {
                Text(fonts.errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(6)
            }
            GeometryReader { geo in
                if let trip {
                    page(trip: trip, size: geo.size)
                        .onAppear { pageSize = geo.size }
                        .onChange(of: geo.size) { _, s in pageSize = s }
                }
            }
            .padding(16)
        }
        .foregroundStyle(.white)
        .background(Color(white: 0.16).ignoresSafeArea())
        .task {
            loadDrawing()
            if let trip { await fonts.load(trip.font) }
            await maps.loadIfNeeded()
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await addPhotos(items) }
        }
        .onChange(of: drawing) { _, d in
            if drawingLoaded { saveDrawing(d) }
        }
        .fullScreenCover(item: $exported) { r in
            ResultView(result: r)
        }
        .confirmationDialog("この写真をノートから外しますか？",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("外す", role: .destructive) {
                if let p = removing {
                    store.removePhoto(p, from: tripID)
                    selectedID = nil
                }
                removing = nil
            }
            Button("やめる", role: .cancel) { removing = nil }
        } message: {
            Text("写真アプリの元の写真は消えません。")
        }
    }

    // 上のボタン列
    var header: some View {
        HStack(spacing: 12) {
            Button {
                onClose()
            } label: {
                Label("本棚", systemImage: "chevron.backward")
            }
            .buttonStyle(.bordered)

            VStack(alignment: .leading, spacing: 2) {
                Text(trip?.title ?? "")
                    .font(.headline)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if adding || maps.lines.isEmpty || !fonts.loading.isEmpty {
                ProgressView().tint(.white)
            }

            PhotosPicker(selection: $pickerItems, maxSelectionCount: 30, matching: .images) {
                Label("写真を追加", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .disabled(adding)

            Menu {
                Picker("紙の色", selection: Binding(
                    get: { trip?.paperIndex ?? 0 },
                    set: { v in store.update(tripID) { $0.paperIndex = v } })) {
                    ForEach(PaperColor.allCases, id: \.self) { p in
                        Text(p.name).tag(p.rawValue)
                    }
                }
                Picker("文字", selection: Binding(
                    get: { trip?.fontName ?? HandFont.klee.rawValue },
                    set: { v in
                        store.update(tripID) { $0.fontName = v }
                        if let f = HandFont(rawValue: v) {
                            Task { await fonts.load(f) }
                        }
                    })) {
                    ForEach(HandFont.allCases, id: \.self) { f in
                        Text("\(f.name)（\(f.note)）").tag(f.rawValue)
                    }
                }
            } label: {
                Label("見た目", systemImage: "paintpalette")
            }
            .buttonStyle(.bordered)

            Button {
                penMode.toggle()
                selectedID = nil
            } label: {
                Label(penMode ? "ペンを終わる" : "ペン", systemImage: "pencil.tip")
            }
            .buttonStyle(.bordered)
            .tint(penMode ? .orange : nil)

            Button {
                exportImage()
            } label: {
                Label("画像で書き出し", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.09))
    }

    var subtitle: String {
        guard let trip else { return "" }
        var parts: [String] = []
        if !trip.dateRangeText.isEmpty { parts.append(trip.dateRangeText) }
        parts.append("写真 \(trip.photos.count)枚")
        if !trip.prefectures.isEmpty { parts.append("\(trip.prefectures.count)県") }
        return parts.joined(separator: "　・　")
    }

    // ペンを選ぶ列
    var penBar: some View {
        HStack(spacing: 10) {
            ForEach(PenChoice.allCases, id: \.self) { choice in
                Button {
                    pen = choice
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(choice.swatch).frame(width: 14, height: 14)
                        Text(choice.name)
                    }
                }
                .buttonStyle(.bordered)
                .tint(pen == choice ? .orange : nil)
            }
            Button {
                undoTick += 1
            } label: {
                Label("1つ戻す", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.bordered)
            Spacer()
            Text("指でも書けます")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(white: 0.12))
    }

    // ノートのページ
    func page(trip: Trip, size: CGSize) -> some View {
        let rects = NotebookPage.rects(for: size)
        let sorted = trip.sortedPhotos
        // 大きい写真を出す場所（地図は見えたままにする）
        let overlay = size.width >= size.height
            ? CGRect(x: rects.photos.minX - 12, y: 0, width: size.width - rects.photos.minX + 12, height: size.height)
            : CGRect(x: 0, y: rects.photos.minY - 12, width: size.width, height: size.height - rects.photos.minY + 12)
        return ZStack(alignment: .topLeading) {
            NotebookPage(trip: trip, lines: maps.lines, size: size, selectedID: selectedID,
                         fontReady: fonts.registeredNames[trip.font] != nil,
                         editable: !penMode,
                         onTapPhoto: { p in selectedID = p.id })

            // 手書きメモ（ペンのときだけ書ける）
            DrawingCanvas(drawing: $drawing, isActive: penMode, tool: pen.pkTool, undoTick: undoTick)
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(penMode)

            // タッチした写真を大きく
            if let id = selectedID, let index = sorted.firstIndex(where: { $0.id == id }) {
                let photo = sorted[index]
                EnlargedPhoto(image: store.thumbnail(tripID, photo), number: index + 1, total: sorted.count,
                              photo: photo, font: trip.font,
                              onPrev: index > 0 ? { selectedID = sorted[index - 1].id } : nil,
                              onNext: index < sorted.count - 1 ? { selectedID = sorted[index + 1].id } : nil,
                              onRemove: { removing = photo },
                              onClose: { selectedID = nil })
                    .frame(width: overlay.width, height: overlay.height)
                    .offset(x: overlay.minX, y: overlay.minY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 写真の追加・手書き・書き出し

    func addPhotos(_ items: [PhotosPickerItem]) async {
        adding = true
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await store.addPhoto(data: data, to: tripID)
            }
        }
        pickerItems = []
        adding = false
    }

    var drawingURL: URL {
        store.folder(tripID).appendingPathComponent("drawing.data")
    }

    func loadDrawing() {
        if let data = try? Data(contentsOf: drawingURL), let d = try? PKDrawing(data: data) {
            drawing = d
        }
        drawingLoaded = true
    }

    func saveDrawing(_ d: PKDrawing) {
        try? d.dataRepresentation().write(to: drawingURL)
    }

    // ページを1枚の画像にする（手書きメモも重ねる）
    @MainActor
    func exportImage() {
        guard let trip, pageSize.width > 0, pageSize.height > 0 else { return }
        let size = pageSize
        let content = NotebookPage(trip: trip, lines: maps.lines, size: size, selectedID: nil,
                                   fontReady: fonts.registeredNames[trip.font] != nil, editable: false)
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let base = renderer.uiImage else { return }

        var ink = UIImage()
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            ink = drawing.image(from: CGRect(origin: .zero, size: size), scale: 2)
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            base.draw(in: CGRect(origin: .zero, size: size))
            ink.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let jpg = image.jpegData(compressionQuality: 0.9) else { return }
        exported = RenderResult(image: image, jpeg: JPEGFile(data: jpg))
    }
}

// MARK: - ノートの1ページ（左上に日付、左に県の地図と道のり、右に写真）

struct NotebookPage: View {
    let trip: Trip
    let lines: [MapLine]
    let size: CGSize
    var selectedID: UUID? = nil
    var fontReady = false          // フォントが読み込まれたら描き直すための目印
    var editable = false
    var onTapPhoto: ((TripPhoto) -> Void)? = nil

    // 横向きなら左右、縦向きなら上下に分ける
    static func rects(for size: CGSize) -> (date: CGPoint, map: CGRect, photos: CGRect) {
        let pad = min(size.width, size.height) * 0.04
        if size.width >= size.height {
            return (CGPoint(x: pad * 1.5, y: pad),
                    CGRect(x: pad, y: size.height * 0.13, width: size.width * 0.52 - pad, height: size.height * 0.87 - pad),
                    CGRect(x: size.width * 0.55, y: pad, width: size.width * 0.45 - pad, height: size.height - pad * 2))
        }
        return (CGPoint(x: pad * 1.5, y: pad),
                CGRect(x: pad, y: size.height * 0.09, width: size.width - pad * 2, height: size.height * 0.42),
                CGRect(x: pad, y: size.height * 0.53, width: size.width - pad * 2, height: size.height * 0.47 - pad))
    }

    var body: some View {
        let rects = Self.rects(for: size)
        let sorted = trip.sortedPhotos
        let dateSize = min(size.width, size.height) * 0.045
        ZStack(alignment: .topLeading) {
            if trip.paper.isCork {
                Image(uiImage: CorkTexture.image(size: size))
                    .resizable()
                    .frame(width: size.width, height: size.height)
            } else {
                trip.paper.color
            }

            // 左上の日付
            Text(trip.photos.isEmpty ? "旅の写真を入れてください" : (trip.dateRangeJa.isEmpty ? trip.title : trip.dateRangeJa))
                .font(FontStore.shared.font(trip.font, size: dateSize))
                .foregroundStyle(NoteInk.ink)
                .offset(x: rects.date.x, y: rects.date.y)

            // 県の地図と道のり
            RouteMap(lines: lines, photos: sorted, selectedID: selectedID, font: trip.font,
                     paper: trip.paper.color, fontReady: fontReady)
                .frame(width: rects.map.width, height: rects.map.height)
                .offset(x: rects.map.minX, y: rects.map.minY)

            // 写真
            PhotoGrid(trip: trip, photos: sorted, size: rects.photos.size, pinned: trip.paper.isCork, onTap: onTapPhoto)
                .frame(width: rects.photos.width, height: rects.photos.height)
                .offset(x: rects.photos.minX, y: rects.photos.minY)
                .allowsHitTesting(editable)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

// MARK: - 県の地図と道のり

struct RouteMap: View {
    let lines: [MapLine]
    let photos: [TripPhoto]       // 撮影日時の順
    let selectedID: UUID?
    let font: HandFont
    let paper: Color
    let fontReady: Bool

    var body: some View {
        GeometryReader { geo in
            let layout = Self.layout(size: geo.size, lines: lines, photos: photos, selectedID: selectedID)
            ZStack(alignment: .topLeading) {
                // 地図（写真を選ぶと、その県を拡大した地図にふわっと切り替わる）
                Canvas { ctx, _ in
                    Self.draw(&ctx, layout: layout, lines: lines, font: font)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .id(selectedID)
                .transition(.opacity.combined(with: .scale(scale: 0.94)))

                // 動く「ココ!」
                if let dot = layout.selectedPoint, let rect = layout.kokoRect {
                    KokoMark(rect: rect, dot: dot, radius: layout.dotRadius * 1.3, size: geo.size)
                        .id(selectedID)
                }
            }
            .animation(.easeInOut(duration: 0.35), value: selectedID)
        }
    }

    // MARK: 配置の計算

    struct Fit {
        let area: CGRect          // 範囲（経度・緯度）
        let cosLat: CGFloat
        let scale: CGFloat
        let ox: CGFloat
        let oy: CGFloat

        func pt(_ lon: CGFloat, _ lat: CGFloat) -> CGPoint {
            CGPoint(x: ox + (lon - area.minX) * cosLat * scale, y: oy + (area.maxY - lat) * scale)
        }

        static func make(area a: CGRect, into usable: CGRect) -> Fit {
            let cosLat = CGFloat(cos(Double(a.midY) * .pi / 180))
            let wDeg = max(a.width * cosLat, 0.0001), hDeg = max(a.height, 0.0001)
            let scale = min(usable.width / wDeg, usable.height / hDeg)
            return Fit(area: a, cosLat: cosLat, scale: scale,
                       ox: usable.minX + (usable.width - wDeg * scale) / 2,
                       oy: usable.minY + (usable.height - hDeg * scale) / 2)
        }
    }

    struct DrawGroup {
        let group: Int
        let colorIndex: Int?      // 行った県なら色の番号、まわりの県は nil
        let emphasized: Bool      // 拡大したときの主役の県
    }

    struct Layout {
        var fits: [Int: Fit] = [:]
        var backings: [[Int]] = []            // 影を付けて敷く白い紙（まとまりごと）
        var drawGroups: [DrawGroup] = []
        var labels: [(text: String, point: CGPoint)] = []
        var points: [(id: UUID, number: Int, point: CGPoint)] = []
        var dotRadius: CGFloat = 10
        var labelSize: CGFloat = 18
        var selectedID: UUID?
        var selectedPoint: CGPoint?
        var kokoRect: CGRect?
        var clip: CGRect = .zero
    }

    static func boxes(count n: Int, size: CGSize) -> [CGRect] {
        let w = size.width, h = size.height
        if n <= 1 { return [CGRect(origin: .zero, size: size)] }
        if n == 2 {
            return [CGRect(x: 0, y: 0, width: w * 0.6, height: h * 0.58),
                    CGRect(x: w * 0.4, y: h * 0.42, width: w * 0.6, height: h * 0.58)]
        }
        let rows = (n + 1) / 2
        let cellW = w / 2, cellH = h / CGFloat(rows)
        return (0..<n).map { i in
            CGRect(x: CGFloat(i % 2) * cellW, y: CGFloat(i / 2) * cellH, width: cellW, height: cellH)
        }
    }

    static func layout(size: CGSize, lines: [MapLine], photos: [TripPhoto], selectedID: UUID?) -> Layout {
        var L = Layout()
        L.selectedID = selectedID
        L.clip = CGRect(origin: .zero, size: size)
        guard !lines.isEmpty, size.width > 0, size.height > 0 else { return L }
        L.labelSize = max(14, min(28, min(size.width, size.height) * 0.06))
        L.dotRadius = max(9, min(14, min(size.width, size.height) * 0.024))

        // 写真ごとの県と、行った順の県
        var groups: [Int] = []
        var photoGroup: [UUID: Int] = [:]
        var groupName: [Int: String] = [:]
        for p in photos {
            guard let c = p.coordinate, let g = MapData.prefectureGroup(at: c, lines: lines) else { continue }
            photoGroup[p.id] = g
            if !groups.contains(g) { groups.append(g) }
            if groupName[g] == nil, !p.prefecture.isEmpty { groupName[g] = Trip.shortPrefecture(p.prefecture) }
        }
        guard !groups.isEmpty else { return L }

        // 県ごとの範囲（遠く離れた小さな島は入れず、本土を中心にする）
        var largest: [Int: CGFloat] = [:]
        for line in lines where !line.isLake {
            let a = (line.maxX - line.minX) * (line.maxY - line.minY)
            largest[line.group] = max(largest[line.group] ?? 0, a)
        }
        var groupAreas: [Int: CGRect] = [:]
        for line in lines where !line.isLake {
            let a = (line.maxX - line.minX) * (line.maxY - line.minY)
            guard a >= (largest[line.group] ?? 0) * 0.08 else { continue }
            let b = CGRect(x: line.minX, y: line.minY, width: line.maxX - line.minX, height: line.maxY - line.minY)
            groupAreas[line.group] = groupAreas[line.group]?.union(b) ?? b
        }
        // 島で撮った写真があれば、その場所も範囲に入れる
        for p in photos {
            guard let g = photoGroup[p.id], let c = p.coordinate else { continue }
            let spot = CGRect(x: c.longitude - 0.03, y: c.latitude - 0.03, width: 0.06, height: 0.06)
            groupAreas[g] = groupAreas[g]?.union(spot) ?? spot
        }

        if let sel = selectedID, let target = photoGroup[sel], let targetArea = groupAreas[target] {
            // ── 拡大：撮影した県を大きく。まわりの県も薄く描く
            let area = targetArea.insetBy(dx: -targetArea.width * 0.08, dy: -targetArea.height * 0.08)
            let fit = Fit.make(area: area, into: CGRect(origin: .zero, size: size).insetBy(dx: 14, dy: 14))
            for (g, a) in groupAreas where a.intersects(area) {
                L.fits[g] = fit
                if g != target && !groups.contains(g) {
                    L.drawGroups.append(DrawGroup(group: g, colorIndex: nil, emphasized: false))
                }
            }
            for (i, g) in groups.enumerated() where L.fits[g] != nil && g != target {
                L.drawGroups.append(DrawGroup(group: g, colorIndex: i, emphasized: false))
            }
            if let i = groups.firstIndex(of: target) {
                L.backings = [[target]]
                L.drawGroups.append(DrawGroup(group: target, colorIndex: i, emphasized: true))
            }
            for g in groups where L.fits[g] != nil {
                if let name = groupName[g], let a = groupAreas[g] {
                    let q = fit.pt(a.midX, a.midY)
                    L.labels.append((name, CGPoint(x: q.x, y: q.y + L.labelSize * 1.2)))
                }
            }
            L.labelSize *= 1.3
            for (i, p) in photos.enumerated() {
                guard let c = p.coordinate else { continue }
                let q = fit.pt(CGFloat(c.longitude), CGFloat(c.latitude))
                if L.clip.insetBy(dx: -20, dy: -20).contains(q) {
                    L.points.append((p.id, i + 1, q))
                }
            }
        } else {
            // ── 全体：隣り合う県はつなげ、離れた県は別々にずらして並べる
            var keyCache: [Int: Set<Int64>] = [:]
            func pointKey(_ p: CGPoint) -> Int64 {
                Int64((p.x * 1000).rounded()) * 100_000 + Int64((p.y * 1000).rounded())
            }
            func keys(_ g: Int) -> Set<Int64> {
                if let k = keyCache[g] { return k }
                var set = Set<Int64>()
                for line in lines where line.group == g {
                    for p in line.points { set.insert(pointKey(p)) }
                }
                keyCache[g] = set
                return set
            }
            func adjacent(_ a: Int, _ b: Int) -> Bool {
                let ka = keys(a)
                for line in lines where line.group == b {
                    for p in line.points where ka.contains(pointKey(p)) { return true }
                }
                return false
            }
            var clusters: [[Int]] = []
            for g in groups {
                var merged: [Int] = [g]
                var rest: [[Int]] = []
                for c in clusters {
                    if c.contains(where: { adjacent($0, g) }) { merged += c } else { rest.append(c) }
                }
                rest.append(merged)
                clusters = rest
            }
            clusters.sort { a, b in
                (a.compactMap { groups.firstIndex(of: $0) }.min() ?? 0) < (b.compactMap { groups.firstIndex(of: $0) }.min() ?? 0)
            }

            let boxRects = boxes(count: clusters.count, size: size)
            for (i, cluster) in clusters.enumerated() {
                var area: CGRect?
                for g in cluster {
                    if let a = groupAreas[g] { area = area?.union(a) ?? a }
                }
                guard let a = area else { continue }
                let fit = Fit.make(area: a, into: boxRects[min(i, boxRects.count - 1)].insetBy(dx: 12, dy: 12))
                for g in cluster { L.fits[g] = fit }
            }
            L.backings = clusters
            for (i, g) in groups.enumerated() {
                L.drawGroups.append(DrawGroup(group: g, colorIndex: i, emphasized: false))
                if let fit = L.fits[g], let name = groupName[g], let a = groupAreas[g] {
                    let q = fit.pt(a.midX, a.midY)
                    L.labels.append((name, CGPoint(x: q.x, y: q.y + L.labelSize * 0.9)))
                }
            }
            for (i, p) in photos.enumerated() {
                guard let g = photoGroup[p.id], let fit = L.fits[g], let c = p.coordinate else { continue }
                L.points.append((p.id, i + 1, fit.pt(CGFloat(c.longitude), CGFloat(c.latitude))))
            }
        }

        // 選んだ写真の点と「ココ!」の場所
        if let sel = selectedID, let item = L.points.first(where: { $0.id == sel }),
           let img = HandwritingAssets.koko, img.size.height > 0 {
            let q = item.point
            L.selectedPoint = q
            let h = min(size.width, size.height) * 0.1
            let w = h * img.size.width / img.size.height
            var lx = q.x - w - h * 0.9
            var ly = q.y - h * 2.4
            if lx < 8 { lx = q.x + h * 0.9 }
            lx = min(max(8, lx), size.width - w - 8)
            ly = min(max(8, ly), size.height - h - 8)
            L.kokoRect = CGRect(x: lx, y: ly, width: w, height: h)
        }
        return L
    }

    // MARK: 描く

    static func draw(_ ctx: inout GraphicsContext, layout L: Layout, lines: [MapLine], font: HandFont) {
        guard !L.fits.isEmpty else { return }

        func ring(_ line: MapLine, _ fit: Fit) -> Path {
            var path = Path()
            for (i, p) in line.points.enumerated() {
                let q = fit.pt(p.x, p.y)
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            path.closeSubpath()
            return path
        }
        func groupPath(_ g: Int) -> Path {
            var path = Path()
            guard let fit = L.fits[g] else { return path }
            let near = fit.area.insetBy(dx: -fit.area.width * 0.3, dy: -fit.area.height * 0.3)
            for line in lines where line.group == g {
                let box = CGRect(x: line.minX, y: line.minY, width: line.maxX - line.minX, height: line.maxY - line.minY)
                if near.intersects(box) { path.addPath(ring(line, fit)) }
            }
            return path
        }

        // まわりの県（拡大のとき）
        for d in L.drawGroups where d.colorIndex == nil {
            let path = groupPath(d.group)
            ctx.fill(path, with: .color(.white.opacity(0.45)), style: FillStyle(eoFill: true))
            ctx.stroke(path, with: .color(NoteInk.ink2.opacity(0.6)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        }

        // 影を付けた白い紙
        for backing in L.backings {
            var outline = Path()
            for g in backing { outline.addPath(groupPath(g)) }
            var shadowCtx = ctx
            shadowCtx.addFilter(.shadow(color: .black.opacity(0.25), radius: 4, x: 1, y: 3))
            shadowCtx.fill(outline, with: .color(.white.opacity(0.9)), style: FillStyle(eoFill: true))
        }

        // 行った県（色を付ける）
        for d in L.drawGroups {
            guard let ci = d.colorIndex, let fit = L.fits[d.group] else { continue }
            let path = groupPath(d.group)
            ctx.fill(path, with: .color(NoteInk.fills[ci % NoteInk.fills.count]), style: FillStyle(eoFill: true))
            ctx.stroke(path, with: .color(NoteInk.ink),
                       style: StrokeStyle(lineWidth: d.emphasized ? 2.6 : 1.8, lineJoin: .round))

            // 県の中の湖
            for line in lines where line.isLake {
                let c = CLLocationCoordinate2D(latitude: Double((line.minY + line.maxY) / 2),
                                               longitude: Double((line.minX + line.maxX) / 2))
                guard fit.area.contains(CGPoint(x: c.longitude, y: c.latitude)),
                      MapData.prefectureGroup(at: c, lines: lines) == d.group else { continue }
                let lake = ring(line, fit)
                ctx.fill(lake, with: .color(Color(red: 0.86, green: 0.93, blue: 0.98)))
                ctx.stroke(lake, with: .color(NoteInk.ink), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
        }

        // 県の名前（手書き風）
        for label in L.labels {
            ctx.draw(Text(label.text)
                        .font(FontStore.shared.font(font, size: L.labelSize))
                        .foregroundColor(NoteInk.ink),
                     at: label.point)
        }

        let r = L.dotRadius

        // 道のり（赤い点線と矢印）
        if L.points.count >= 2 {
            for k in 1..<L.points.count {
                let a = L.points[k - 1].point, b = L.points[k].point
                let dx = b.x - a.x, dy = b.y - a.y
                let len = sqrt(dx * dx + dy * dy)
                guard len > r * 2.6 else { continue }
                let ux = dx / len, uy = dy / len
                let start = CGPoint(x: a.x + ux * r * 1.4, y: a.y + uy * r * 1.4)
                let end = CGPoint(x: b.x - ux * r * 1.6, y: b.y - uy * r * 1.6)
                let bow = min(len * 0.18, 60)
                let control = CGPoint(x: (start.x + end.x) / 2 - uy * bow, y: (start.y + end.y) / 2 + ux * bow)
                var path = Path()
                path.move(to: start)
                path.addQuadCurve(to: end, control: control)
                ctx.stroke(path, with: .color(NoteInk.red),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [6, 6]))

                let ex = end.x - control.x, ey = end.y - control.y
                let el = max(sqrt(ex * ex + ey * ey), 0.001)
                let bx = -ex / el, by = -ey / el
                let head: CGFloat = 9
                func rotated(_ t: CGFloat) -> CGPoint {
                    CGPoint(x: end.x + (bx * cos(t) - by * sin(t)) * head,
                            y: end.y + (bx * sin(t) + by * cos(t)) * head)
                }
                var arrow = Path()
                arrow.move(to: rotated(.pi / 5))
                arrow.addLine(to: end)
                arrow.addLine(to: rotated(-.pi / 5))
                ctx.stroke(arrow, with: .color(NoteInk.red),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
        }

        // 番号の点（選んだ写真の点は最後に大きく）
        let ordered = L.points.filter { $0.id != L.selectedID } + L.points.filter { $0.id == L.selectedID }
        for item in ordered {
            let q = item.point
            let isSelected = item.id == L.selectedID
            let rr = isSelected ? r * 1.3 : r
            if isSelected {
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - rr - 3, y: q.y - rr - 3, width: (rr + 3) * 2, height: (rr + 3) * 2)),
                         with: .color(.white))
            }
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - rr, y: q.y - rr, width: rr * 2, height: rr * 2)),
                     with: .color(NoteInk.red))
            ctx.draw(Text("\(item.number)")
                        .font(.system(size: rr * 1.05, weight: .bold, design: .rounded))
                        .foregroundColor(.white),
                     at: q)
        }
    }
}

// 動く「ココ!」（撮影地に向かってぴょこぴょこ動き、点のまわりに波紋が広がる）
struct KokoMark: View {
    let rect: CGRect
    let dot: CGPoint
    let radius: CGFloat
    let size: CGSize

    @State private var bob = false
    @State private var pulse = false
    @State private var shown = false

    var body: some View {
        let dx = dot.x - rect.midX, dy = dot.y - rect.midY
        let len = max(sqrt(dx * dx + dy * dy), 1)
        let ux = dx / len, uy = dy / len
        let amp = rect.height * 0.14

        ZStack(alignment: .topLeading) {
            // 撮影地の波紋
            Circle()
                .stroke(NoteInk.red, lineWidth: 3)
                .frame(width: radius * 2.4, height: radius * 2.4)
                .scaleEffect(pulse ? 2.4 : 1)
                .opacity(pulse ? 0 : 0.9)
                .position(dot)

            // 手書きの「ココ!」と矢印
            ZStack(alignment: .topLeading) {
                if let arrow = HereArrow.path(from: rect, to: dot, dotRadius: radius * 0.6, width: rect.height * 0.09) {
                    Path(arrow)
                        .stroke(NoteInk.red, style: StrokeStyle(lineWidth: rect.height * 0.09, lineCap: .round, lineJoin: .round))
                }
                if let img = HandwritingAssets.koko {
                    Image(uiImage: img)
                        .renderingMode(.template)
                        .resizable()
                        .foregroundStyle(NoteInk.red)
                        .frame(width: rect.width, height: rect.height)
                        .rotationEffect(.degrees(bob ? 4 : -4))
                        .position(x: rect.midX, y: rect.midY)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .offset(x: bob ? ux * amp : -ux * amp * 0.3, y: bob ? uy * amp : -uy * amp * 0.3)
            .opacity(shown ? 1 : 0)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.3)) { shown = true }
            withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) { bob = true }
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

// MARK: - 写真（2列〜4列で、1列おきに少し下げて並べる）

struct PhotoGrid: View {
    let trip: Trip
    let photos: [TripPhoto]
    let size: CGSize
    let pinned: Bool
    let onTap: ((TripPhoto) -> Void)?

    var body: some View {
        let n = photos.count
        let cols = n <= 4 ? 2 : (n <= 9 ? 3 : 4)
        let rows = max(1, (n + cols - 1) / cols)
        let cellW = size.width / CGFloat(cols)
        let byHeight = size.height / (CGFloat(rows - 1) * 1.08 + 1 + 0.45)
        let card = max(40, min(cellW * 0.88, byHeight))
        let rowStep = card * 1.08
        let stagger = card * 0.45

        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                let col = index % cols
                let row = index / cols
                PhotoTile(image: TripStore.shared.thumbnail(trip.id, photo), number: index + 1, side: card, pinned: pinned)
                    .contentShape(Rectangle())
                    .onTapGesture { onTap?(photo) }
                    .position(x: cellW * (CGFloat(col) + 0.5),
                              y: card / 2 + CGFloat(row) * rowStep + (col % 2 == 1 ? stagger : 0))
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

// 写真1枚（そのまま表示。四角く切り取って番号を付ける）
struct PhotoTile: View {
    let image: UIImage?
    let number: Int
    let side: CGFloat
    var pinned = false

    var body: some View {
        let badge = max(18, side * 0.13)
        ZStack(alignment: .topLeading) {
            ZStack {
                Color(white: 0.78)
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: side, height: side)
            .clipped()
            .border(Color.white, width: max(2, side * 0.025))
            .shadow(color: .black.opacity(0.25), radius: 3, y: 2)

            Text("\(number)")
                .font(.system(size: badge * 0.6, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: badge, height: badge)
                .background(Circle().fill(NoteInk.red))
                .offset(x: -badge * 0.3, y: -badge * 0.3)

            if pinned {
                PushPin(size: max(14, side * 0.1))
                    .offset(x: side / 2 - max(14, side * 0.1) / 2, y: -max(14, side * 0.1) * 0.35)
            }
        }
        .frame(width: side, height: side)
    }
}

// タッチした写真を大きく見せる
struct EnlargedPhoto: View {
    let image: UIImage?
    let number: Int
    let total: Int
    let photo: TripPhoto
    let font: HandFont
    let onPrev: (() -> Void)?
    let onNext: (() -> Void)?
    let onRemove: () -> Void
    let onClose: () -> Void

    @State private var dragX: CGFloat = 0

    var caption: String {
        var parts: [String] = []
        if let d = photo.taken {
            let f = DateFormatter()
            f.locale = Locale(identifier: "ja_JP")
            f.dateFormat = "M月d日 H:mm"
            parts.append(f.string(from: d))
        }
        let place = [photo.prefecture, photo.city].filter { !$0.isEmpty }.joined(separator: " ")
        if !place.isEmpty { parts.append(place) }
        return parts.joined(separator: "　")
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }

            VStack(alignment: .leading, spacing: 12) {
                // 左右にスワイプで前後の写真へ
                ZStack {
                    Color(white: 0.9)
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .offset(x: dragX)
                    }
                }
                .frame(maxHeight: .infinity)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 15)
                        .onChanged { v in
                            let x = v.translation.width
                            // 端の写真では動きを小さくする
                            dragX = (x < 0 && onNext == nil) || (x > 0 && onPrev == nil) ? x * 0.25 : x
                        }
                        .onEnded { v in
                            let x = v.translation.width
                            if x < -60, let onNext {
                                onNext()
                            } else if x > 60, let onPrev {
                                onPrev()
                            }
                            withAnimation(.easeOut(duration: 0.2)) { dragX = 0 }
                        }
                )

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(number)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(NoteInk.red))
                    Text(caption)
                        .font(FontStore.shared.font(font, size: 22))
                        .foregroundStyle(NoteInk.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Spacer()
                }

                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Label("ノートから外す", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button {
                        onPrev?()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)
                    .disabled(onPrev == nil)
                    Text("\(number) / \(total)")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(NoteInk.ink2)
                    Button {
                        onNext?()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)
                    .disabled(onNext == nil)
                    Spacer()
                    Button {
                        onClose()
                    } label: {
                        Text("閉じる").frame(minWidth: 80)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
            .padding(18)
            .background(Color.white)
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            .padding(24)
        }
    }
}

// MARK: - 手書きメモ（PencilKit）

struct DrawingCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var isActive: Bool
    var tool: PKTool
    var undoTick: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.backgroundColor = .clear
        view.isOpaque = false
        view.drawingPolicy = .anyInput           // 指でもペンでも書ける
        view.overrideUserInterfaceStyle = .light // 黒いペンが白に変わらないように
        view.isScrollEnabled = false
        view.drawing = drawing
        view.tool = tool
        view.delegate = context.coordinator
        context.coordinator.lastUndoTick = undoTick
        return view
    }

    func updateUIView(_ view: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        view.isUserInteractionEnabled = isActive
        view.tool = tool
        if view.drawing != drawing {
            view.drawing = drawing
        }
        if undoTick != context.coordinator.lastUndoTick {
            context.coordinator.lastUndoTick = undoTick
            view.undoManager?.undo()
        }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: DrawingCanvas
        var lastUndoTick = 0

        init(_ parent: DrawingCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if parent.drawing != canvasView.drawing {
                parent.drawing = canvasView.drawing
            }
        }
    }
}
