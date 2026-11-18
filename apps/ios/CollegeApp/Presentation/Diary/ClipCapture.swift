import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// 「カメラで 2 秒撮る」「ライブラリから選ぶ」のボタン。選ばれた動画のファイル URL を返す（2 秒への切り出しは呼び出し側）
struct ClipSourceButtons: View {
    var cameraTitle = "カメラで2秒撮る"
    let onPicked: (URL) async -> Void

    @State private var showingCamera = false
    @State private var libraryItem: PhotosPickerItem?
    @State private var processing = false

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        VStack(spacing: 8) {
            if cameraAvailable {
                Button {
                    showingCamera = true
                } label: {
                    Label(cameraTitle, systemImage: "video.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            PhotosPicker(selection: $libraryItem, matching: .videos) {
                Label(processing ? "読み込み中..." : "ライブラリから選ぶ（先頭2秒を使います）", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .disabled(processing)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraClipPicker { url in
                showingCamera = false
                guard let url else { return }
                Task { await handle(url) }
            }
            .ignoresSafeArea()
        }
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                processing = true
                if let movie = try? await item.loadTransferable(type: PickedMovie.self) {
                    await handle(movie.url)
                }
                processing = false
                libraryItem = nil
            }
        }
    }

    private func handle(_ url: URL) async {
        processing = true
        await onPicked(url)
        processing = false
    }
}

/// UIImagePickerController のカメラ（動画・最大 2 秒）
private struct CameraClipPicker: UIViewControllerRepresentable {
    let onFinish: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoMaximumDuration = ClipProcessing.clipSeconds
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (URL?) -> Void

        init(onFinish: @escaping (URL?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.mediaURL] as? URL)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

/// フォトライブラリの動画を一時ファイルとして受け取る
private struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// クリップのサムネイル
struct ClipThumbnail: View {
    let url: URL
    var revision = 0
    var cornerRadius: CGFloat = 8

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.tertiarySystemFill)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: "\(url.path)#\(revision)") {
            image = await ThumbnailCache.shared.image(for: url)
        }
    }
}

/// 動画をループ再生し、共有（写真に保存など）できるシート
struct VideoPlayerSheet: View {
    let url: URL
    let title: String
    var extraActions: AnyView?

    @Environment(\.dismiss) private var dismiss
    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let player {
                    VideoPlayer(player: player)
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                ShareLink(item: url) {
                    Label("保存・共有", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(SecondaryButtonStyle())
                if let extraActions { extraActions }
            }
            .padding(16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .onAppear {
            let queue = AVQueuePlayer()
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            player = queue
            queue.play()
        }
        .onDisappear { player?.pause() }
    }
}

/// 自分の端末にある音源ファイル（MP3 など）を選ぶ。選んだファイルは一時領域にコピーして返す
/// （YouTube などからの音声抽出は行わない。AGENTS.md の決定事項）
struct MusicPickerButton: View {
    @Binding var music: URL?
    var required = false

    @State private var importing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "music.note")
                    .foregroundStyle(Theme.primary)
                Text(music?.lastPathComponent ?? (required ? "音源を選んでください（必須）" : "音源なし（クリップの音を使う）"))
                    .font(.system(size: 13))
                    .foregroundStyle(music == nil ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if music != nil, !required {
                    Button("外す") { music = nil }
                        .font(.system(size: 12))
                }
                Button("選ぶ") { importing = true }
                    .font(.system(size: 12, weight: .semibold))
            }
            Text("自分で用意した、使ってよい音源（MP3 など）だけを選んでください")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.mp3, .audio]) { result in
            guard case .success(let picked) = result else { return }
            let accessing = picked.startAccessingSecurityScopedResource()
            defer { if accessing { picked.stopAccessingSecurityScopedResource() } }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(picked.lastPathComponent)
            try? FileManager.default.removeItem(at: copy)
            if (try? FileManager.default.copyItem(at: picked, to: copy)) != nil {
                music = copy
            }
        }
    }
}
