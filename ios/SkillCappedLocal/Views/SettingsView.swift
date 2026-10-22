import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var store: LibraryStore
  @Environment(\.dismiss) private var dismiss

  @State private var picking = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          LabeledContent("Name", value: store.rootName ?? "—")
          if let path = store.scan?.rootPath {
            Text(path)
              .font(.caption2)
              .foregroundStyle(Palette.inkFaint)
              .textSelection(.enabled)
          }
          Button("Choose folder") { picking = true }
          Button("Forget folder", role: .destructive) { store.forget() }
            .disabled(!store.hasFolder)
        } header: {
          Text("Folder")
        } footer: {
          Text("Library folders live in Files › On My iPhone › SkillCapped Local.")
        }

        Section("Library") {
          if let scan = store.scan {
            LabeledContent("Lessons", value: "\(scan.lessonCount)")
            LabeledContent("Courses", value: "\(scan.courses.count)")
            LabeledContent("Size", value: Format.bytes(scan.totalBytes))
            LabeledContent("Catalogue", value: scan.catalogDate.map { Format.date($0) ?? "unknown" } ?? "not found")
            Button("Rescan") { store.rescan() }
          } else {
            Text("No folder yet.")
              .foregroundStyle(Palette.inkDim)
          }
        }

        Section("About") {
          LabeledContent("Version", value: Bundle.main.appVersion)
          Text("Reads the chosen folder in place. No uploading, no downloading, no network calls.")
            .font(.caption)
            .foregroundStyle(Palette.inkDim)
        }
      }
      .scrollContentBackground(.hidden)
      .background(Palette.bg)
      .navigationTitle("Library")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .sheet(isPresented: $picking) {
        LibraryLocationView()
      }
    }
    .tint(Palette.brand)
  }
}
