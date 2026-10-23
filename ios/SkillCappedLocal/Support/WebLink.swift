import Foundation

/// A catalogue string that names a picture: only an http(s) address is worth
/// handing to an image view, because anything else would be read as a local file
/// path the app never wrote.
enum WebLink {
  static func url(_ text: String) -> URL? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let url = URL(string: trimmed),
          let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http"
    else { return nil }
    return url
  }
}
