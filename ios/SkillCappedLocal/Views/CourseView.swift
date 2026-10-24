import SwiftUI

/// One course on this phone.
///
/// The screen itself is `CoursePage` — the same page a catalogue course opens,
/// with every row a file. This is only the library's source for it.
struct CourseView: View {
  let course: Course

  @EnvironmentObject private var progress: ProgressStore

  var body: some View {
    CoursePage(model: .library(course) { progress.fraction(for: $0) })
  }
}
