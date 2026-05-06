import SwiftUI

struct ExtractedMetadata: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var author: String
    var year: String
    var description: String
    var identifier: String
}

struct MetadataReviewView: View {
    @Environment(TaskStore.self) var store
    let onConfirm: () -> Void
    let onCancel: () -> Void

    @State private var draft: ExtractedMetadata?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().padding(.horizontal, 16)
            ScrollView {
                VStack(spacing: 18) {
                    if let draft {
                        filenamePreview(draft)
                        fieldsSection(draft)
                        Divider()
                        summarySection(draft)
                    }
                }
                .padding(20)
            }
            Divider().padding(.horizontal, 16)
            actionButtons
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
        }
        .frame(width: 400, height: 540)
        .onAppear {
            draft = store.pendingMetadata
        }
    }

    var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 1) {
                Text("Review Metadata")
                    .font(.system(size: 15, weight: .semibold))
                Text("LM Studio extracted this from the archive page")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    func filenamePreview(_ meta: ExtractedMetadata) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Filename Preview")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
            }
            Text(suggestedFilename(meta))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                )
        }
    }

    func fieldsSection(_ meta: ExtractedMetadata) -> some View {
        VStack(spacing: 12) {
            MetadataField(icon: "textformat", label: "Title", text: metaBinding(\.title), placeholder: "Book title")
            MetadataField(icon: "person", label: "Author", text: metaBinding(\.author), placeholder: "Author name")
            MetadataField(icon: "calendar", label: "Year", text: metaBinding(\.year), placeholder: "Publication year")
        }
    }

    func summarySection(_ meta: ExtractedMetadata) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "text.quote")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Text("Description / Summary")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if let draft {
                    Text("\(draft.description.count)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            TextEditor(text: metaBinding(\.description))
                .font(.system(size: 12))
                .frame(minHeight: 70, maxHeight: 100)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
        }
    }

    var actionButtons: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Text("Cancel")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Button(action: confirm) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 12))
                    Text("Download & Upload")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(AppTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    func confirm() {
        if let draft {
            store.pendingMetadata = draft
        }
        onConfirm()
    }

    func metaBinding(_ keyPath: WritableKeyPath<ExtractedMetadata, String>) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? "" },
            set: { newValue in
                draft?[keyPath: keyPath] = newValue
            }
        )
    }

    func suggestedFilename(_ meta: ExtractedMetadata) -> String {
        var parts: [String] = []
        if !meta.author.isEmpty { parts.append(meta.author) }
        if !meta.title.isEmpty { parts.append(meta.title) }
        if !meta.year.isEmpty { parts.append(meta.year) }
        let name = parts.isEmpty ? meta.identifier : parts.joined(separator: " - ")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,_-")
        let safe = name.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let trimmed = String(safe.prefix(200))
        return trimmed + ".pdf"
    }
}

struct MetadataField: View {
    let icon: String
    let label: String
    @Binding var text: String
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            TextField(placeholder, text: $text)
                .font(.system(size: 12))
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(AppTheme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
        }
    }
}
