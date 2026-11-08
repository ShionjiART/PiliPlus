import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  @available(iOS 26.0, *)
  override func preferredWindowingControlStyle(
    for windowScene: UIWindowScene
  ) -> UIWindowScene.WindowingControlStyle {
    return .minimal
  }

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    // FlutterSceneDelegate declares this method but may not implement it.
    if FlutterSceneDelegate.instancesRespond(
      to: #selector(UISceneDelegate.scene(_:willConnectTo:options:)))
    {
      super.scene(scene, willConnectTo: session, options: connectionOptions)
    }
    // iPhone on iOS 26+: host Flutter in a native tab bar controller so the
    // main navigation uses the system Liquid Glass tab bar, which iPhone Duo
    // also places in its vertical status bar.
    if #available(iOS 26.0, *), UIDevice.current.userInterfaceIdiom == .phone,
      let window,
      let flutterViewController = window.rootViewController as? FlutterViewController
    {
      let tabs = NativeTabBarController(flutterViewController: flutterViewController)
      (flutterViewController as? DuoFlutterViewController)?.onFoldOrientationApplied = { [weak tabs] needsSync in
        tabs?.publishFoldOrientationChange(needsFlutterSync: needsSync)
      }
      (flutterViewController as? DuoFlutterViewController)?.onPlayerOrientationRequest = { [weak tabs] request in
        tabs?.publishPlayerOrientationRequest(request)
      }
      let navigation = NativePageNavigationController(rootViewController: tabs)
      navigation.onBack = { [weak tabs] completion in
        tabs?.requestBack(completion: completion)
      }
      navigation.onPageAction = { [weak tabs] owner, id, completion in
        tabs?.requestPageAction(owner: owner, id: id, completion: completion)
      }
      navigation.onCommentAction = { [weak tabs] owner, completion in
        tabs?.requestCommentAction(owner: owner, completion: completion)
      }
      navigation.onCommentVisibilityChange = { [weak tabs] owner, visible in
        tabs?.publishCommentVisibility(owner: owner, visible: visible)
      }
      navigation.onVisibilityChange = { [weak tabs] back, actions, video, home in
        tabs?.publishBarVisibility(back: back, actions: actions, video: video, home: home)
      }
      window.rootViewController = navigation
      (flutterViewController as? DuoFlutterViewController)?.observeHinge(in: navigation.view)
    }
  }
}

/// Hosts the single Flutter view inside whichever tab is selected. Dart sends
/// the tabs over `piliplus/native_tab_bar`; until then the tab bar is hidden
/// and Flutter draws its own navigation.
@available(iOS 26.0, *)
final class NativeTabBarController: UITabBarController, UITabBarControllerDelegate {
  private let flutterViewController: FlutterViewController
  private var channel: FlutterMethodChannel?

  init(flutterViewController: FlutterViewController) {
    self.flutterViewController = flutterViewController
    super.init(nibName: nil, bundle: nil)
    delegate = self
    let channel = FlutterMethodChannel(
      name: "piliplus/native_tab_bar",
      binaryMessenger: flutterViewController.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    self.channel = channel
    let host = makeHost()
    viewControllers = [host]
    host.embed(flutterViewController)
    setTabBarHidden(true, animated: false)
  }

  private var safeArea = UIEdgeInsets.zero
  private var canGoBack = false
  private var isPlayerFullScreen = false
  private var tabsConfigured = false
  private var requestedTabBarHidden = true
  private var appliedTabBarHidden = true
  private var videoChrome: [String: Any]?
  var isInnerDisplay: Bool {
    (flutterViewController as? DuoFlutterViewController)?.isInnerDirectionDisplay ?? false
  }
  private var navigationHost: NativePageNavigationController? {
    navigationController as? NativePageNavigationController
  }

  private func updateBackButton() {
    navigationHost?.setPageState(canGoBack: canGoBack, fullScreen: isPlayerFullScreen)
  }

  private func updateTabBarVisibility(animated: Bool) {
    // Secondary routes keep their commands, but not the three root tabs.
    let hidden = isPlayerFullScreen || (videoChrome?["fullScreen"] as? Bool ?? false) || !tabsConfigured
      || canGoBack || requestedTabBarHidden
    guard hidden != appliedTabBarHidden else { return }
    appliedTabBarHidden = hidden
    setTabBarHidden(hidden, animated: animated)
  }

  func requestBack(completion: @escaping () -> Void) {
    channel?.invokeMethod("back", arguments: nil) { _ in completion() }
  }

  func publishFoldOrientationChange(needsFlutterSync: Bool) {
    channel?.invokeMethod("foldOrientationChanged", arguments: needsFlutterSync)
  }

  func publishPlayerOrientationRequest(_ request: [String: Any]) {
    channel?.invokeMethod("playerOrientationRequest", arguments: request)
  }

  func requestPageAction(owner: Int, id: String, completion: @escaping () -> Void) {
    channel?.invokeMethod("pageAction", arguments: ["owner": owner, "id": id]) {
      _ in completion()
    }
  }

  func requestCommentAction(owner: Int, completion: @escaping () -> Void) {
    channel?.invokeMethod("commentAction", arguments: owner) { _ in completion() }
  }

  func publishCommentVisibility(owner: Int, visible: Bool) {
    channel?.invokeMethod("commentButtonVisible", arguments: ["owner": owner, "visible": visible])
  }

  func publishBarVisibility(back: Bool, actions: Bool, video: Bool, home: Bool) {
    channel?.invokeMethod("homeToolsVisible", arguments: home)
    channel?.invokeMethod("backButtonVisible", arguments: back)
    channel?.invokeMethod("pageActionsVisible", arguments: actions)
    channel?.invokeMethod("videoNavigationEnabled", arguments: video)
  }

  private func makeHost() -> FlutterHostViewController {
    let host = FlutterHostViewController()
    host.onSafeAreaChange = { [weak self] insets in
      guard let self, insets != self.safeArea else { return }
      self.safeArea = insets
      self.updateBackButton()
      self.channel?.invokeMethod("safeArea", arguments: Self.encode(insets))
    }
    return host
  }

  private static func encode(_ insets: UIEdgeInsets) -> [String: Double] {
    [
      "top": insets.top, "left": insets.left,
      "bottom": insets.bottom, "right": insets.right,
    ]
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setNavigationState":
      let state = call.arguments as? [String: Any] ?? [:]
      navigationHost?.performNavigationUpdates {
        if let page = state["page"] as? [String: Any] {
          videoChrome = page["video"] as? [String: Any]
          canGoBack = page["canGoBack"] as? Bool ?? canGoBack
          navigationHost?.setPageActions(owner: page["owner"] as? Int ?? 0,
            items: page["items"] as? [[String: Any]] ?? [], video: videoChrome,
            homeTools: page["homeTools"] as? Bool ?? false, canGoBack: canGoBack)
        }
        if let comment = state["comment"] as? [String: Any] {
          navigationHost?.setCommentAction(owner: comment["owner"] as? Int ?? 0,
            visible: comment["visible"] as? Bool ?? false,
            label: comment["label"] as? String ?? "发表评论")
        }
      }
      verticalBarDidChange()
      result(nil)
    case "setCommentAction":
      let args = call.arguments as? [String: Any] ?? [:]
      navigationHost?.setCommentAction(owner: args["owner"] as? Int ?? 0,
        visible: args["visible"] as? Bool ?? false, label: args["label"] as? String ?? "发表评论")
      result(nil)
    case "setPageActions":
      if let args = call.arguments as? [String: Any] {
        videoChrome = args["video"] as? [String: Any]
        canGoBack = args["canGoBack"] as? Bool ?? canGoBack
        navigationHost?.setPageActions(
          owner: args["owner"] as? Int ?? 0,
          items: args["items"] as? [[String: Any]] ?? [], video: videoChrome,
          homeTools: args["homeTools"] as? Bool ?? false, canGoBack: canGoBack)
        verticalBarDidChange()
      }
      result(nil)
    case "setCanGoBack":
      canGoBack = call.arguments as? Bool ?? false
      updateBackButton()
      updateTabBarVisibility(animated: true)
      result(nil)
    case "getFoldOrientationDiagnostics":
      result((flutterViewController as? DuoFlutterViewController)?.foldOrientationDiagnostics() ?? [])
    case "beginPlayerOrientation":
      result((flutterViewController as? DuoFlutterViewController)?
        .beginAutomaticPlayerOrientation(vertical: call.arguments as? Bool ?? false) ?? false)
    case "isPlayerOrientationRequestCurrent":
      result((flutterViewController as? DuoFlutterViewController)?
        .isPlayerOrientationRequestCurrent(call.arguments as? Int ?? -1) ?? false)
    case "completePlayerOrientationRequest":
      let args = call.arguments as? [String: Any] ?? [:]
      DispatchQueue.main.async { [weak self] in
        (self?.flutterViewController as? DuoFlutterViewController)?
          .completePlayerOrientationRequest(args["id"] as? Int ?? -1,
            success: args["success"] as? Bool ?? false)
        result(nil)
      }
    case "applyFoldableOrientation":
      // Flutter queues its orientationPreferences update on this same queue.
      // Clear the scene only after that update, including its geometry request.
      DispatchQueue.main.async { [weak self] in
        let handled = (self?.flutterViewController as? DuoFlutterViewController)?
          .configureAutomaticOrientation(call.arguments as? Bool ?? true) ?? false
        result(handled)
      }
    case "setFullScreen":
      isPlayerFullScreen = call.arguments as? Bool ?? false
      (flutterViewController as? DuoFlutterViewController)?
        .setPlayerFullScreen(isPlayerFullScreen)
      updateBackButton()
      verticalBarDidChange()
      result(nil)
    case "getNavigationCapabilities":
      result(["verticalRail": hasVerticalBar, "commentActions": true])
    case "getSafeArea":
      result(Self.encode(safeArea))
    case "setTabs":
      guard let args = call.arguments as? [String: Any],
        let tabs = args["tabs"] as? [[String: String]], tabs.count > 1
      else { return result(false) }
      let selected = min(args["selected"] as? Int ?? 0, tabs.count - 1)
      let hosts = tabs.map { tab -> FlutterHostViewController in
        let host = makeHost()
        let symbols = Self.symbols(for: tab["id"] ?? "")
        host.tabBarItem = UITabBarItem(
          title: tab["title"],
          image: UIImage(systemName: symbols.normal),
          selectedImage: UIImage(systemName: symbols.selected))
        return host
      }
      hosts[selected].embed(flutterViewController)
      viewControllers = hosts
      selectedIndex = selected
      tabsConfigured = true
      requestedTabBarHidden = false
      updateTabBarVisibility(animated: false)
      result(true)
    case "setSelected":
      if let index = call.arguments as? Int { select(index) }
      result(nil)
    case "setBadge":
      if let args = call.arguments as? [String: Any], let index = args["index"] as? Int,
        let item = viewControllers?[safe: index]?.tabBarItem
      {
        item.badgeValue = args["value"] as? String
      }
      result(nil)
    case "setHidden":
      requestedTabBarHidden = call.arguments as? Bool ?? false
      updateTabBarVisibility(animated: true)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private static func symbols(for id: String) -> (normal: String, selected: String) {
    switch id {
    case "home": return ("house", "house.fill")
    case "dynamics": return ("circle.dashed", "circle.dashed.inset.filled")
    case "mine": return ("person", "person.fill")
    default: return ("circle", "circle.fill")
    }
  }

  private func select(_ index: Int) {
    guard let host = viewControllers?[safe: index] as? FlutterHostViewController,
      index != selectedIndex
    else { return }
    host.embed(flutterViewController)
    selectedIndex = index
  }

  func tabBarController(
    _ tabBarController: UITabBarController, shouldSelect viewController: UIViewController
  ) -> Bool {
    // Move the Flutter view into the tab before UIKit shows it.
    (viewController as? FlutterHostViewController)?.embed(flutterViewController)
    return true
  }

  func tabBarController(
    _ tabBarController: UITabBarController, didSelect viewController: UIViewController
  ) {
    channel?.invokeMethod("select", arguments: selectedIndex)
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    flutterViewController.supportedInterfaceOrientations
  }

  // Normal Duo pages retain the system rail. Only fullscreen hides it; video
  // pixels can extend underneath without changing the rest of the page's inset.
  private var hasVerticalBar = false {
    didSet { verticalBarDidChange() }
  }
  private var isVerticalBarHidden: Bool {
    guard hasVerticalBar else { return false }
    return DuoStatusBarPolicy.hidesStatusIcons(
      inner: isInnerDisplay, playerFullScreen: isPlayerFullScreen, video: videoChrome)
  }
  private var sentVerticalBarHidden = false

  private func verticalBarDidChange() {
    updateTabBarVisibility(animated: true)
    let hidden = isVerticalBarHidden
    guard hidden != sentVerticalBarHidden else { return }
    sentVerticalBarHidden = hidden
    UIView.animate(withDuration: 0.25) { self.setNeedsStatusBarAppearanceUpdate() }
    channel?.invokeMethod("verticalBarHidden", arguments: hidden)
  }

  override var childForStatusBarHidden: UIViewController? {
    hasVerticalBar ? nil : super.childForStatusBarHidden
  }

  override var prefersStatusBarHidden: Bool {
    hasVerticalBar ? isVerticalBarHidden : super.prefersStatusBarHidden
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateBackButton()
    // The vertical bar edge stays set while the status bar is hidden, and
    // changes when the device folds or unfolds.
    var hasVerticalBar = false
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        hasVerticalBar = traitCollection.verticalBarEdge != .unspecified
      }
    #endif
    if hasVerticalBar {
      (flutterViewController as? DuoFlutterViewController)?.recognizeFoldableDisplay()
    }
    if hasVerticalBar != self.hasVerticalBar {
      self.hasVerticalBar = hasVerticalBar
      channel?.invokeMethod("rightRailDevice", arguments: hasVerticalBar)
    }
    verticalBarDidChange()
  }

  // The tabs do not forward appearance callbacks, so deliver this controller's
  // appearance to Flutter directly. FlutterViewController creates its rendering
  // surface in viewWillAppear only once the viewport size is known, and
  // otherwise only on first layout or scene activation while active; on device
  // both can be missed at launch, leaving the launch screen up. The first
  // appearance is therefore delivered after this view is in the window and laid
  // out.
  private var hasFlutterAppeared = false

  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    if hasFlutterAppeared {
      flutterViewController.beginAppearanceTransition(true, animated: animated)
    }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if hasFlutterAppeared {
      flutterViewController.endAppearanceTransition()
    } else {
      hasFlutterAppeared = true
      flutterViewController.view.layoutIfNeeded()
      flutterViewController.beginAppearanceTransition(true, animated: false)
      flutterViewController.endAppearanceTransition()
    }
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    flutterViewController.beginAppearanceTransition(false, animated: animated)
  }

  override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    flutterViewController.endAppearanceTransition()
  }
}

/// A tab's content controller; it only holds the shared Flutter view controller
/// and forwards system appearance queries to it. Appearance callbacks are not
/// forwarded, so moving Flutter between tabs does not pause the engine.
final class FlutterHostViewController: UIViewController {
  override var shouldAutomaticallyForwardAppearanceMethods: Bool { false }
  override var childForStatusBarStyle: UIViewController? { children.first }
  override var childForStatusBarHidden: UIViewController? { children.first }
  override var childForHomeIndicatorAutoHidden: UIViewController? { children.first }
  override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
    children.first
  }
  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    children.first?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
  }

  func embed(_ child: UIViewController) {
    guard child.parent !== self else { return }
    child.willMove(toParent: nil)
    child.view.removeFromSuperview()
    child.removeFromParent()
    addChild(child)
    child.view.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(child.view)
    NSLayoutConstraint.activate([
      child.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      child.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      child.view.topAnchor.constraint(equalTo: view.topAnchor),
      child.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
    ])
    child.didMove(toParent: self)
    onSafeAreaChange?(view.safeAreaInsets)
  }

  /// The Flutter view reports no safe area when it is not the window's root
  /// controller, so the tab bar controller forwards this one to Dart.
  var onSafeAreaChange: ((UIEdgeInsets) -> Void)?

  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    if !children.isEmpty { onSafeAreaChange?(view.safeAreaInsets) }
  }
}

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

// MARK: - Fold orientation policy

/// Fullscreen takes precedence over the inner display's normal persistent icons.
/// Either fullscreen signal is sufficient while Dart/native updates settle.
struct DuoStatusBarPolicy {
  static func hidesStatusIcons(inner: Bool, playerFullScreen: Bool, video: [String: Any]?) -> Bool {
    if playerFullScreen || (video?["fullScreen"] as? Bool ?? false) { return true }
    if inner { return false }
    guard let video else { return false }
    return !(video["collapsed"] as? Bool ?? false)
      && !(video["paused"] as? Bool ?? false)
  }
}

/// A missing/unknown hinge update means the hierarchy is moving, not closing.
/// Keep the last authoritative posture until another valid update arrives.
struct DuoOrientationPolicy {
  var automatic = true
  var playerFullScreen = false
  private(set) var foldableDisplayRecognized = false
  private(set) var isHingeOpen: Bool?

  @discardableResult
  mutating func recognizeFoldableDisplay() -> Bool {
    guard !foldableDisplayRecognized else { return false }
    foldableDisplayRecognized = true
    return true
  }

  @discardableResult
  mutating func updateHinge(isOpen: Bool?) -> Bool {
    guard let isOpen else { return false }
    recognizeFoldableDisplay()
    guard isOpen != isHingeOpen else { return false }
    isHingeOpen = isOpen
    return true
  }

  var handlesAutomaticOrientation: Bool { automatic && foldableDisplayRecognized }
  var geometryMask: UIInterfaceOrientationMask? {
    guard handlesAutomaticOrientation, !playerFullScreen else { return nil }
    // Empty means no scene orientation preference. .all still expresses a
    // preference; portrait on the outer display can carry into inner migration.
    return []
  }
  var releasesPortraitLock: Bool {
    handlesAutomaticOrientation && !playerFullScreen
  }
}

/// UIKit's interface orientation is display-relative. The inner display's
/// upright baseline is one quarter turn from the outer display. Learn a normal
/// scene's baseline when available; retain the Duo baseline for first opening.
struct DuoDisplayDirections {
  private var offsets = [Bool: Int]()
  private let cycle: [UIInterfaceOrientation] = [.portrait, .landscapeLeft, .portraitUpsideDown, .landscapeRight]

  mutating func observe(inner: Bool, device: UIDeviceOrientation, interface: UIInterfaceOrientation) {
    guard offsets[inner] == nil,
      let physical = cycle.firstIndex(where: { $0.rawValue == device.rawValue }),
      let displayed = cycle.firstIndex(of: interface) else { return }
    offsets[inner] = (displayed - physical + 4) % 4
  }

  func upright(inner: Bool, device: UIDeviceOrientation) -> UIInterfaceOrientation {
    let physical = cycle.firstIndex(where: { $0.rawValue == device.rawValue }) ?? 0
    return cycle[(physical + (offsets[inner] ?? (inner ? 1 : 0))) % 4]
  }
}

class DuoFlutterViewController: FlutterViewController {
  var onFoldOrientationApplied: ((Bool) -> Void)?
  var onPlayerOrientationRequest: (([String: Any]) -> Void)?
  private var foldPolicy = DuoOrientationPolicy()
  private var lastRequestedMask: UIInterfaceOrientationMask?
  private weak var orientationScene: UIWindowScene?
  private weak var orientationScreen: UIScreen?
  private var orientationTrace = [[String: Any]]()
  private var lastLayoutGeometry = ""
  private var hingeInteraction: UIInteraction?
  private enum DirectionPhase { case restore, hold, release, prepareMigration }
  private struct DirectionRequest {
    let id: Int
    let target: UIInterfaceOrientation?
    let phase: DirectionPhase
    var acknowledged = false
  }
  private var directions = DuoDisplayDirections()
  private var managedFullScreenVertical: Bool?
  private var recoveryEnabled = false
  private var directionGeneration = 0
  private var directionRequest: DirectionRequest?
  private var expectedInnerDisplay: Bool?
  private var migrationPrepared = false
  private weak var currentDirectionScreen: UIScreen?
  private var transitioning = false
  private var directionFailed = false
  private var deviceObserver: NSObjectProtocol?
  private var lastPhysicalOrientation = UIDeviceOrientation.portrait

  override func viewDidLoad() {
    super.viewDidLoad()
    observeHinge(in: view)
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    deviceObserver = NotificationCenter.default.addObserver(
      forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
        self?.applyHingeOrientation(force: true)
      }
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    applyHingeOrientation()
  }

  deinit {
    if let deviceObserver { NotificationCenter.default.removeObserver(deviceObserver) }
  }

  override func viewWillTransition(to size: CGSize,
    with coordinator: UIViewControllerTransitionCoordinator) {
    recordOrientation("transition.begin")
    transitioning = true
    applyHingeOrientation()
    super.viewWillTransition(to: size, with: coordinator)
    coordinator.animate(alongsideTransition: nil) { [weak self] _ in
      self?.recordOrientation("transition.end")
      self?.transitioning = false
      self?.observeNormalDirection()
      self?.advanceDirectionRequest()
      self?.applyHingeOrientation()
    }
  }

  /// Move the same observer to the stable navigation root once Flutter is
  /// embedded in tab hosts. Tab changes must not detach the hinge observer.
  func observeHinge(in host: UIView) {
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        if hingeInteraction == nil {
          hingeInteraction = UIHingeInteraction { [weak self] _, update in
            self?.hingeDidUpdate(update.hinge)
          }
        }
        guard let interaction = hingeInteraction, interaction.view !== host else { return }
        interaction.view?.removeInteraction(interaction)
        host.addInteraction(interaction)
      }
    #endif
  }

  func recognizeFoldableDisplay() {
    guard foldPolicy.recognizeFoldableDisplay() else { return }
    recordOrientation("device.recognized")
    applyHingeOrientation(force: true)
  }

  func configureAutomaticOrientation(_ automatic: Bool) -> Bool {
    if foldPolicy.automatic != automatic {
      foldPolicy.automatic = automatic
      lastRequestedMask = nil
      invalidateDirectionRequest()
      if #available(iOS 16.0, *) { setNeedsUpdateOfSupportedInterfaceOrientations() }
    }
    recordOrientation("automatic.configured")
    // A previous asynchronous Flutter orientation request may have replaced
    // the scene preference after our last clear; an explicit apply must retry.
    applyHingeOrientation(force: true)
    return foldPolicy.handlesAutomaticOrientation
  }

  func setPlayerFullScreen(_ fullScreen: Bool) {
    guard foldPolicy.playerFullScreen != fullScreen else { return }
    observeNormalDirection()
    foldPolicy.playerFullScreen = fullScreen
    managedFullScreenVertical = nil
    recoveryEnabled = recoveryEnabled || foldPolicy.handlesAutomaticOrientation
    invalidateDirectionRequest()
    recordOrientation(fullScreen ? "player.enter" : "player.exit")
    // The player's explicit SystemChrome request replaces scene preferences.
    lastRequestedMask = nil
    if #available(iOS 16.0, *) { setNeedsUpdateOfSupportedInterfaceOrientations() }
    if !fullScreen { applyHingeOrientation() }
  }

  #if compiler(>=6.4)
    @available(iOS 27.1, *)
    private func hingeDidUpdate(_ hinge: UIHinge?) {
      let isOpen: Bool?
      switch hinge?.status {
      case .closed: isOpen = false
      case .partiallyOpen, .fullyOpen: isOpen = true
      default: isOpen = nil
      }
      updateHingeState(isOpen)
    }
  #endif

  func updateHingeState(_ isOpen: Bool?) {
    let wasRecognized = foldPolicy.foldableDisplayRecognized
    let changed = foldPolicy.updateHinge(isOpen: isOpen)
    if changed && recoveryEnabled {
      expectedInnerDisplay = isOpen
      migrationPrepared = false
      invalidateDirectionRequest()
    }
    if changed || isOpen == nil {
      recordOrientation(isOpen.map { $0 ? "hinge.open" : "hinge.closed" } ?? "hinge.unavailable")
    }
    // Hinge changes do not select a portrait/landscape orientation. The
    // system must already be free to choose before the display moves.
    if changed && (!wasRecognized || recoveryEnabled) { applyHingeOrientation(force: true) }
  }

  var isInnerDirectionDisplay: Bool {
    guard let screen = view.window?.windowScene?.screen else { return false }
    return min(screen.bounds.width, screen.bounds.height) >= 600
  }

  private func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask {
    UIInterfaceOrientationMask(rawValue: 1 << UInt(orientation.rawValue))
  }

  private func observeNormalDirection() {
    guard #available(iOS 16.0, *), foldPolicy.handlesAutomaticOrientation,
      !recoveryEnabled, !foldPolicy.playerFullScreen,
      !transitioning, super.supportedInterfaceOrientations == .all,
      let scene = view.window?.windowScene else { return }
    directions.observe(inner: isInnerDirectionDisplay, device: UIDevice.current.orientation,
      interface: scene.effectiveGeometry.interfaceOrientation)
  }

  private func invalidateDirectionRequest() {
    directionGeneration += 1
    directionRequest = nil
    directionFailed = false
  }

  func beginAutomaticPlayerOrientation(vertical: Bool) -> Bool {
    guard foldPolicy.handlesAutomaticOrientation else { return false }
    managedFullScreenVertical = vertical
    recoveryEnabled = true
    invalidateDirectionRequest()
    applyHingeOrientation(force: true)
    return true
  }

  func isPlayerOrientationRequestCurrent(_ id: Int) -> Bool {
    directionRequest?.id == id && foldPolicy.handlesAutomaticOrientation
  }

  private func issueDirection(_ target: UIInterfaceOrientation?, phase: DirectionPhase) {
    guard let send = onPlayerOrientationRequest else { return }
    directionGeneration += 1
    directionRequest = DirectionRequest(id: directionGeneration, target: target, phase: phase)
    let name: String?
    switch target {
    case .portrait: name = "portraitUp"
    case .portraitUpsideDown: name = "portraitDown"
    case .landscapeLeft: name = "landscapeLeft"
    case .landscapeRight: name = "landscapeRight"
    default: name = nil
    }
    recordOrientation("direction.request.\(phase)", requestedMask: target.map { mask(for: $0).rawValue } ?? 30)
    send(["id": directionGeneration, "orientations": name.map { [$0] } ?? [String]()])
  }

  func completePlayerOrientationRequest(_ id: Int, success: Bool) {
    guard #available(iOS 16.0, *), isPlayerOrientationRequestCurrent(id),
      var request = directionRequest else { return }
    guard success else {
      directionRequest = nil
      directionFailed = true
      recordOrientation("direction.error", error: "Flutter rejected orientation synchronization")
      return
    }
    request.acknowledged = true
    directionRequest = request
    recordOrientation("direction.ack")
    if let target = request.target, let scene = view.window?.windowScene,
      scene.effectiveGeometry.interfaceOrientation != target {
      scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask(for: target))) { [weak self] error in
        guard self?.directionRequest?.id == id else { return }
        self?.directionRequest = nil
        self?.directionFailed = true
        self?.recordOrientation("direction.error", error: error.localizedDescription)
      }
    }
    advanceDirectionRequest()
  }

  private func advanceDirectionRequest() {
    guard #available(iOS 16.0, *), let request = directionRequest,
      request.acknowledged, let scene = view.window?.windowScene else { return }
    if let target = request.target {
      guard !transitioning, scene.effectiveGeometry.interfaceOrientation == target else { return }
      if let window = view.window {
        guard abs(view.bounds.width - window.bounds.width) < 1,
          abs(view.bounds.height - window.bounds.height) < 1 else { return }
      }
      directionRequest = nil
      recordOrientation("direction.settled")
      if request.phase == .restore { issueDirection(nil, phase: .release) }
    } else {
      directionRequest = nil
      if request.phase == .prepareMigration { migrationPrepared = true }
      clearSceneDirection(force: true)
      applyHingeOrientation()
    }
  }

  /// Returns true while this coordinator owns the display-specific request.
  private func coordinatePlayerDirection(force: Bool) -> Bool {
    guard #available(iOS 16.0, *), foldPolicy.handlesAutomaticOrientation,
      let scene = view.window?.windowScene else { return false }
    if currentDirectionScreen !== scene.screen {
      currentDirectionScreen = scene.screen
      invalidateDirectionRequest()
      lastRequestedMask = nil
    }
    if foldPolicy.playerFullScreen && managedFullScreenVertical == nil { return false }
    guard recoveryEnabled else { return false }
    if force { directionFailed = false }
    if directionFailed { return true }
    let device = UIDevice.current.orientation
    if (1...4).contains(device.rawValue), device != lastPhysicalOrientation {
      lastPhysicalOrientation = device
      invalidateDirectionRequest()
    }
    let inner = isInnerDirectionDisplay
    if let expected = expectedInnerDisplay {
      if expected != inner {
        if directionRequest == nil && !migrationPrepared { issueDirection(nil, phase: .prepareMigration) }
        return true
      }
      expectedInnerDisplay = nil
      migrationPrepared = false
    }
    if directionRequest != nil { return true }
    let upright = directions.upright(inner: inner, device: lastPhysicalOrientation)
    let holdOuterFullscreen = foldPolicy.playerFullScreen && !inner
    let target: UIInterfaceOrientation
    if holdOuterFullscreen {
      if managedFullScreenVertical == true { target = .portrait }
      else { target = upright.isLandscape ? upright : .landscapeRight }
    } else { target = upright }
    let current = scene.effectiveGeometry.interfaceOrientation
    let locked: Bool
    if #available(iOS 26.0, *) { locked = scene.effectiveGeometry.isInterfaceOrientationLocked }
    else { locked = false }
    if current != target && (!locked || holdOuterFullscreen) {
      issueDirection(target, phase: holdOuterFullscreen ? .hold : .restore)
    } else if holdOuterFullscreen {
      if super.supportedInterfaceOrientations != mask(for: target) {
        issueDirection(target, phase: .hold)
      }
    } else if super.supportedInterfaceOrientations != .all {
      issueDirection(nil, phase: .release)
    } else { clearSceneDirection(force: force) }
    return true
  }

  private func applyHingeOrientation(force: Bool = false) {
    if coordinatePlayerDirection(force: force) { return }
    if foldPolicy.releasesPortraitLock && super.supportedInterfaceOrientations != .all {
      if directionRequest == nil { issueDirection(nil, phase: .release) }
      return
    }
    guard foldPolicy.geometryMask != nil else { return }
    clearSceneDirection(force: force)
  }

  private func clearSceneDirection(force: Bool) {
    let mask: UIInterfaceOrientationMask = []
    guard #available(iOS 16.0, *), let scene = view.window?.windowScene,
      force || mask != lastRequestedMask || orientationScene !== scene
        || orientationScreen !== scene.screen else { return }
    lastRequestedMask = mask
    orientationScene = scene
    orientationScreen = scene.screen
    recordOrientation("preference.clear", requestedMask: mask.rawValue)
    onFoldOrientationApplied?(false)
    setNeedsUpdateOfSupportedInterfaceOrientations()
    scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak self] error in
      self?.recordOrientation("preference.error", error: error.localizedDescription)
      // A display migration may temporarily reject geometry; permit a retry
      // when Flutter reports the settled display dimensions.
      if self?.orientationScene === scene && self?.lastRequestedMask == mask {
        self?.lastRequestedMask = nil
      }
    }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    let scene = view.window?.windowScene
    let orientation: Int
    if #available(iOS 16.0, *) {
      orientation = scene.map { $0.effectiveGeometry.interfaceOrientation.rawValue } ?? 0
    } else { orientation = 0 }
    let geometry = "\(view.bounds):\(orientation):\(scene.map { ObjectIdentifier($0.screen).hashValue } ?? 0)"
    if geometry != lastLayoutGeometry {
      lastLayoutGeometry = geometry
      recordOrientation("layout.changed")
    }
    observeNormalDirection()
    advanceDirectionRequest()
    applyHingeOrientation()
  }

  func foldOrientationDiagnostics() -> [[String: Any]] {
    recordOrientation("diagnostics.read")
    return orientationTrace
  }

  private func recordOrientation(_ event: String, requestedMask: UInt? = nil, error: String? = nil) {
    let scene = isViewLoaded ? view.window?.windowScene : nil
    var entry: [String: Any] = [
      "time": ProcessInfo.processInfo.systemUptime,
      "event": event,
      "automatic": foldPolicy.automatic,
      "recognized": foldPolicy.foldableDisplayRecognized,
      "fullScreen": foldPolicy.playerFullScreen,
      "managedFullscreenDirection": managedFullScreenVertical != nil,
      "directionRequest": directionRequest?.id ?? 0,
      "targetOrientation": directionRequest?.target?.rawValue ?? 0,
      "deviceOrientation": UIDevice.current.orientation.rawValue,
      "hinge": foldPolicy.isHingeOpen.map { $0 ? "open" : "closed" } ?? "unknown",
      "flutterMask": super.supportedInterfaceOrientations.rawValue,
      "supportedMask": supportedInterfaceOrientations.rawValue,
      "viewBounds": isViewLoaded ? String(describing: view.bounds) : "unloaded",
    ]
    if let scene {
      if #available(iOS 16.0, *) {
        entry["orientation"] = scene.effectiveGeometry.interfaceOrientation.rawValue
      }
      entry["screen"] = ObjectIdentifier(scene.screen).hashValue
      entry["screenBounds"] = String(describing: scene.screen.bounds)
      if #available(iOS 26.0, *) {
        entry["orientationLocked"] = scene.effectiveGeometry.isInterfaceOrientationLocked
      }
    }
    if let requestedMask { entry["requestedMask"] = requestedMask }
    if let error { entry["error"] = error }
    orientationTrace.append(entry)
    if orientationTrace.count > 128 { orientationTrace.removeFirst(orientationTrace.count - 128) }
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    foldPolicy.handlesAutomaticOrientation &&
      (!foldPolicy.playerFullScreen || managedFullScreenVertical != nil)
      ? .all : super.supportedInterfaceOrientations
  }

  @available(iOS 16.0, *)
  override func setNeedsUpdateOfSupportedInterfaceOrientations() {
    super.setNeedsUpdateOfSupportedInterfaceOrientations()
    if let root = view.window?.rootViewController, root !== self {
      root.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
  }
}

// MARK: - System-managed page navigation and actions

/// UIKit owns the bar geometry, including the space below Duo's status icons.
/// Flutter keeps its own route stack and receives all button actions.
/// A transparent, noninteractive navigation item supplies UIKit's real leading
/// control position. UIKit moves it below status icons and expanded Live Activities.
@available(iOS 26.0, *)
private final class DuoNavigationAnchorView: UIView {
  var geometryChanged: (() -> Void)?
  private var lastFrame: CGRect?
  override func layoutSubviews() {
    super.layoutSubviews()
    guard let window else { return }
    let frame = convert(bounds, to: window)
    if lastFrame != frame {
      lastFrame = frame
      geometryChanged?()
    }
  }
  override func didMoveToWindow() {
    super.didMoveToWindow()
    lastFrame = nil
    setNeedsLayout()
  }
}

@available(iOS 26.0, *)
private final class DuoRailDisplayLinkTarget: NSObject {
  var tick: (() -> Void)?
  @objc func refresh() { tick?() }
}

/// Plain content inside a shared glass surface needs its own press feedback;
/// buttons with a glass configuration retain UIKit's built-in interaction.
@available(iOS 26.0, *)
private final class DuoRailGroupButton: UIButton {
  override var isHighlighted: Bool {
    didSet {
      guard isHighlighted != oldValue else { return }
      let changes = {
        self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
        self.alpha = self.isHighlighted ? 0.72 : 1
      }
      if UIAccessibility.isReduceMotionEnabled { changes() }
      else {
        UIView.animate(withDuration: isHighlighted ? 0.12 : 0.24, delay: 0,
          usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
          options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
      }
    }
  }
}

@available(iOS 26.0, *)
final class NativePageNavigationController: UINavigationController {
  // Custom UIButton symbol metrics matching the original vertical UITabBar.
  private static let actionIconPointSize: CGFloat = 18.5
  var onBack: ((@escaping () -> Void) -> Void)?
  var onPageAction: ((Int, String, @escaping () -> Void) -> Void)?
  var onCommentAction: ((Int, @escaping () -> Void) -> Void)?
  var onCommentVisibilityChange: ((Int, Bool) -> Void)?
  var onVisibilityChange: ((Bool, Bool, Bool, Bool) -> Void)?

  private var canGoBack = false
  private var playerFullScreen = false
  private var actionsOwner = 0
  private var pageActions: [[String: Any]] = []
  private var videoChrome: [String: Any]?
  private var videoNavigationEnabled = false
  private var backInFlight = false
  private var pendingActions = Set<String>()
  private var barsVisible = false
  private var backButtonVisible = false
  private var actionsVisible = false
  private var needsItemsUpdate = true
  private var homeToolsRequested = false
  private var homeToolsVisible = false
  private var renderedOwner = 0
  private var updatingBars = false
  private var commentOwner = 0
  private var commentRequested = false
  private var commentLabel = "发表评论"
  private var commentVisible = false
  private var renderedCommentOwner = 0
  private var commentInFlight = false
  private let outerVideoButtons = UIStackView()
  private let navigationAnchor = DuoNavigationAnchorView(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
  private var outerButtonsVisible = false
  private var outerVisibilityGeneration = 0
  private var placementLink: CADisplayLink?
  private var lastPresentedAnchor: CGRect?
  private var lastVideoBottom: Double?
  private var itemCache: [String: (NSDictionary, Int, UIBarButtonItem)] = [:]
  private var navigationUpdateDepth = 0
  private var leadingSignature: [[ObjectIdentifier]] = []
  private var outerCommandSignature: [String] = []
  private var outerCommandOwner = 0
  private var outerCommandButtons: [String: UIButton] = [:]
  private lazy var backItem: UIBarButtonItem = {
    let item = UIBarButtonItem(title: "返回", image: UIImage(systemName: "chevron.backward"),
      primaryAction: UIAction { [weak self] _ in self?.requestBack() })
    item.accessibilityLabel = "返回"
    item.identifier = "piliplus.navigation.back"
    return item
  }()
  private lazy var anchorItem: UIBarButtonItem = {
    let item = UIBarButtonItem(customView: navigationAnchor)
    item.hidesSharedBackground = true
    item.sharesBackground = false
    item.accessibilityElementsHidden = true
    if #available(iOS 27.0, *) { item.isPaddingRemoved = true; item.visibilityPriority = .high }
    if #available(iOS 27.1, *) { item.axisBehavior = .verticalPreferred }
    return item
  }()

  func performNavigationUpdates(_ updates: () -> Void) {
    navigationUpdateDepth += 1
    updates()
    navigationUpdateDepth -= 1
    updateBars()
  }
  private var cachedCommentItem: (Int, String, UIBarButtonItem)?
  private var renderedOuterVideo = false

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationBar.isTranslucent = true
    toolbar.isTranslucent = true
    setNavigationBarHidden(true, animated: false)
    setToolbarHidden(true, animated: false)
    outerVideoButtons.isHidden = true
    outerVideoButtons.alpha = 0
    outerVideoButtons.axis = .vertical
    outerVideoButtons.alignment = .center
    outerVideoButtons.spacing = 12
    view.addSubview(outerVideoButtons)
    navigationAnchor.accessibilityIdentifier = "piliplus.navigation.anchor"
    navigationAnchor.alpha = 0
    navigationAnchor.isUserInteractionEnabled = false
    navigationAnchor.accessibilityElementsHidden = true
    navigationAnchor.widthAnchor.constraint(equalToConstant: 44).isActive = true
    navigationAnchor.heightAnchor.constraint(equalToConstant: 44).isActive = true
    navigationAnchor.geometryChanged = { [weak self] in self?.view.setNeedsLayout() }
  }

  func setCommentAction(owner: Int, visible: Bool, label: String) {
    if commentOwner != owner || commentRequested != visible || commentLabel != label {
      needsItemsUpdate = true
    }
    commentOwner = owner
    commentRequested = visible
    commentLabel = label
    updateBars()
  }

  func setPageState(canGoBack: Bool, fullScreen: Bool) {
    self.canGoBack = canGoBack
    playerFullScreen = fullScreen
    updateBars()
  }

  func setPageActions(owner: Int, items: [[String: Any]], video: [String: Any]? = nil,
    homeTools: Bool = false, canGoBack: Bool? = nil) {
    if actionsOwner != owner || homeToolsRequested != homeTools ||
      !NSArray(array: pageActions).isEqual(to: items) { needsItemsUpdate = true }
    if let canGoBack { self.canGoBack = canGoBack }
    actionsOwner = owner
    pageActions = items
    videoChrome = video
    homeToolsRequested = homeTools
    updateBars()
  }

  private var hasVerticalBar: Bool {
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        return traitCollection.verticalBarEdge != .unspecified
      }
    #endif
    return false
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateBars()
  }

  private func updateBars() {
    guard navigationUpdateDepth == 0, !updatingBars, isViewLoaded, let content = topViewController else { return }
    updatingBars = true
    defer { updatingBars = false }
    let managesVideo = videoChrome != nil && !playerFullScreen
      && !(videoChrome?["fullScreen"] as? Bool ?? false) && hasVerticalBar && canGoBack
    let isHomeTools = homeToolsRequested && !canGoBack
    // Root tools cannot masquerade as detail-page actions during a route change.
    let pageAllowed = canGoBack && !homeToolsRequested
    let visible = hasVerticalBar && !playerFullScreen && !(videoChrome?["fullScreen"] as? Bool ?? false)
    let screenSize = view.window?.windowScene?.screen.bounds.size ?? .zero
    let innerDisplay = (content as? NativeTabBarController)?.isInnerDisplay
      ?? (min(screenSize.width, screenSize.height) >= 600)
    let outerVideo = managesVideo && !innerDisplay
    let showsBack = visible && canGoBack && (!outerVideo || videoChrome?["frame"] != nil)
    let showsComment = visible && commentRequested && commentOwner != 0
    let toolbarActions = homeToolsRequested ? [] : pageActions.filter {
      !["home", "fullscreen"].contains($0["id"] as? String ?? "")
    }
    let home = pageActions.first { ($0["id"] as? String) == "home" }
    let fullscreen = pageActions.first { ($0["id"] as? String) == "fullscreen" }
    let showsActions = visible && pageAllowed && !toolbarActions.isEmpty
    let showsHome = visible && isHomeTools
    let showsToolbar = showsActions || showsComment
    let animate = view.window != nil && !UIAccessibility.isReduceMotionEnabled
      && (needsItemsUpdate || actionsOwner != renderedOwner || visible != barsVisible
        || showsHome != homeToolsVisible || showsActions != actionsVisible
        || showsBack != backButtonVisible)
    if needsItemsUpdate || visible != barsVisible || showsHome != homeToolsVisible
      || showsBack != backButtonVisible || outerVideo != renderedOuterVideo {
      needsItemsUpdate = false
      content.navigationItem.hidesBackButton = true
      content.navigationItem.leftItemsSupplementBackButton = false
      var leadingItems: [[UIBarButtonItem]] = []
      if showsHome {
        leadingItems = pageActions.map { [makeActionItem($0, owner: actionsOwner)] }
      } else if showsBack && !outerVideo {
        var navigationItems = [backItem]
        if let home { navigationItems.append(makeActionItem(home, owner: actionsOwner)) }
        leadingItems.append(navigationItems)
        if let fullscreen { leadingItems.append([makeActionItem(fullscreen, owner: actionsOwner)]) }
      }
      if outerVideo {
        leadingItems = [[anchorItem]]
        let commandSignature = [home, fullscreen].compactMap { $0?["id"] as? String }
        if commandSignature != outerCommandSignature {
        outerCommandSignature = commandSignature
        outerCommandButtons.removeAll()
        for item in outerVideoButtons.arrangedSubviews {
          outerVideoButtons.removeArrangedSubview(item)
          item.removeFromSuperview()
        }
        let navigationGroup = UIVisualEffectView(effect: {
          let glass = UIGlassEffect(style: .regular)
          glass.isInteractive = true
          return glass
        }())
        navigationGroup.accessibilityIdentifier = "piliplus.navigation.group"
        navigationGroup.layer.cornerRadius = 22
        navigationGroup.clipsToBounds = true
        let groupStack = UIStackView()
        groupStack.axis = .vertical
        groupStack.addArrangedSubview(makeRailButton(title: "返回", symbol: "chevron.backward", glass: false) { [weak self] in self?.requestBack() })
        func commandButton(_ descriptor: [String: Any], glass: Bool) -> UIButton {
          let id = descriptor["id"] as? String ?? ""
          let button = makeRailButton(title: descriptor["title"] as? String ?? "",
            symbol: id == "home" ? "house" : "arrow.up.left.and.arrow.down.right", glass: glass) {}
          button.removeTarget(nil, action: nil, for: .touchUpInside)
          outerCommandButtons[id] = button
          return button
        }
        if let home { groupStack.addArrangedSubview(commandButton(home, glass: false)) }
        groupStack.translatesAutoresizingMaskIntoConstraints = false
        navigationGroup.contentView.addSubview(groupStack)
        NSLayoutConstraint.activate([
          navigationGroup.widthAnchor.constraint(equalToConstant: 44),
          navigationGroup.heightAnchor.constraint(equalToConstant: CGFloat(groupStack.arrangedSubviews.count) * 44),
          groupStack.leadingAnchor.constraint(equalTo: navigationGroup.contentView.leadingAnchor),
          groupStack.trailingAnchor.constraint(equalTo: navigationGroup.contentView.trailingAnchor),
          groupStack.topAnchor.constraint(equalTo: navigationGroup.contentView.topAnchor),
          groupStack.bottomAnchor.constraint(equalTo: navigationGroup.contentView.bottomAnchor),
        ])
        outerVideoButtons.addArrangedSubview(navigationGroup)
        if let fullscreen { outerVideoButtons.addArrangedSubview(commandButton(fullscreen, glass: true)) }
        outerCommandOwner = 0
        }
        if outerCommandOwner != actionsOwner {
          outerCommandOwner = actionsOwner
          let owner = actionsOwner
          for (id, button) in outerCommandButtons {
            button.removeAction(identifiedBy: .init("piliplus.command"), for: .touchUpInside)
            button.addAction(UIAction(identifier: .init("piliplus.command")) { [weak self] _ in
              guard let self, self.barsVisible, self.renderedOuterVideo, self.actionsOwner == owner else { return }
              let key = "\(owner):\(id)"
              guard self.pendingActions.insert(key).inserted else { return }
              self.onPageAction?(owner, id) { [weak self] in self?.pendingActions.remove(key) }
            }, for: .touchUpInside)
          }
        }
        for descriptor in [home, fullscreen].compactMap({ $0 }) {
          if let id = descriptor["id"] as? String {
            outerCommandButtons[id]?.isEnabled = descriptor["enabled"] as? Bool ?? true
          }
        }
      }

      let signature = leadingItems.map { $0.map(ObjectIdentifier.init) }
      if signature != leadingSignature {
        leadingSignature = signature
        content.navigationItem.leadingItemGroups = leadingItems.map {
          .fixedGroup(representativeItem: nil, items: $0)
        }
      }
      var items = showsActions ? toolbarActions.map { makeActionItem($0, owner: actionsOwner) } : []
      if showsComment { items.append(makeCommentItem()) }
      let previous = (content.toolbarItems ?? []).filter { $0.identifier != "piliplus.toolbar.space" }
      if previous.map(ObjectIdentifier.init) != items.map(ObjectIdentifier.init) {
        let space = UIBarButtonItem(systemItem: .flexibleSpace)
        space.identifier = "piliplus.toolbar.space"
        content.setToolbarItems(items.isEmpty ? nil : [space] + items, animated: animate)
      }
      #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
          content.navigationItem.verticalBarCompressionBehavior = .prefersBarItems
        }
      #endif
    }
    let changed = visible != barsVisible || showsActions != actionsVisible
      || managesVideo != videoNavigationEnabled || showsHome != homeToolsVisible
      || showsBack != backButtonVisible
    renderedOwner = actionsOwner
    barsVisible = visible
    backButtonVisible = showsBack
    actionsVisible = showsActions
    videoNavigationEnabled = managesVideo
    homeToolsVisible = showsHome
    renderedOuterVideo = outerVideo
    let navigationVisible = visible
    if isNavigationBarHidden == navigationVisible {
      setNavigationBarHidden(!navigationVisible, animated: animate)
    }
    if isToolbarHidden == showsToolbar {
      setToolbarHidden(!showsToolbar, animated: animate)
    }
    updateOuterVideoButtons(visible: outerVideo && showsBack)
    if showsComment != commentVisible || renderedCommentOwner != commentOwner {
      commentVisible = showsComment
      renderedCommentOwner = commentOwner
      onCommentVisibilityChange?(commentOwner, showsComment)
    }
    if changed { onVisibilityChange?(showsBack, showsActions, managesVideo, showsHome) }
  }

  private func requestBack() {
    guard barsVisible, canGoBack, !backInFlight else { return }
    backInFlight = true
    onBack? { [weak self] in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        self?.backInFlight = false
      }
    }
  }

  private func makeRailButton(title: String, symbol: String, glass: Bool = true, action: @escaping () -> Void) -> UIButton {
    var configuration = glass ? UIButton.Configuration.glass() : .plain()
    configuration.cornerStyle = .capsule
    configuration.contentInsets = .zero
    configuration.image = UIImage(systemName: symbol)
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: Self.actionIconPointSize)
    let button = glass ? UIButton(configuration: configuration) : DuoRailGroupButton(type: .system)
    button.configuration = configuration
    button.accessibilityLabel = title
    button.widthAnchor.constraint(equalToConstant: 44).isActive = true
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    return button
  }

  private func trackSystemNavigation(_ enabled: Bool) {
    if !enabled {
      placementLink?.invalidate()
      placementLink = nil
      lastPresentedAnchor = nil
      return
    }
    guard placementLink == nil else { return }
    let target = DuoRailDisplayLinkTarget()
    target.tick = { [weak self] in
      guard let self else { return }
      guard self.navigationAnchor.window != nil else { self.setOuterButtonsVisible(false); return }
      let frame: CGRect
      if let source = self.navigationAnchor.layer.presentation(), let destination = self.view.layer.presentation() {
        frame = source.convert(self.navigationAnchor.bounds, to: destination)
      } else {
        frame = self.navigationAnchor.convert(self.navigationAnchor.bounds, to: self.view)
      }
      if self.lastPresentedAnchor != frame {
        self.lastPresentedAnchor = frame
        self.updateOuterVideoButtons(visible: true, presentedAnchor: frame)
      }
    }
    let link = CADisplayLink(target: target, selector: #selector(DuoRailDisplayLinkTarget.refresh))
    link.preferredFrameRateRange = CAFrameRateRange(minimum: 10, maximum: 60, preferred: 60)
    link.add(to: .main, forMode: .common)
    placementLink = link
  }

  deinit { placementLink?.invalidate() }

  private func setOuterButtonsVisible(_ visible: Bool) {
    guard outerButtonsVisible != visible else { return }
    outerButtonsVisible = visible
    trackSystemNavigation(visible)
    outerVisibilityGeneration += 1
    let generation = outerVisibilityGeneration
    outerVideoButtons.isUserInteractionEnabled = visible
    if visible {
      outerVideoButtons.isHidden = false
      outerVideoButtons.alpha = 0
    }
    let changes = { self.outerVideoButtons.alpha = visible ? 1 : 0 }
    if view.window == nil || UIAccessibility.isReduceMotionEnabled {
      changes()
      outerVideoButtons.isHidden = !visible
    } else {
      UIView.animate(withDuration: 0.25, delay: 0,
        options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
        animations: changes) { [weak self] _ in
          guard let self, self.outerVisibilityGeneration == generation else { return }
          self.outerVideoButtons.isHidden = !visible
        }
    }
  }

  private func updateOuterVideoButtons(visible: Bool, presentedAnchor: CGRect? = nil) {
    guard visible, let frame = videoChrome?["frame"] as? [String: Double],
      let bottom = frame["bottom"], let right = frame["right"], bottom.isFinite, right.isFinite else {
      setOuterButtonsVisible(false)
      return
    }
    let bounds = view.bounds
    if let aspect = frame["aspect"], abs(aspect - bounds.width / max(1, bounds.height)) > 0.03 {
      setOuterButtonsVisible(false)
      return
    }
    let rail = max(72, max(view.safeAreaInsets.right, topViewController?.view.safeAreaInsets.right ?? 0))
    let height = outerVideoButtons.systemLayoutSizeFitting(
      CGSize(width: 44, height: UIView.layoutFittingCompressedSize.height),
      withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
    let intersectsVideo = right * bounds.width > bounds.width - rail
    guard let window = navigationAnchor.window, window == view.window,
      !navigationAnchor.bounds.isEmpty else {
      setOuterButtonsVisible(false)
      return
    }
    let anchorFrame = presentedAnchor ?? navigationAnchor.convert(navigationAnchor.bounds, to: view)
    // No fixed status height: the system anchor already avoids the camera,
    // status icons, and the current expanded/compact Dynamic Island.
    let y = max(anchorFrame.minY, intersectsVideo ? bottom * bounds.height + 8 : 0)
    let target = CGRect(x: bounds.width - max(48, rail / 2) - 22, y: y, width: 44, height: height)
    let videoMoved = lastVideoBottom != bottom
    lastVideoBottom = bottom
    if outerVideoButtons.frame != target {
      let changes = { self.outerVideoButtons.frame = target }
      if presentedAnchor != nil || videoMoved {
        // Both sources already animate frame by frame. Follow their displayed
        // positions directly, so a second tween cannot lag into the video or island.
        outerVideoButtons.layer.removeAnimation(forKey: "position")
        outerVideoButtons.layer.removeAnimation(forKey: "bounds")
        UIView.performWithoutAnimation(changes)
      } else if outerButtonsVisible && !UIAccessibility.isReduceMotionEnabled {
        if let coordinator = transitionCoordinator {
          coordinator.animate(alongsideTransition: { _ in changes() })
        } else {
          let duration = UIView.inheritedAnimationDuration > 0 ? UIView.inheritedAnimationDuration : 0.25
          UIView.animate(withDuration: duration, delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut], animations: changes)
        }
      } else { changes() }
    }
    setOuterButtonsVisible(true)
    view.bringSubviewToFront(outerVideoButtons)
  }

  private func makeCommentItem() -> UIBarButtonItem {
    if let cached = cachedCommentItem, cached.0 == commentOwner, cached.1 == commentLabel { return cached.2 }
    let owner = commentOwner
    let descriptor: [String: Any] = ["id": "compose", "title": commentLabel]
    let handler: UIActionHandler = { [weak self] _ in
      guard let self, self.commentVisible, self.commentOwner == owner, !self.commentInFlight else { return }
      self.commentInFlight = true
      self.onCommentAction?(owner) { [weak self] in
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { self?.commentInFlight = false }
      }
    }
    let image = UIImage(systemName: "square.and.pencil")
    let item: UIBarButtonItem
    if let cached = cachedCommentItem, cached.1 == commentLabel {
      item = cached.2
      rebind(item, action: UIAction(title: commentLabel, image: image, handler: handler), handler: handler)
    } else {
      item = makeHomeToolItem(descriptor, image: image, handler: handler)
    }
    item.identifier = "piliplus.comment.compose"
    cachedCommentItem = (owner, commentLabel, item)
    if #available(iOS 27.0, *) { item.visibilityPriority = .high }
    if #available(iOS 27.1, *) { item.axisBehavior = .verticalPreferred }
    return item
  }

  private func makeActionItem(_ descriptor: [String: Any], owner: Int) -> UIBarButtonItem {
    let id = descriptor["id"] as? String ?? ""
    let cacheKey = id
    let signature = NSDictionary(dictionary: descriptor)
    let title = descriptor["title"] as? String ?? ""
    let count = descriptor["count"] as? String
    let selected = descriptor["selected"] as? Bool ?? false
    let enabled = descriptor["enabled"] as? Bool ?? true
    let symbol: String
    switch id {
    case "search": symbol = "magnifyingglass"
    case "notifications": symbol = "bell"
    case "home": symbol = "house"
    case "fullscreen": symbol = "arrow.up.left.and.arrow.down.right"
    case "scrollToTop": symbol = "arrow.up.to.line"
    case "like": symbol = selected ? "hand.thumbsup.fill" : "hand.thumbsup"
    case "comment": symbol = "bubble.right"
    case "repost": symbol = "arrowshape.turn.up.right"
    case "share": symbol = "square.and.arrow.up"
    case "compose": symbol = "square.and.pencil"
    default: symbol = "ellipsis"
    }
    let handler: UIActionHandler = { [weak self] _ in
      guard let self, self.barsVisible, self.actionsOwner == owner else { return }
      let key = "\(owner):\(id)"
      guard self.pendingActions.insert(key).inserted else { return }
      self.onPageAction?(owner, id) { [weak self] in self?.pendingActions.remove(key) }
    }
    let action = UIAction(title: title, image: UIImage(systemName: symbol), handler: handler)
    if let cached = itemCache[cacheKey], cached.0 == signature {
      if cached.1 != owner { rebind(cached.2, action: action, handler: handler) }
      itemCache[cacheKey] = (signature, owner, cached.2)
      return cached.2
    }
    var item = UIBarButtonItem(title: title, image: action.image, primaryAction: action)
    if ["search", "notifications", "scrollToTop"].contains(id) {
      item = makeHomeToolItem(descriptor, image: action.image, handler: handler)
    } else if let count {
      // Keep count-bearing items compact, with a meaningful overflow title.
      // The system bar supplies the shared glass background, so the content
      // button is plain rather than another nested glass surface.
      var configuration = UIButton.Configuration.plain()
      configuration.image = action.image
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: Self.actionIconPointSize)
      configuration.title = count
      configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var attributes = $0
        attributes.font = UIFont.preferredFont(forTextStyle: .caption1)
        return attributes
      }
      configuration.imagePlacement = .top
      configuration.imagePadding = 3
      configuration.contentInsets = .zero
      configuration.baseForegroundColor = selected ? .systemPink : .label
      let button = DuoRailGroupButton(type: .system)
      button.configuration = configuration
      // A primaryAction would replace the short count with its menu title.
      button.addAction(UIAction(identifier: .init("piliplus.item"), handler: handler), for: .touchUpInside)
      button.accessibilityLabel = "\(title)，\(count)"
      button.isEnabled = enabled
      button.accessibilityTraits = selected ? [.button, .selected] : .button
      button.frame = CGRect(x: 0, y: 0, width: 44, height: 56)
      button.widthAnchor.constraint(equalToConstant: 44).isActive = true
      button.heightAnchor.constraint(equalToConstant: 56).isActive = true
      let container = UIView(frame: button.frame)
      container.addSubview(button)
      container.widthAnchor.constraint(equalToConstant: 44).isActive = true
      container.heightAnchor.constraint(equalToConstant: 56).isActive = true
      item = UIBarButtonItem(customView: container)
      item.title = title
      item.menuRepresentation = action
    }
    item.identifier = "piliplus.action.\(id)"
    item.isEnabled = enabled
    item.accessibilityLabel = count.map { "\(title)，\($0)" } ?? item.accessibilityLabel ?? title
    item.sharesBackground = !["compose", "search", "notifications", "scrollToTop"].contains(id)
    #if compiler(>=6.4)
      if #available(iOS 27.0, *) {
        // Keep the two independent affordances ahead of count-bearing groups
        // when the inner display's short vertical bar needs an overflow menu.
        item.visibilityPriority = ["home", "fullscreen", "search", "notifications", "scrollToTop"].contains(id) ? .high : .low
      }
      if #available(iOS 27.1, *) { item.axisBehavior = .verticalPreferred }
    #endif
    item.tintColor = selected ? .systemPink : nil
    itemCache[cacheKey] = (signature, owner, item)
    return item
  }

  private func rebind(_ item: UIBarButtonItem, action: UIAction, handler: @escaping UIActionHandler) {
    if let button = item.customView?.subviews.compactMap({ $0 as? UIButton }).first {
      button.removeAction(identifiedBy: .init("piliplus.item"), for: .touchUpInside)
      button.addAction(UIAction(identifier: .init("piliplus.item"), handler: handler), for: .touchUpInside)
      item.menuRepresentation = action
    } else {
      item.primaryAction = action
    }
  }

  private func makeHomeToolItem(_ descriptor: [String: Any], image: UIImage?,
    handler: @escaping UIActionHandler) -> UIBarButtonItem {
    let title = descriptor["title"] as? String ?? ""
    var configuration = UIButton.Configuration.glass()
    configuration.cornerStyle = .capsule
    configuration.contentInsets = .zero
    configuration.image = image
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(pointSize: Self.actionIconPointSize)
    let button = UIButton(configuration: configuration)
    button.addAction(UIAction(identifier: .init("piliplus.item"), handler: handler), for: .touchUpInside)
    button.accessibilityLabel = title
    button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
    button.widthAnchor.constraint(equalToConstant: 44).isActive = true
    button.heightAnchor.constraint(equalToConstant: 44).isActive = true
    if let badge = descriptor["badge"] as? String {
      button.accessibilityLabel = badge.isEmpty ? "消息，有未读消息" : "消息，\(badge)条未读"
    }
    let container = UIView(frame: button.frame)
    container.addSubview(button)
    container.widthAnchor.constraint(equalToConstant: 44).isActive = true
    container.heightAnchor.constraint(equalToConstant: 44).isActive = true
    let item = UIBarButtonItem(customView: container)
    // The bar must not draw another capsule around our square glass button.
    item.hidesSharedBackground = true
    if #available(iOS 27.0, *) { item.isPaddingRemoved = true }
    item.title = title
    item.accessibilityLabel = button.accessibilityLabel
    item.menuRepresentation = UIAction(title: title, image: image, handler: handler)
    if let badge = descriptor["badge"] as? String {
      item.badge = badge.isEmpty ? .indicator() : .string(badge)
    }
    return item
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    topViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
  }
  override var childForStatusBarStyle: UIViewController? { topViewController }
  override var childForStatusBarHidden: UIViewController? { topViewController }
  override var childForHomeIndicatorAutoHidden: UIViewController? { topViewController }
}
