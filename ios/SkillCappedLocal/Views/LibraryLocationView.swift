import SwiftUI

/// Where the library comes from.
///
/// The first choice is any folder at all — the system picker, so iCloud Drive, an
/// external volume or another app's folder all work, read in place. Some builds
/// cannot open that picker: it needs an iCloud container entitlement in the
/// signing profile, and `FolderAccess` reports the refusal instead of letting the
/// app die. For those, the sheet keeps listing the library folders already in the
/// app's own Documents folder ("On My iPhone › SkillCapped Local") together with
/// the copy-in steps.
struct LibraryLocationView: View {
  @EnvironmentObject private var store: LibraryStore
  @Environment(\.dismiss) private var dismiss

  @State private var candidates: [URL] = []
  @State private var pickerRequest: FolderPickerRequest?
  @State private var pickerNote: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Button {
            openPicker()
          } label: {
            Label("Choose a folder…", systemImage: "folder.badge.plus")
          }
          if let pickerNote {
            Text(pickerNote)
              .font(.caption)
              .foregroundStyle(Palette.warn)
              .fixedSize(horizontal: false, vertical: true)
          }
        } header: {
          Text("Any folder")
        } footer: {
          Text("Wherever the downloader wrote its folder — iCloud Drive, On My iPad, another app's folder. The app reads it in place and remembers it, so the next launch opens straight into it.")
        }

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
          Text("If the picker will not open")
        } footer: {
          Text("This is the fallback for a build signed without the iCloud entitlement: iOS then refuses to show the picker at all. Copying puts the folder where the app is always allowed to read it.")
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
    .fullScreenCover(item: $pickerRequest) { request in
      FolderPickerSheet(controller: request.controller) { url in
        pickerRequest = nil
        guard let url else { return }
        pickerNote = nil
        store.choose(url)
        dismiss()
      }
      .ignoresSafeArea()
    }
  }

  private func openPicker() {
    switch FolderAccess.picker() {
    case let .ready(controller):
      pickerNote = nil
      pickerRequest = FolderPickerRequest(controller: controller)
    case let .unavailable(reason):
      pickerNote = reason
    }
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
