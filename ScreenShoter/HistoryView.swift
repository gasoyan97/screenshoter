import SwiftUI
import AppKit

struct HistoryView: View {
    @State private var records: [UploadRecord] = UploadHistory.shared.list()
    @State private var previewImages: [UUID: NSImage] = [:]

    private let previewColumns = 4
    private let thumbnailSize: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("history.title")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if records.isEmpty {
                Text("history.empty")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let recent = Array(records.prefix(4))
                if !recent.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: min(recent.count, previewColumns)), spacing: 12) {
                        ForEach(recent) { record in
                            HistoryThumbnailRow(
                                record: record,
                                thumbnailSize: thumbnailSize,
                                previewImage: previewImages[record.id]
                            ) {
                                if let url = URL(string: record.fileURL) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .task {
                                await loadPreview(for: record)
                            }
                        }
                    }
                    .padding(.bottom, 8)
                }

                List(records) { record in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.fileName)
                                .lineLimit(1)
                            Text(record.date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !record.fileURL.isEmpty, let url = URL(string: record.fileURL) {
                            Button("history.open") {
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(.bordered)
                            Button("history.copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(record.fileURL, forType: .string)
                                if record.fileURL.contains("yadi.sk") {
                                    NSPasteboard.general.writeObjects([url as NSURL])
                                }
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Text("history.link_not_received")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .listRowBackground(Color.primary.opacity(0.02))
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .padding(24)
        .background(.windowBackground)
        .onAppear {
            records = UploadHistory.shared.list()
        }
    }

    private func loadPreview(for record: UploadRecord) async {
        let webdav = record.webdavURL ?? (record.fileURL.lowercased().contains("webdav") && record.fileURL.lowercased().contains("yandex") ? record.fileURL : nil)
        let isRecent = Date().timeIntervalSince(record.date) < 90
        let delays: [UInt64] = isRecent ? [0, 2_000_000_000, 5_000_000_000] : [0]
        for delayNs in delays {
            if delayNs > 0 { try? await Task.sleep(nanoseconds: delayNs) }
            if let img = await YandexPreviewLoader.shared.loadPreview(webdavURL: webdav) {
                await MainActor.run { previewImages[record.id] = img }
                return
            }
        }
    }
}

private struct HistoryThumbnailRow: View {
    let record: UploadRecord
    let thumbnailSize: CGFloat
    let previewImage: NSImage?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(spacing: 6) {
                Group {
                    if let img = previewImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                            .overlay {
                                ProgressView()
                            }
                    }
                }
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(record.fileName)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
