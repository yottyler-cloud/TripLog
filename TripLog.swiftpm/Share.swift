import SwiftUI
import UniformTypeIdentifiers

// 保存・共有用のJPEG
struct JPEGFile: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .jpeg) { file in file.data }
    }
}

struct RenderResult: Identifiable {
    let id = UUID()
    let image: UIImage
    let jpeg: JPEGFile
}

// 書き出した画像の確認と保存
struct ResultView: View {
    let result: RenderResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(uiImage: result.image)
                    .resizable()
                    .scaledToFit()
                HStack(spacing: 16) {
                    Button {
                        dismiss()
                    } label: {
                        Label("ノートに戻る", systemImage: "chevron.backward")
                    }
                    .buttonStyle(.bordered)

                    ShareLink(item: result.jpeg,
                              preview: SharePreview("TripLog", image: Image(uiImage: result.image))) {
                        Label("保存・共有", systemImage: "square.and.arrow.up")
                            .bold()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .controlSize(.large)
            }
            .padding()
        }
        .preferredColorScheme(.dark)
    }
}
