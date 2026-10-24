import Combine
import SwiftUI
import UIKit

/// A playing lesson stays the way the phone is held.
///
/// The system's rotation lock sends the interface back to portrait when it is
/// turned on with the phone on its side, because the lock pins the window to the
/// orientation it was unlocked in whatever the app declares. Nothing in the app
/// was asking for portrait — the window scene was.
///
/// There are two answers and the player needs both. A geometry request is the
/// public way to ask the window to turn, and it is honoured whenever the system
/// allows it (the Camera app turns its own interface the same way). When it is
/// refused — a lock that has just engaged is the case that matters here — the
/// picture is drawn turned by the player itself instead, which no setting can
/// prevent because it is only a transform on our own view.
enum PlayerOrientation {
  /// How far the player's content has to be turned to stand upright in its
  /// window, and therefore which window edge each of its own edges faces.
  enum Turn: Equatable {
    case upright
    case clockwise
    case counterClockwise

    var angle: Angle {
      switch self {
      case .upright: return .zero
      case .clockwise: return .degrees(90)
      case .counterClockwise: return .degrees(-90)
      }
    }

    var isTurned: Bool { self != .upright }
  }

  /// The window mask a physical orientation asks for.
  ///
  /// The two enums name the landscapes the other way round —
  /// `UIDeviceOrientation.landscapeLeft` is `UIInterfaceOrientation.landscapeRight`
  /// — and a phone lying flat on a table names no orientation at all.
  static func mask(for orientation: UIDeviceOrientation) -> UIInterfaceOrientationMask? {
    switch orientation {
    case .portrait: return .portrait
    case .portraitUpsideDown: return .portraitUpsideDown
    case .landscapeLeft: return .landscapeRight
    case .landscapeRight: return .landscapeLeft
    case .faceUp, .faceDown, .unknown: return nil
    @unknown default: return nil
    }
  }

  /// Whether a window of `window`'s orientation is the shape the phone is held
  /// in. Only the shape is compared: a landscape window is landscape whichever
  /// way round it is, and asking the system to turn a correct one the other way
  /// would be a needless half-turn.
  static func agrees(device: UIDeviceOrientation, window: UIInterfaceOrientation) -> Bool {
    switch device {
    case .portrait, .portraitUpsideDown: return window.isPortrait
    case .landscapeLeft, .landscapeRight: return window.isLandscape
    case .faceUp, .faceDown, .unknown: return true
    @unknown default: return true
    }
  }

  /// What the content has to do to fill `window` while the phone is held the way
  /// `device` says. A window the system has already turned needs nothing.
  static func turn(device: UIDeviceOrientation, window: CGSize) -> Turn {
    guard window.width <= window.height else { return .upright }
    switch mask(for: device) {
    case .landscapeRight?: return .clockwise
    case .landscapeLeft?: return .counterClockwise
    default: return .upright
    }
  }

  /// A turned picture takes its safe area from the window's other edges: the end
  /// of the phone the notch is on is one of its sides now.
  static func insets(_ insets: EdgeInsets, turned turn: Turn) -> EdgeInsets {
    switch turn {
    case .upright:
      return insets
    case .clockwise:
      return EdgeInsets(
        top: insets.trailing,
        leading: insets.top,
        bottom: insets.leading,
        trailing: insets.bottom
      )
    case .counterClockwise:
      return EdgeInsets(
        top: insets.leading,
        leading: insets.bottom,
        bottom: insets.trailing,
        trailing: insets.top
      )
    }
  }

  /// The window's own rotation, which a lock does not refuse outright.
  @MainActor
  static func request(_ mask: UIInterfaceOrientationMask) {
    guard let scene = activeScene else { return }
    scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
  }

  @MainActor
  static var activeScene: UIWindowScene? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
  }
}

/// Watches the phone while a lesson is on screen: publishes the orientation so
/// the player can turn its own picture, and asks the window to follow whenever
/// the two disagree.
@MainActor
final class OrientationKeeper: ObservableObject {
  /// How often the phone is read. The sensor notifies on movement, but a lock
  /// engaging moves nothing, so the window can turn against the phone without an
  /// event to hear — and a read of two properties is free.
  private static let tick: UInt64 = 400_000_000

  /// A phone turning with the lock off is answered by the window's own rotation
  /// animation, which takes a moment. Publishing the new orientation only after
  /// it has had that moment keeps the player from turning its picture too and
  /// then turning it back, which read as a stumble.
  private static let settleDelay: UInt64 = 350_000_000

  /// A request the system keeps refusing must not be repeated for ever: the
  /// player's own rotation already covers it.
  private static let attempts = 8

  /// The orientation the picture is drawn for.
  @Published private(set) var device: UIDeviceOrientation = UIDevice.current.orientation

  /// The orientation the phone is in right now, which the window is asked for
  /// before it is published.
  private var physical = UIDevice.current.orientation
  private var watch: Task<Void, Never>?
  private var pending: Task<Void, Never>?
  private var refused = 0

  /// Called when the player opens, and asks straight away — that is what turns a
  /// picture the lock has already sent portrait back the way the phone is held.
  func start() {
    guard watch == nil else { return }
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    physical = UIDevice.current.orientation
    device = physical
    settle()
    watch = Task { @MainActor in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: Self.tick)
        guard !Task.isCancelled else { return }
        read()
      }
    }
  }

  /// Called when the player closes, giving the orientation back to the app.
  func stop() {
    watch?.cancel()
    watch = nil
    pending?.cancel()
    pending = nil
    UIDevice.current.endGeneratingDeviceOrientationNotifications()
  }

  private func read() {
    let now = UIDevice.current.orientation
    if now != physical {
      physical = now
      publish()
    }
    settle()
  }

  private func publish() {
    pending?.cancel()
    pending = Task { @MainActor in
      try? await Task.sleep(nanoseconds: Self.settleDelay)
      guard !Task.isCancelled else { return }
      device = physical
    }
  }

  /// Asks the window for the orientation the phone is in, and stops asking once
  /// the system has made it clear it will not.
  private func settle() {
    guard let scene = PlayerOrientation.activeScene else { return }
    guard !PlayerOrientation.agrees(device: physical, window: scene.interfaceOrientation) else {
      refused = 0
      return
    }
    guard let wanted = PlayerOrientation.mask(for: physical) else { return }
    guard refused < Self.attempts else { return }
    refused += 1
    PlayerOrientation.request(wanted)
  }
}
