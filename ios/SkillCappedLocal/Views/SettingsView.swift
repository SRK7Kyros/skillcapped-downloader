import SwiftUI
import UIKit

struct SettingsView: View {
  @EnvironmentObject private var store: LibraryStore
  @EnvironmentObject private var downloads: DownloadManager
  @EnvironmentObject private var prefs: PreferencesStore
  @Environment(\.dismiss) private var dismiss

  /// How many journal lines the form lists. The whole file goes to the clipboard.
  private static let shownJournalLines = 16

  @State private var picking = false
  @State private var report: LiveActivityReport?
  @State private var journal: [String] = []
  @State private var copied = false
  @State private var copyToken = 0
  /// How many journal lines the last copy put on the clipboard, so the sheet can
  /// say what happened after the button's own two-second acknowledgement fades.
  @State private var copiedLines: Int?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          LabeledContent("Name", value: store.rootName ?? "—")
          LabeledContent("In Files", value: store.filesLocation)
          LabeledContent("Source", value: store.isCloudRoot ? "iCloud Drive" : "On this device")
          if let moving = store.moving {
            LabeledContent("Moving", value: moving.label)
          } else if let preparing = store.preparing {
            LabeledContent("Reading", value: preparing)
          } else if let message = store.message {
            Text(message)
              .font(.caption)
              .foregroundStyle(Palette.inkDim)
              .fixedSize(horizontal: false, vertical: true)
          }
          Button("Choose folder") { picking = true }
            .disabled(store.moving != nil || store.preparing != nil)
          if store.hasFolder {
            Button("Back to the app's folder") { store.forget() }
              .disabled(store.moving != nil)
          }
        } header: {
          Text("Folder")
        } footer: {
          Text("The app downloads into Files › \(FilesPlace.ownFolder) unless another folder is chosen — iCloud Drive, On My iPad, another app's folder. Choosing one moves the lessons already on the phone into it.")
        }

        Section {
          NavigationLink {
            QualityOrderView()
          } label: {
            LabeledContent("Quality", value: prefs.qualityPriority.first ?? "—")
          }
          LabeledContent("In the queue", value: "\(downloads.activeCount)")
          LabeledContent("On disk", value: Format.bytes(downloads.readyBytes))
        } header: {
          Text("Downloads")
        } footer: {
          Text("Discover fetches the site's own catalogue and pulls a lesson straight onto the phone; it lands in the folder above, in the same Courses, Videos and Commentaries layout the desktop build writes.")
        }

        Section {
          if journal.isEmpty {
            Text("Nothing recorded yet.")
              .font(.caption)
              .foregroundStyle(Palette.inkDim)
          } else {
            ForEach(Array(journal.enumerated()), id: \.offset) { _, entry in
              Text(entry)
                .font(.caption2.monospaced())
                .foregroundStyle(Palette.inkDim)
            }
          }
          HStack {
            Button {
              copyLogs()
            } label: {
              Label(copied ? "Copied" : "Copy logs", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .accessibilityIdentifier("settings.copyLogs")
            Spacer()
            Button("Refresh") { journal = BackgroundJournal.shared.lines(Self.shownJournalLines) }
            Button("Clear", role: .destructive) {
              BackgroundJournal.shared.clear()
              journal = []
            }
          }
          if let copiedLines {
            Text("Copied \(copiedLines) lines to the clipboard.")
              .font(.caption2)
              .foregroundStyle(Palette.inkDim)
              .accessibilityIdentifier("settings.copyLogs.confirmation")
          }
        } header: {
          Text("Background queue")
        } footer: {
          Text("What the queue did while the screen was off: the system hands over a part, the app writes one line here. A download that stops in the background stops on one of these lines.\n\nOnly the last \(Self.shownJournalLines) lines are listed; Copy logs puts all \(BackgroundJournal.limit) on the clipboard, with the queue's current state and the Live Activity facts listed below.")
        }

        Section {
          if let report {
            Text(report.verdict.sentence)
              .font(.footnote.weight(.semibold))
              .foregroundStyle(Palette.ink)
              .fixedSize(horizontal: false, vertical: true)
            ForEach(report.facts, id: \.self) { fact in
              Text(fact)
                .font(.caption2.monospaced())
                .foregroundStyle(Palette.inkDim)
            }
          }
          Button("Start the card now") {
            downloads.startActivityNow()
            report = downloads.liveActivityReport()
          }
        } header: {
          Text("Live Activity")
        } footer: {
          Text("The lock-screen card is drawn by a widget inside this app's bundle, so when it does not appear there is nothing to see in the app. This says which link is missing; the button asks for a card immediately and reports what iOS answered.\n\nIf a card is live here but nothing is on the lock screen, add Extension check from the widget gallery: the same extension draws both, so one that is missing there means iOS never loaded the extension at all — which is the installer's job, not the app's.")
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
      .onAppear {
        report = downloads.liveActivityReport()
        journal = BackgroundJournal.shared.lines(Self.shownJournalLines)
      }
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

  /// Reads the journal at the moment of the tap rather than from the form, so a
  /// line the queue wrote since the screen opened is not what goes missing.
  @MainActor
  private func copyLogs() {
    let activity = downloads.liveActivityReport()
    let summary = DebugReport(
      app: Bundle.main.appVersion,
      folder: store.filesLocation,
      source: store.isCloudRoot ? "iCloud Drive" : "On this device",
      queued: downloads.activeCount,
      onDisk: Format.bytes(downloads.readyBytes),
      activity: activity,
      journal: BackgroundJournal.shared.lines(BackgroundJournal.limit),
      limit: BackgroundJournal.limit
    )
    UIPasteboard.general.string = summary.text
    report = activity
    journal = Array(summary.journal.suffix(Self.shownJournalLines))
    copiedLines = summary.journal.count
    copied = true
    copyToken += 1
    let token = copyToken
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(2))
      guard token == copyToken else { return }
      copied = false
    }
  }
}
