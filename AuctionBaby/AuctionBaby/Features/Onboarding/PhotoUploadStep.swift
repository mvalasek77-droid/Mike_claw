import SwiftUI
import PhotosUI
import UIKit

/// Multi-photo upload for onboarding and the profile editor. Up to 6 photos,
/// primary first, drag-reorder, ≥600×600 quality gate, JPEG-compressed for
/// archive size. Falls back cleanly to the gradient monogram when the user
/// declines to upload — the app has always worked without photos and this
/// step keeps the same "photo optional" contract.
struct PhotoUploadStep: View {
    /// Primary photo shown on cards. First upload in the picker lands here.
    @Binding var primary: Data?
    /// Extra photos, up to 5. Order matters — index 0 shows second.
    @Binding var gallery: [Data]

    @State private var selection: [PhotosPickerItem] = []
    @State private var rejectReason: String?
    @State private var isLoading = false

    /// Apple-friendly minimum: 600×600 with a non-trivial file size (rules
    /// out 1×1 sentinels and near-empty JPEGs).
    static let minSidePx: CGFloat = 600
    static let minBytes = 30 * 1024
    static let maxTotal = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            heading

            if primary == nil && gallery.isEmpty {
                emptyPicker
            } else {
                grid
                addMoreButton
            }

            if let rejectReason {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.warning)
                    Text(rejectReason)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warning.opacity(0.10)))
            }

            Text("Photos stay on your phone until you post them. You can skip this step — a monogram portrait stands in until you upload.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.inkFaint)
        }
        .onChange(of: selection) { _, newValue in
            guard !newValue.isEmpty else { return }
            Task { await ingest(newValue) }
        }
        .overlay {
            if isLoading {
                Color.black.opacity(0.25).ignoresSafeArea()
                ProgressView().tint(Theme.gold).scaleEffect(1.3)
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add your photos")
                .font(.system(size: 20, weight: .heavy, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("Up to \(Self.maxTotal). The first one shows on your card — tap any photo to make it primary. Drag to reorder.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyPicker: some View {
        PhotosPicker(selection: $selection,
                     maxSelectionCount: Self.maxTotal,
                     matching: .images) {
            VStack(spacing: 12) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 42))
                    .foregroundStyle(Theme.gold)
                Text("Choose photos")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.ink)
                Text("From your photo library")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 46)
            .background(
                RoundedRectangle(cornerRadius: Theme.cornerL)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
                    .foregroundStyle(Theme.gold.opacity(0.5))
            )
        }
        .buttonStyle(.plain)
    }

    private var addMoreButton: some View {
        let remaining = Self.maxTotal - allPhotos.count
        return Group {
            if remaining > 0 {
                PhotosPicker(selection: $selection,
                             maxSelectionCount: remaining,
                             matching: .images) {
                    Label("Add more (\(remaining) left)", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Capsule().stroke(Theme.gold, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var allPhotos: [Data] { (primary.map { [$0] } ?? []) + gallery }

    private var grid: some View {
        LazyVGrid(columns: [.init(.flexible(), spacing: 10), .init(.flexible(), spacing: 10),
                            .init(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Array(allPhotos.enumerated()), id: \.offset) { idx, data in
                photoTile(index: idx, data: data)
            }
        }
    }

    private func photoTile(index: Int, data: Data) -> some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable().scaledToFill()
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerM))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.cornerM)
                            .strokeBorder(index == 0 ? Theme.gold : Theme.hairline,
                                          lineWidth: index == 0 ? 2 : 0.8)
                    )
            }
            if index == 0 {
                Chip(text: "Primary", systemImage: "star.fill", color: Theme.gold, filled: true)
                    .padding(6)
            }
            HStack(spacing: 6) {
                if index != 0 {
                    Button { makePrimary(index) } label: {
                        Image(systemName: "star").font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white).padding(6)
                            .background(Circle().fill(.black.opacity(0.55)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Make photo \(index + 1) primary")
                }
                Button { remove(at: index) } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white).padding(6)
                        .background(Circle().fill(.black.opacity(0.55)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove photo \(index + 1)")
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    // MARK: Actions

    private func makePrimary(_ index: Int) {
        guard index > 0, index - 1 < gallery.count else { return }
        let promoted = gallery.remove(at: index - 1)
        if let current = primary { gallery.insert(current, at: 0) }
        primary = promoted
        Haptics.selection()
    }

    private func remove(at index: Int) {
        if index == 0 {
            if !gallery.isEmpty { primary = gallery.removeFirst() } else { primary = nil }
        } else {
            let galleryIdx = index - 1
            guard galleryIdx < gallery.count else { return }
            gallery.remove(at: galleryIdx)
        }
        Haptics.warning()
    }

    private func ingest(_ items: [PhotosPickerItem]) async {
        await MainActor.run { isLoading = true; rejectReason = nil }
        var accepted: [Data] = []
        var lastReject: String?
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            if let normalized = normalize(data) {
                accepted.append(normalized)
            } else {
                let img = UIImage(data: data)
                let w = Int(img?.size.width ?? 0), h = Int(img?.size.height ?? 0)
                lastReject = "One photo was too small (need ≥\(Int(Self.minSidePx))×\(Int(Self.minSidePx)); got \(w)×\(h)) and was skipped."
            }
        }
        await MainActor.run {
            for photo in accepted {
                if primary == nil {
                    primary = photo
                } else if gallery.count < Self.maxTotal - 1 {
                    gallery.append(photo)
                }
            }
            rejectReason = lastReject
            selection = []
            isLoading = false
            if !accepted.isEmpty { Haptics.success() }
        }
    }

    /// Downsizes to ≤1600px on the long edge and re-encodes as JPEG(0.85) so
    /// the encrypted archive stays small and the picker's HEIC decode work
    /// only happens once.
    private func normalize(_ raw: Data) -> Data? {
        guard let image = UIImage(data: raw) else { return nil }
        guard image.size.width >= Self.minSidePx && image.size.height >= Self.minSidePx else {
            return nil
        }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 1600 ? 1600 / longest : 1.0
        let target = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let downsized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = downsized.jpegData(compressionQuality: 0.85),
              jpeg.count >= Self.minBytes else { return nil }
        return jpeg
    }
}
