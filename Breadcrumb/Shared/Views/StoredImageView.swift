import SwiftUI

struct StoredImageView: View {
    @EnvironmentObject private var appModel: AppModel

    let relativePath: String
    var cornerRadius: CGFloat = 18

    var body: some View {
        Group {
            if let image = appModel.image(for: relativePath) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [.gray.opacity(0.3), .gray.opacity(0.15)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
