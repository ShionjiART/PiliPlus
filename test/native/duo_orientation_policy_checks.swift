import UIKit

/// Invoked by the simulator probe against the production orientation policy.
func checkDuoOrientationPolicy() -> [String] {
  var policy = DuoOrientationPolicy()
  var passed = [String]()
  precondition(!policy.handlesAutomaticOrientation && policy.geometryMask == nil)

  // Recognition must release preferences while still on the outer screen,
  // without waiting for a hinge callback or the inner display's first layout.
  precondition(policy.recognizeFoldableDisplay())
  precondition(policy.geometryMask?.rawValue == 0 && policy.releasesPortraitLock)
  precondition(policy.isHingeOpen == nil)
  passed.append("Device recognition releases the old preference before hinge updates")

  policy.updateHinge(isOpen: false)
  precondition(policy.geometryMask?.rawValue == 0 && policy.releasesPortraitLock)
  policy.updateHinge(isOpen: true)
  precondition(policy.geometryMask?.rawValue == 0 && policy.releasesPortraitLock)
  precondition(!policy.updateHinge(isOpen: nil))
  precondition(!policy.updateHinge(isOpen: true))
  precondition(policy.geometryMask?.rawValue == 0)
  passed.append("Opening, closing and unavailable hinge data never select an orientation")

  let preference = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: policy.geometryMask!)
  precondition(preference.interfaceOrientations == nil)
  precondition(preference.interfaceOrientations != .all)
  passed.append("The UIKit request is no-preference, not portrait or all")

  policy.playerFullScreen = true
  precondition(policy.geometryMask == nil && !policy.releasesPortraitLock)
  policy.updateHinge(isOpen: false)
  precondition(policy.geometryMask == nil && policy.handlesAutomaticOrientation)
  policy.playerFullScreen = false
  precondition(policy.geometryMask?.rawValue == 0)
  passed.append("Fullscreen retains explicit direction; exit restores system choice")

  policy.automatic = false
  precondition(policy.geometryMask == nil && !policy.handlesAutomaticOrientation)
  policy.automatic = true
  precondition(policy.geometryMask?.rawValue == 0)
  passed.append("Manual mode opts out without changing the system-managed normal mode")
  return passed
}

func checkDuoDisplayDirections() -> [String] {
  var directions = DuoDisplayDirections()
  precondition(directions.upright(inner: false, device: .portrait) == .portrait)
  precondition(directions.upright(inner: true, device: .portrait) == .landscapeLeft)
  precondition(directions.upright(inner: true, device: .portraitUpsideDown) == .landscapeRight)
  precondition(directions.upright(inner: true, device: .landscapeLeft) == .portrait)
  precondition(directions.upright(inner: true, device: .landscapeRight) == .portraitUpsideDown)
  directions.observe(inner: true, device: .portrait, interface: .landscapeLeft)
  // Later fullscreen orientation must never replace the normal display baseline.
  directions.observe(inner: true, device: .portrait, interface: .landscapeRight)
  precondition(directions.upright(inner: true, device: .portrait) == .landscapeLeft)
  return ["Display-relative upright directions cover four physical poses",
    "Fullscreen cannot overwrite a learned normal baseline"]
}


func checkDuoStatusBarPolicy() -> [String] {
  for inner in [false, true] {
    // Normal inner pages keep icons; expanded playing outer video hides them.
    precondition(DuoStatusBarPolicy.hidesStatusIcons(inner: inner, playerFullScreen: false,
      video: ["fullScreen": false, "paused": false, "collapsed": false]) == !inner)
    for video in [["paused": true], ["collapsed": true], ["paused": true, "collapsed": true]] {
      precondition(!DuoStatusBarPolicy.hidesStatusIcons(inner: inner, playerFullScreen: false, video: video))
    }
    // Native state can arrive before metadata, or metadata before native state.
    for video in [nil, ["fullScreen": false], ["paused": true, "collapsed": true]] as [[String: Any]?] {
      precondition(DuoStatusBarPolicy.hidesStatusIcons(inner: inner, playerFullScreen: true, video: video))
    }
    precondition(DuoStatusBarPolicy.hidesStatusIcons(inner: inner, playerFullScreen: false,
      video: ["fullScreen": true, "paused": true, "collapsed": true]))
    precondition(!DuoStatusBarPolicy.hidesStatusIcons(inner: inner, playerFullScreen: false, video: nil))
  }
  return ["Both displays hide status icons in fullscreen, independent of update ordering",
    "Exiting fullscreen restores inner persistence and outer pause/collapse visibility"]
}
