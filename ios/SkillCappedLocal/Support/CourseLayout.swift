import CoreGraphics

/// How a course page is arranged, as pure geometry — the answer is testable
/// without a screen.
///
/// The poster-and-lessons columns are a **landscape** arrangement: a course page
/// is read by scrolling its lessons while the art stays put, and there is only
/// room for both when the window is wider than it is tall. A portrait phone
/// stacks instead — the poster shrinks to a card beside the words, because a
/// poster column there eats the list it is supposed to decorate.
enum CourseLayout {
  /// How much wider than tall a window must be before the columns are used. A
  /// hair over 1 so a square-ish window (an iPad in a split view) stacks rather
  /// than splitting its width three ways.
  static let wideAspect: CGFloat = 1.05

  /// The most of the width the poster column may take, so the lessons keep the
  /// room a row of words needs even on a 4:3 window.
  static let posterShare: CGFloat = 0.46

  /// The stacked page's poster: a third of the width, floored so the art still
  /// reads and capped so it never becomes the page.
  static let heroShare: CGFloat = 0.32
  static let heroFloor: CGFloat = 96
  static let heroCeiling: CGFloat = 200

  /// Below this much width the lesson rows turn compact (a smaller still, a
  /// taller title) instead of squeezing the words out.
  static let roomyLessons: CGFloat = 440

  /// Whether the window is landscape enough for a poster column.
  static func isSideBySide(_ size: CGSize) -> Bool {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
      return false
    }
    return size.width >= size.height * wideAspect
  }

  /// How wide the poster column is: exactly what the art needs to fill the height
  /// at its own shape — the poster is whole, never letterboxed — capped so the
  /// lessons are not starved on a wide, short window.
  static func posterColumn(size: CGSize, ratio: CGFloat) -> CGFloat {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0,
          ratio.isFinite, ratio > 0
    else { return 0 }
    return min(size.height * ratio, size.width * posterShare)
  }

  /// The poster a stacked page opens with: a third of the width, floored so the
  /// art still reads and capped so it never becomes the page — or, on a window
  /// narrower than a poster, so it never takes half of it.
  static func heroWidth(for width: CGFloat) -> CGFloat {
    guard width.isFinite, width > 0 else { return heroFloor }
    return min(max(width * heroShare, heroFloor), min(heroCeiling, width * 0.42))
  }

  /// Whether the lessons have too little room for a roomy row.
  static func lessonsAreTight(width: CGFloat, side: CGFloat) -> Bool {
    guard width.isFinite, side.isFinite else { return false }
    return width - side < roomyLessons
  }
}
