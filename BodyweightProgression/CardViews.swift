import CoreImage
import SwiftUI
import UIKit

private struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL

    init(data: Data, filename: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

private struct ActivitySheet: UIViewControllerRepresentable {
    let file: ShareFile

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in file.remove() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct ShareControl: View {
    var title: String
    var id: String
    var style: ActionStyle = .outline
    var prepare: () throws -> (Data, String)
    var didShare: () -> Void = {}
    @State private var file: ShareFile?
    @State private var presentedFile: ShareFile?
    @State private var preparing = false
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Action(title: title, id: id, style: style) {
                do {
                    let (data, name) = try prepare()
                    preparing = true
                    status = nil
                    Task {
                        defer { preparing = false }
                        do {
                            let request = try await Task.detached(priority: .userInitiated) {
                                try ShareFile(data: data, filename: name)
                            }.value
                            if Launch.testing {
                                await Task.detached { request.remove() }.value
                                status = "share.requested"
                            } else {
                                presentedFile = request
                                file = request
                            }
                            didShare()
                        } catch {
                            status = "share.failed"
                        }
                    }
                } catch TransferError.tooLarge {
                    status = "import.tooLarge"
                } catch {
                    status = "share.failed"
                }
            }
            .disabled(preparing)
            if let status {
                Text(L.t(status)).font(.caption).accessibilityIdentifier(status)
            }
        }
        .sheet(item: $file, onDismiss: {
            if let presentedFile { Task.detached { presentedFile.remove() } }
            presentedFile = nil
        }) { file in
            ActivitySheet(file: file).presentationDetents([.medium, .large])
        }
    }
}

struct CardView: View {
    @EnvironmentObject private var store: AppStoreModel
    @Environment(\.dismiss) private var dismiss
    @State private var includeDetails = false
    @State private var includeDate = false
    @State private var copied: String?
    @State private var qr: CGImage?
    @State private var previewLoaded = false
    var milestone: Milestone

    private var template: TrainingSheet {
        store.state.sheets.first { $0.id == milestone.sheetID } ?? store.sheet
    }
    private var storeID: String? { Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String }
    private var downloadURL: URL { DownloadQR.url(appID: storeID) }
    private var isPreviewQR: Bool { downloadURL == DownloadQR.url(appID: nil) }
    private var details: String? {
        guard includeDetails, store.pro else { return nil }
        if let movement = milestone.movement {
            if let best = milestone.bestValue { return "\(movement.title) · \(movement.unit.format(best))" }
            return movement.title
        }
        if let session = store.state.history.first(where: { $0.sheetID == milestone.sheetID }) {
            return session.entries.prefix(3).compactMap { entry in
                guard let last = entry.sets.last else { return nil }
                return "\(entry.movement.title) · \(entry.movement.unit.format(last.value))"
            }.joined(separator: "\n")
        }
        return nil
    }
    private var dateLine: String? {
        guard includeDate, store.pro else { return nil }
        return milestone.date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                PageHeader(title: L.t("card.title"), subtitle: L.t("card.privacy")) {
                    Action(title: L.t("close"), id: "card.close") { dismiss() }
                }
                preview
                if store.pro {
                    Toggle(L.t("card.details"), isOn: $includeDetails)
                        .accessibilityIdentifier("card.details")
                    Toggle(L.t("card.date"), isOn: $includeDate)
                        .accessibilityIdentifier("card.date")
                }
                ShareControl(title: L.t("card.share"), id: "card.share", style: .prominent, prepare: {
                    (try render(), L.t("card.filename") + ".png")
                }, didShare: markUsed)
                HStack(alignment: .top) {
                    Action(title: L.t("card.copyCode"), id: "card.copy", style: .outline) {
                        do {
                            UIPasteboard.general.string = try SheetCode.encode(template)
                            copied = "card.codeCopied"
                        } catch TransferError.tooLarge {
                            copied = "import.tooLarge"
                        } catch {
                            copied = "share.failed"
                        }
                    }
                    Action(title: L.t("card.copyTags"), id: "card.tags", style: .outline) {
                        UIPasteboard.general.string = L.t("card.hashtags")
                        copied = "card.tagsCopied"
                    }
                }
                ShareControl(title: L.t("card.shareFile"), id: "card.file", style: .outline) {
                    (.init(try SheetCode.encode(template).utf8), "template.bwprogress")
                }
                if let copied { Text(L.t(copied)).font(.caption).accessibilityIdentifier("card.copy.status") }
            }
            .page()
        }
        .task {
            guard !previewLoaded else { return }
            let url = downloadURL
            qr = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                guard let code = DownloadQR.image(for: url) else { return nil }
                return CIContext().createCGImage(code, from: code.extent)
            }.value
            previewLoaded = true
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(L.t("app.name")).font(.caption.bold())
            Text(milestone.headline)
                .font(.largeTitle.weight(.medium)).fontDesign(.serif)
                .accessibilityIdentifier("card.headline")
            if let details { Text(details).font(.caption.weight(.medium)) }
            if let dateLine { Text(dateLine).font(.caption) }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.t("card.hashtags")).font(.caption.bold())
                    if isPreviewQR { Text(L.t("card.previewQR")).font(.caption2) }
                }
                Spacer()
                if let qr {
                    Image(qr, scale: 1, label: Text(L.t("card.qr")))
                        .interpolation(.none).resizable()
                        .frame(width: 76, height: 76)
                        .accessibilityIdentifier("card.qr")
                }
            }
        }
        .padding(16).foregroundStyle(.white)
        .background(Palette.action, in: RoundedRectangle(cornerRadius: 18))
    }

    private func markUsed() {
        store.change { draft in
            if let index = draft.milestones.firstIndex(where: { $0.id == milestone.id }) {
                draft.milestones[index].used = true
            }
        }
    }

    private func render() throws -> Data {
        let rect = CGRect(x: 0, y: 0, width: 1080, height: 1350)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(bounds: rect, format: format)
        let code: CGImage?
        if let qr {
            code = qr
        } else if let image = DownloadQR.image(for: downloadURL) {
            code = CIContext().createCGImage(image, from: image.extent)
        } else {
            code = nil
        }
        guard let code else { throw TransferError.malformed }
        return renderer.pngData { context in
            UIColor(Palette.action).setFill()
            context.fill(rect)
            UIColor(Palette.tint).setStroke()
            let rule = UIBezierPath()
            rule.move(to: CGPoint(x: 72, y: 184))
            rule.addLine(to: CGPoint(x: 1008, y: 184))
            rule.lineWidth = 2
            rule.stroke()
            draw(L.t("app.name"), in: CGRect(x: 72, y: 85, width: 936, height: 85),
                 font: .systemFont(ofSize: 39, weight: .semibold))
            let serif = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .largeTitle).withDesign(.serif)
            let headline = serif.map { UIFont(descriptor: $0, size: 108) } ?? .systemFont(ofSize: 108)
            draw(milestone.headline, in: CGRect(x: 72, y: 286, width: 936, height: 470), font: headline)
            if let details {
                draw(details, in: CGRect(x: 72, y: 776, width: 936, height: 205),
                     font: .systemFont(ofSize: 34, weight: .medium))
            }
            if let dateLine {
                draw(dateLine, in: CGRect(x: 72, y: 985, width: 936, height: 50),
                     font: .systemFont(ofSize: 29))
            }
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: code).draw(in: CGRect(x: 780, y: 1042, width: 228, height: 228))
            draw(L.t("card.hashtags"), in: CGRect(x: 72, y: 1091, width: 675, height: 120),
                 font: .systemFont(ofSize: 36, weight: .semibold))
            if isPreviewQR {
                draw(L.t("card.previewQR"), in: CGRect(x: 72, y: 1217, width: 675, height: 52),
                     font: .systemFont(ofSize: 26))
            }
        }
    }

    private func draw(_ text: String, in rect: CGRect, font: UIFont) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                                attributes: [.font: font, .foregroundColor: UIColor.white,
                                             .paragraphStyle: paragraph], context: nil)
    }
}
