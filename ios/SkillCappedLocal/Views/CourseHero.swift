import SwiftUI

/// The pill a course page opens with — *Play* on a course this phone has, the
/// download on one it does not. One shape for both so the two course pages read
/// as the same screen.
struct CoursePill: View {
  let title: String
  let systemImage: String
  /// In a column the pill is only as wide as its words; stacked it spans the
  /// page, where a thumb reaches it.
  var compact = false

  var body: some View {
    Label(title, systemImage: systemImage)
      .font(.caption.weight(.bold))
      .padding(.horizontal, compact ? 14 : 0)
      .frame(maxWidth: compact ? nil : CGFloat.infinity)
      .padding(.vertical, compact ? 7 : 8)
      .background(Palette.brand, in: Capsule())
      .foregroundStyle(Palette.bg)
  }
}

/// The words at the top of a course page: the role badge, the title, the numbers
/// and one pill — shared by the course this phone has and the one the catalogue
/// lists, so both pages are the same screen.
///
/// Pinned (the columns, landscape) it is two short lines — badge and numbers with
/// the pill at the right, then the title — because every point here is a point the
/// lesson list does not get. Stacked (portrait) each part takes its own line and
/// the pill the full width, where it is the page's obvious target.
struct CourseHero<Action: View>: View {
  let role: String
  let title: String
  let meta: String
  let pinned: Bool
  private let action: Action

  init(role: String, title: String, meta: String, pinned: Bool, @ViewBuilder action: () -> Action) {
    self.role = role
    self.title = title
    self.meta = meta
    self.pinned = pinned
    self.action = action()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: pinned ? 6 : 8) {
      if pinned {
        HStack(spacing: 8) {
          badge
          if !meta.isEmpty {
            Text(meta)
              .font(.caption2)
              .foregroundStyle(Palette.inkFaint)
              .lineLimit(1)
              .truncationMode(.tail)
          }
          Spacer(minLength: 10)
          action
        }
        titleText
          .lineLimit(2)
      } else {
        badge
        titleText
        if !meta.isEmpty {
          Text(meta)
            .font(.caption2)
            .foregroundStyle(Palette.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
        }
        action
          .padding(.top, 2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  @ViewBuilder private var badge: some View {
    if !role.isEmpty {
      Text(Format.roleLabel(role))
        .font(.caption2.weight(.heavy))
        .foregroundStyle(Palette.bg)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Palette.brand, in: Capsule())
    }
  }

  private var titleText: some View {
    Text(title)
      .font(.headline)
      .foregroundStyle(Palette.ink)
      .fixedSize(horizontal: false, vertical: true)
  }
}
