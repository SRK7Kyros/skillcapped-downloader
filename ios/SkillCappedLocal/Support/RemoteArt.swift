import UIKit

/// Cover art the site hosts, loaded on demand and remembered in memory so a grid
/// of a hundred cards does not re-fetch a poster it already holds. The bytes are
/// kept between launches by the URL cache (the CDN sends cache headers); nothing
/// here writes into the library.
actor RemoteArtStore {
  static let shared = RemoteArtStore()

  private let session: URLSession
  private var memory: [URL: UIImage] = [:]

  init() {
    let configuration = URLSessionConfiguration.default
    configuration.timeoutIntervalForRequest = 20
    configuration.timeoutIntervalForResource = 40
    configuration.requestCachePolicy = .returnCacheDataElseLoad
    configuration.urlCache = URLCache(
      memoryCapacity: 12 * 1_024 * 1_024,
      diskCapacity: 96 * 1_024 * 1_024,
      diskPath: "remote-art"
    )
    session = URLSession(configuration: configuration)
  }

  func image(for url: URL) async -> UIImage? {
    if let held = memory[url] { return held }
    guard let (data, response) = try? await session.data(from: url) else { return nil }
    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
    guard let image = UIImage(data: data) else { return nil }
    if memory.count > 240 { memory.removeAll() }
    memory[url] = image
    return image
  }
}
