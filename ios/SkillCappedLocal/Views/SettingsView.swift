import SwiftUI

struct SettingsView: View {
  @EnvironmentObject private var store: LibraryStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var prefs: PreferencesStore
  @Environment(\.dismiss) private var dismiss

  @State private var picking = false

  var body: some View {
    NavigationStack {
      Form {
        Section {
          LabeledContent("Name", value: store.rootName ?? "—")
          LabeledContent("Source", value: store.isCloudRoot ? "iCloud Drive" : "On this device")
          if let path = store.scan?.rootPath {
            Text(path)
              .font(.caption2)
              .foregroundStyle(Palette.inkFaint)
              .textSelection(.enabled)
          }
          if let moving = store.moving {
            LabeledContent("Moving", value: moving.label)
          } else if let message = store.message {
            Text(message)
              .font(.caption)
              .foregroundStyle(Palette.inkDim)
              .fixedSize(horizontal: false, vertical: true)
          }
          Button("Choose folder") { picking = true }
            .disabled(store.moving != nil)
          Button("Forget folder", role: .destructive) { store.forget() }
            .disabled(!store.hasFolder || store.moving != nil)
        } header: {
          Text("Folder")
        } footer: {
          Text("Any folder works — iCloud Drive, On My iPad, another app's folder — as does one inside Files › On My iPhone › SkillCapped Local. Choosing a new folder moves the lessons already on the phone into it.")
        }

        Section {
          NavigationLink {
            QualityOrderView()
          } label: {
            LabeledContent("Quality", value: prefs.qualityPriority.first ?? "—")
          }
          LabeledContent("In the queue", value: "\(downloads.activeCount)")
          LabeledContent("On disk", value: Format.bytes(downloads.readyBytes))
          Text(downloads.root.path)
            .font(.caption2)
            .foregroundStyle(Palette.inkFaint)
            .textSelection(.enabled)
        } header: {
          Text("Downloads")
        } footer: {
          Text("Discover fetches the site's own catalogue and pulls a lesson straight onto the phone; it lands in the library folder above.")
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
          Text("Reads the chosen folder in place. A lesson held in iCloud Drive is fetched only when you play it; nothing is uploaded and there are no accounts.")
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
