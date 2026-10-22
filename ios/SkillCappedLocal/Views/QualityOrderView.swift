import SwiftUI

/// The fallback chain, in the user's own order. Reordering this list is the
/// whole setting: the first rendition the CDN publishes is the one fetched.
struct QualityOrderView: View {
  @EnvironmentObject private var prefs: PreferencesStore

  var body: some View {
    List {
      Section {
        ForEach(prefs.qualityPriority, id: \.self) { label in
          HStack(spacing: 10) {
            Text(label)
              .foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            if let tier = QualityTier.byLabel(label) {
              Text("tier \(tier.id)")
                .font(.caption2)
                .foregroundStyle(Palette.inkFaint)
            }
          }
        }
        .onMove { source, destination in
          prefs.move(from: source, to: destination)
        }
      } header: {
        Text("Quality")
      } footer: {
        Text("Every download asks for the first rendition here that the CDN actually publishes, then works down the list. Drag to reorder.")
      }

      Section {
        Button("Reset to default") { prefs.reset() }
      }
    }
    .environment(\.editMode, .constant(.active))
    .scrollContentBackground(.hidden)
    .background(Palette.bg)
    .navigationTitle("Download quality")
    .navigationBarTitleDisplayMode(.inline)
  }
}
