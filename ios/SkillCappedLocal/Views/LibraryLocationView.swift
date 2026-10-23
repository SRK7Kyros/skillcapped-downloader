import SwiftUI
import UIKit

/// Where the library comes from.
///
/// The first choice is any folder at all — the system picker, so iCloud Drive, an
/// external volume or another app's folder all work, read in place. A folder-only
/// picker is refused by iOS 26 and later (`folder import is not supported, use
/// asCopy:false`, raised even when `asCopy` is already `NO`), so `FolderAccess`
/// asks for a folder *beside* `UTTypeItem` and walks the spellings until one is
/// accepted. The accepted list is shown in **Picker diagnostics**, and when none
/// is, the sheet falls back to the library folders already in the app's own
/// Documents ("On My iPhone › SkillCapped Local") with the copy-in steps.
struct LibraryLocationView: View {
  @EnvironmentObject private var store: LibraryStore
  @Environment(\.dismiss) private var dismiss

  @State private var candidates: [URL] = []
  @State private var attempts: [FolderAccess.Attempt] = []
  @State private var pickerNote: String?
  /// Held in `@State` so the picker's delegate outlives a body pass — UIKit holds
  /// delegates weakly.
  @State private var presenter = FolderPickerPresenter()

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
          Text("Wherever the downloader wrote its folder — iCloud Drive, On My iPad, another app's folder. The app reads it in place and remembers it, and moves the lessons already on the phone into the folder you pick, so the app keeps one library instead of two.")
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
          Text("Every folder in there holding Courses, Videos or Commentaries. The app reads it in place, and picking one moves anything it already downloaded into it.")
        }

        Section {
          step("1", "Open Files and find the folder the downloader wrote to.")
          step("2", "Touch and hold it, then tap Copy.")
          step("3", "Go to On My iPhone › SkillCapped Local and tap Paste.")
          step("4", "Come back here and tap Scan again.")
        } header: {
          Text("If the picker will not open")
        } footer: {
          Text("Some iOS versions refuse the folder picker outright. Copying puts the folder where the app is always allowed to read it.")
        }

        Section {
          DisclosureGroup("Picker diagnostics") {
            if attempts.isEmpty {
              Text("Checking…")
                .font(.footnote)
                .foregroundStyle(Palette.inkDim)
            } else {
              ForEach(attempts) { attempt in
                VStack(alignment: .leading, spacing: 2) {
                  HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: attempt.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                      .font(.caption)
                      .foregroundStyle(attempt.ok ? Palette.brand : Palette.warn)
                    Text(attempt.name)
                      .font(.footnote)
                      .foregroundStyle(Palette.ink)
                  }
                  if let detail = attempt.detail {
                    Text(detail)
                      .font(.caption2)
                      .foregroundStyle(Palette.inkFaint)
                      .fixedSize(horizontal: false, vertical: true)
                  }
                }
              }
            }

            Text("iOS \(UIDevice.current.systemVersion) · build \(Bundle.main.appVersion)")
              .font(.caption2)
              .foregroundStyle(Palette.inkFaint)
          }
        } footer: {
          Text("Which folder-picker spellings this build's iOS accepts. The folder button uses the first one marked ✓.")
        }

        Section {
          Button("Scan again") { reload() }
          if store.hasFolder {
            Button("Forget folder", role: .destructive) {
              store.forget()
              reload()
            }
            .disabled(store.moving != nil)
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

  private func openPicker() {
    switch FolderAccess.picker(startingAt: store.documentsURL) {
    case let .unavailable(reason):
      pickerNote = reason
      attempts = FolderAccess.survey()

    case let .ready(controller):
      pickerNote = nil
      presenter.present(controller) { result in
        switch result {
        case let .success(url):
          pickerNote = nil
          store.choose(url)
          dismiss()
        case let .failure(error):
          if case .cancelled = error { return }
          pickerNote = error.errorDescription
          attempts = FolderAccess.survey()
        }
      }
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
    if attempts.isEmpty {
      attempts = FolderAccess.survey()
    }
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
