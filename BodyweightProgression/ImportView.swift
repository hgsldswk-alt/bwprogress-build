import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject private var store: AppStoreModel
    @Environment(\.dismiss) private var dismiss
    @State private var preview: TrainingSheet?
    @State private var selectingFile = false
    @State private var importing = false
    @State private var status: String?
    var imported: () -> Void

    private var duplicate: TrainingSheet? {
        guard let preview else { return nil }
        return store.state.sheets.first { SheetCode.matches($0, preview) }
    }

    private var confirmation: String {
        if duplicate != nil { return L.t("import.reuse") }
        return L.t(store.pro ? "import.add" : "import.replace")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                PageHeader(title: L.t("import.title"), subtitle: L.t("import.subtitle")) {
                    Action(title: L.t("close"), id: "import.close") { dismiss() }
                }
                if Launch.testing, let fixture = ProcessInfo.processInfo.environment["BW_IMPORT_CODE"] {
                    Action(title: L.t("import.paste"), id: "import.paste", style: .outline) {
                        decode(fixture)
                    }
                } else {
                    HStack {
                        Text(L.t("import.paste")).font(.subheadline.weight(.semibold))
                        Spacer()
                        PasteButton(payloadType: String.self) { items in
                            if let code = items.first { decode(code) }
                        }
                        .buttonBorderShape(.roundedRectangle(radius: 10))
                        .frame(minHeight: 44)
                        .accessibilityLabel(L.t("import.paste"))
                        .accessibilityIdentifier("import.paste")
                    }
                }
                Action(title: L.t("import.file"), id: "import.file", style: .outline) { selectingFile = true }
                    .disabled(importing)
                if let status { Text(L.t(status)).foregroundStyle(Palette.muted).accessibilityIdentifier("import.status") }
                if let preview {
                    templatePreview(preview)
                    if duplicate != nil || !store.pro {
                        Text(L.t(duplicate != nil ? "import.duplicate" : "import.kept"))
                            .font(.caption).foregroundStyle(Palette.muted)
                    }
                    Action(title: confirmation, id: "import.confirm", style: .prominent) {
                        store.activate(duplicate ?? preview)
                        imported()
                    }
                }
            }
            .page()
        }
        .fileImporter(isPresented: $selectingFile, allowedContentTypes: [.data, .plainText]) { result in
            switch result {
            case .success(let url):
                importing = true
                Task {
                    defer { importing = false }
                    do {
                        let code = try await Task.detached(priority: .userInitiated) {
                            let scoped = url.startAccessingSecurityScopedResource()
                            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                            let handle = try FileHandle(forReadingFrom: url)
                            defer { try? handle.close() }
                            let data = try handle.read(upToCount: SheetCode.limit + 1) ?? Data()
                            guard data.count <= SheetCode.limit else { throw TransferError.tooLarge }
                            guard let code = String(data: data, encoding: .utf8) else { throw TransferError.malformed }
                            return code
                        }.value
                        decode(code)
                    } catch TransferError.tooLarge {
                        preview = nil
                        status = "import.tooLarge"
                    } catch {
                        preview = nil
                        status = "import.bad"
                    }
                }
            case .failure:
                status = "import.bad"
            }
        }
    }

    private func templatePreview(_ sheet: TrainingSheet) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L.t("import.preview")).font(.caption.bold()).foregroundStyle(Palette.action)
            Text(sheet.title).font(.headline).accessibilityIdentifier("import.preview.name")
            ForEach(sheet.groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title).font(.subheadline.weight(.semibold))
                    ForEach(group.moves) { move in
                        HStack {
                            Text(move.title)
                            Spacer()
                            Text(move.unit.spoken).foregroundStyle(Palette.muted)
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
    }

    private func decode(_ code: String) {
        preview = nil
        status = nil
        do {
            preview = try SheetCode.decode(code)
        } catch TransferError.tooLarge {
            status = "import.tooLarge"
        } catch TransferError.unsupported {
            status = "import.version"
        } catch {
            status = "import.bad"
        }
    }
}
