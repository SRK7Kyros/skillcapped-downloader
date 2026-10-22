import SwiftUI

/// Where the library comes from.
///
/// Sideloaded builds cannot present the system folder picker: its initializer
/// requires the iCloud Documents entitlement, a free Apple ID cannot grant one,
/// and the app is killed on the spot (`Application initializing document picker
/// is missing the iCloud entitlement`). So the picker is gone — the app reads
/// what iOS already gives it, its own Documents folder, shown in Files as
/// "On My iPhone › SkillCapped Local", and lists every library folder in there.
struct LibraryLocationView: View {
  @EnvironmentObject private var store: LibraryStore
  @Environment(\.dismiss) private var dismiss

  @State private var candidates: [URL] = []

  var body: some View {
    NavigationStack {
      Form {
        Section {
          if candidates.isEmpty {
            Text("No library folder here yet.")
              .foregroundStyle(Palette.inkDim)
          } else {
            ForEach(candidates, id: \.self) { folder in
              row(folder)
            }
          }
        } header: {
          Text("On My iPhone › SkillCapped Local")
        } footer: {
          Text("Every folder in there holding Courses, Videos or Commentaries. The app reads it in place — nothing is copied.")
        }

        Section {
          step("1", "Open Files and find the folder the downloader wrote to.")
          step("2", "Touch and hold it, then tap Copy.")
          step("3", "Go to On My iPhone › SkillCapped Local and tap Paste.")
          step("4", "Come back here and tap Scan again.")
        } header: {
          Text("Add your library")
        } footer: {
          Text("iOS hides the system folder picker from sideloaded apps: it needs an iCloud entitlement a free Apple ID cannot give, and the app is killed the moment it opens one. This folder is the one place iOS lets the app read.")
        }

        Section {
          Button("Scan again") { reload() }
          if store.hasFolder {
            Button("Forget folder", role: .destructive) {
              store.forget()
              reload()
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background(Palette.bg)
      .navigationTitle("Library folder")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Done") { dismiss() }
        }
      }
      .onAppear(perform: reload)
    }
    .tint(Palette.brand)
  }

  private func row(_ folder: URL) -> some View {
    Button {
      store.choose(folder)
      dismiss()
    } label: {
      HStack(spacing: 12) {
        Image(systemName: "folder.fill")
          .font(.body)
          .foregroundStyle(Palette.brand)
          .frame(width: 22)
        VStack(alignment: .leading, spacing: 2) {
          Text(name(folder))
            .foregroundStyle(Palette.ink)
          Text(path(folder))
            .font(.caption)
            .foregroundStyle(Palette.inkFaint)
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer(minLength: 8)
        if store.isCurrent(folder) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(Palette.brand)
        }
      }
    }
    .buttonStyle(.plain)
    .accessibilityHint("Read this folder")
  }

  private func step(_ number: String, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(number)
        .font(.caption.weight(.bold))
        .foregroundStyle(Palette.brand)
        .frame(width: 12, alignment: .trailing)
      Text(text)
        .font(.footnote)
        .foregroundStyle(Palette.ink)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func reload() {
    store.refreshCandidates()
    candidates = store.candidates
  }

  private func name(_ folder: URL) -> String {
    isDocuments(folder) ? "SkillCapped Local" : folder.lastPathComponent
  }

  private func path(_ folder: URL) -> String {
    let root = store.documentsURL.standardizedFileURL.path
    let full = folder.standardizedFileURL.path
    guard full != root else { return "On My iPhone › SkillCapped Local" }
    guard full.hasPrefix(root + "/") else { return full }
    return String(full.dropFirst(root.count + 1))
  }

  private func isDocuments(_ folder: URL) -> Bool {
    folder.standardizedFileURL.path == store.documentsURL.standardizedFileURL.path
  }
}
