import AVFoundation

/// The app's sound, taken over the way a video app does.
///
/// Without a word from us an app runs on the default session category,
/// `soloAmbient`: the ringer switch silences it and it stops when the screen
/// locks, whatever the lesson is doing. That is why a lesson had no sound at all
/// on a phone left on silent — the transport showed a picture advancing and the
/// speaker said nothing — and why `UIBackgroundModes: audio` could not help.
enum AudioSession {
  static let category: AVAudioSession.Category = .playback
  static let mode: AVAudioSession.Mode = .moviePlayback

  /// Where the sound may go: an AirPlay screen or speaker, and Bluetooth
  /// headphones in their high-quality stereo profile. A video app that allows
  /// neither is silent on every device but the phone's own speaker, and the
  /// route menu in the player's header has nothing to offer.
  static let options: AVAudioSession.CategoryOptions = [.allowAirPlay, .allowBluetoothA2DP]

  /// Called when the player opens; answers whether the session took it, so a
  /// failure is visible to a test rather than silent.
  @discardableResult
  static func activate() -> Bool {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(category, mode: mode, options: options)
      try session.setActive(true)
      return true
    } catch {
      return false
    }
  }

  /// Called when the player closes, giving the sound back to whatever was
  /// playing before it.
  static func deactivate() {
    try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
  }
}
