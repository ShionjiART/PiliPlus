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
      var root: UIViewController = tabs
      // iPhone Duo (iOS 27.1 SDK): a navigation controller around the tabs lets
      // pages put their own buttons, such as back, in the vertical bar. Its
      // bars stay hidden on devices without a vertical bar.
      #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
          let navigation = NativePageNavigationController(rootViewController: tabs)
          navigation.onBack = { [weak tabs] completion in
            tabs?.requestBack(completion: completion)
          }
          navigation.onPageAction = { [weak tabs] owner, id, completion in
            tabs?.requestPageAction(owner: owner, id: id, completion: completion)
          }
          navigation.onVisibilityChange = { [weak tabs] back, actions in
            tabs?.publishBarVisibility(back: back, actions: actions)
          }
          navigation.onTool = { [weak tabs] id, completion in
            tabs?.requestTool(id, completion: completion)
          }
          navigation.onToolsShownChange = { [weak tabs] shown in
            tabs?.publishToolsShown(shown)
          }
          navigation.onBackAvailableChange = { [weak tabs] available in
            tabs?.publishBackAvailable(available)
          }
          root = navigation
        }
      #endif
      window.rootViewController = root
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

  private var navigationHost: NativePageNavigationController? {
    navigationController as? NativePageNavigationController
  }

  func requestBack(completion: @escaping () -> Void) {
    channel?.invokeMethod("back", arguments: nil) { _ in completion() }
  }

  func requestPageAction(owner: Int, id: String, completion: @escaping () -> Void) {
    channel?.invokeMethod("pageAction", arguments: ["owner": owner, "id": id]) { _ in
      completion()
    }
  }

  func publishBarVisibility(back: Bool, actions: Bool) {
    channel?.invokeMethod("backButtonVisible", arguments: back)
    channel?.invokeMethod("pageActionsVisible", arguments: actions)
  }

  private func makeHost() -> FlutterHostViewController {
    let host = FlutterHostViewController()
    host.onSafeAreaChange = { [weak self, weak host] insets in
      guard let self else { return }
      var insets = insets
      // iPhone Duo: UIKit moves the navigation bar into the vertical bar but
      // still adds its height to the top safe area. Nothing is drawn there, so
      // keep the window's own top inset and the page does not move down.
      if let window = host?.view.window {
        insets.top = min(insets.top, window.safeAreaInsets.top)
      }
      guard insets != self.safeArea else { return }
      self.safeArea = insets
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
      // The top page, whether it can go back, and its buttons; sent by Dart
      // once per frame after route changes.
      if let page = (call.arguments as? [String: Any])?["page"] as? [String: Any] {
        navigationHost?.setPage(
          owner: page["owner"] as? Int ?? 0,
          items: page["items"] as? [[String: Any]] ?? [],
          canGoBack: page["canGoBack"] as? Bool ?? false)
      }
      result(nil)
    case "getSafeArea":
      result(Self.encode(safeArea))
    case "getBackAvailable":
      result(navigationHost?.backAvailable ?? false)
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
      setTabBarHidden(false, animated: false)
      result(true)
    case "setTools":
      navigationHost?.setTools(call.arguments as? [[String: Any]] ?? [])
      result(nil)
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
      setTabBarHidden(call.arguments as? Bool ?? false, animated: true)
      result(nil)
    case "setHidesVerticalBar":
      hidesVerticalBar = call.arguments as? Bool ?? false
      // Reply with the actual state so Dart can correct itself if it missed a
      // `verticalBarHidden` notification.
      result(isVerticalBarHidden)
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

  func requestTool(_ id: String, completion: @escaping () -> Void) {
    channel?.invokeMethod("toolAction", arguments: id) { _ in completion() }
  }

  func publishToolsShown(_ shown: Bool) {
    channel?.invokeMethod("toolsShown", arguments: shown)
  }

  func publishBackAvailable(_ available: Bool) {
    channel?.invokeMethod("backAvailable", arguments: available)
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

  // iPhone Duo: pages such as the video page hide the status bar while it is
  // in the vertical bar, so their content can fill the bar's space. Elsewhere
  // the status bar is on top and Flutter keeps controlling it. The bar's safe
  // area stays when the status bar is hidden, so Dart is told to lay out over
  // it.
  private var hidesVerticalBar = false {
    didSet { verticalBarDidChange() }
  }
  private var hasVerticalBar = false {
    didSet { verticalBarDidChange() }
  }
  private var isVerticalBarHidden: Bool { hidesVerticalBar && hasVerticalBar }
  private var sentVerticalBarHidden = false

  private func verticalBarDidChange() {
    UIView.animate(withDuration: 0.25) { self.setNeedsStatusBarAppearanceUpdate() }
    // Pages that hide the vertical bar (the video page) fill its space, so its
    // buttons go away with it.
    navigationHost?.setVerticalBarHidden(isVerticalBarHidden)
    if isVerticalBarHidden != sentVerticalBarHidden {
      sentVerticalBarHidden = isVerticalBarHidden
      channel?.invokeMethod("verticalBarHidden", arguments: isVerticalBarHidden)
    }
  }

  override var childForStatusBarHidden: UIViewController? {
    isVerticalBarHidden ? nil : super.childForStatusBarHidden
  }

  override var prefersStatusBarHidden: Bool {
    isVerticalBarHidden ? true : super.prefersStatusBarHidden
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    // The vertical bar edge stays set while the status bar is hidden, and
    // changes when the device folds or unfolds.
    var hasVerticalBar = false
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        hasVerticalBar = traitCollection.verticalBarEdge != .unspecified
      }
    #endif
    if hasVerticalBar != self.hasVerticalBar {
      self.hasVerticalBar = hasVerticalBar
    }
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

/// A custom view in a bar item gets no press feedback from the system, so the
/// button shrinks and fades a little while held, like the system bar items.
private final class RailPressButton: UIButton {
  override var isHighlighted: Bool {
    didSet {
      guard isHighlighted != oldValue else { return }
      let pressed = isHighlighted
      let changes = {
        self.transform = pressed ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
        self.alpha = pressed ? 0.6 : 1
      }
      if UIAccessibility.isReduceMotionEnabled {
        changes()
      } else {
        UIView.animate(
          withDuration: pressed ? 0.12 : 0.3, delay: 0, usingSpringWithDamping: 0.7,
          initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction],
          animations: changes)
      }
    }
  }
}

/// iPhone Duo: wraps the tabs so pages can put their own buttons in the
/// vertical bar through the navigation bar, which UIKit moves into the vertical
/// bar: a back button on secondary pages, which replaces the back button
/// Flutter's app bars would add. The bars are hidden on devices without a
/// vertical bar and while a page hides the vertical bar (the video page).
///
/// Dart decides which page is on top and whether it can go back
/// (`setNavigationState`); taps go back to Dart, so this controller never
/// pushes or pops view controllers itself.
@available(iOS 26.0, *)
final class NativePageNavigationController: UINavigationController {
  var onBack: ((@escaping () -> Void) -> Void)?
  var onPageAction: ((Int, String, @escaping () -> Void) -> Void)?
  var onVisibilityChange: ((_ back: Bool, _ actions: Bool) -> Void)?
  var onTool: ((String, @escaping () -> Void) -> Void)?
  /// Whether the vertical bar has the tools, so the page can drop its own
  /// copy (the home page's avatar).
  var onToolsShownChange: ((Bool) -> Void)?
  /// Whether secondary pages get the back button in the vertical bar, so
  /// their app bars leave theirs out. Follows the vertical bar only, not the
  /// video page hiding it: pages under the video page keep their layout.
  var onBackAvailableChange: ((Bool) -> Void)?
  private(set) var backAvailable = false

  // Search, notifications and the avatar: shown at the top of the vertical bar
  // on root pages, where secondary pages show the back button.
  private var toolGroups: [[UIBarButtonItem]] = []
  private var toolCache: [String: UIBarButtonItem] = [:]
  private var toolInFlight = false
  private var toolsShown: Bool?
  private var avatarURL: String?
  private var avatarTask: URLSessionDataTask?

  private var canGoBack = false
  private var actionsOwner = 0
  private var pageActions: [[String: Any]] = []
  private var verticalBarHidden = false
  private var backInFlight = false
  private var barsVisible = false
  private var backButtonVisible = false
  private var actionsVisible = false
  private var updatingBars = false
  private var leadingSignature: [[ObjectIdentifier]] = []

  private lazy var backItem: UIBarButtonItem = {
    let item = UIBarButtonItem(
      title: "返回", image: UIImage(systemName: "chevron.backward"),
      primaryAction: UIAction { [weak self] _ in self?.requestBack() })
    item.accessibilityLabel = "返回"
    item.identifier = "piliplus.navigation.back"
    return item
  }()

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationBar.isTranslucent = true
    setNavigationBarHidden(true, animated: false)
    setToolbarHidden(true, animated: false)
    // There is only ever one view controller; Flutter handles edge swipes.
    interactivePopGestureRecognizer?.isEnabled = false
    // The vertical bar edge is a trait, and a trait change need not come with
    // a layout pass, so the bars would keep their old state after folding or
    // unfolding.
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        registerForTraitChanges(UITraitCollection.systemTraitsAffectingVerticalBarEdge) {
          (self: NativePageNavigationController, _) in
          self.updateBars()
        }
      }
    #endif
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    updateBars()
  }

  func setPage(owner: Int, items: [[String: Any]], canGoBack: Bool) {
    actionsOwner = owner
    pageActions = items
    self.canGoBack = canGoBack
    updateBars()
  }

  func setVerticalBarHidden(_ hidden: Bool) {
    guard hidden != verticalBarHidden else { return }
    verticalBarHidden = hidden
    updateBars()
  }

  /// Each tool: `id`, `title`, an SF Symbol name in `symbol`, an optional
  /// `badge` (empty for a dot) and an optional `image` URL drawn as a circle.
  func setTools(_ descriptors: [[String: Any]]) {
    var seen = Set<String>()
    var groups: [[UIBarButtonItem]] = []
    var lastGroup: String?
    for descriptor in descriptors {
      guard let id = descriptor["id"] as? String, !id.isEmpty, seen.insert(id).inserted
      else { continue }
      let item = toolCache[id] ?? makeToolItem(id)
      toolCache[id] = item
      let title = descriptor["title"] as? String
      item.title = title
      item.accessibilityLabel = title
      if let url = descriptor["image"] as? String, !url.isEmpty {
        loadAvatar(url, into: item, placeholder: descriptor["symbol"] as? String)
      } else {
        if item === avatarItem { cancelAvatar() }
        item.image = UIImage(systemName: descriptor["symbol"] as? String ?? "circle")
      }
      if let badge = descriptor["badge"] as? String {
        item.badge = badge.isEmpty ? .indicator() : .string(badge)
      } else {
        item.badge = nil
      }
      // Adjacent tools of the same group share one button in the bar.
      let group = descriptor["group"] as? String
      if group != nil, group == lastGroup, !groups.isEmpty {
        groups[groups.count - 1].append(item)
      } else {
        groups.append([item])
      }
      lastGroup = group
    }
    // A lone item would otherwise share its background with the next group
    // (the avatar and search look like one button while logged out).
    for group in groups {
      for item in group { item.sharesBackground = group.count > 1 }
    }
    toolGroups = groups
    updateBars()
  }

  private weak var avatarItem: UIBarButtonItem?

  private func makeToolItem(_ id: String) -> UIBarButtonItem {
    let item = UIBarButtonItem(
      title: nil, image: nil,
      primaryAction: UIAction { [weak self] _ in self?.requestTool(id) })
    item.identifier = "piliplus.navigation.tool.\(id)"
    return item
  }

  private func loadAvatar(_ url: String, into item: UIBarButtonItem, placeholder: String?) {
    avatarItem = item
    guard url != avatarURL else { return }
    cancelAvatar()
    avatarURL = url
    if item.image == nil, let placeholder { item.image = UIImage(systemName: placeholder) }
    guard let source = URL(string: url) else { return }
    avatarTask = URLSession.shared.dataTask(with: source) { [weak self, weak item] data, _, _ in
      guard let data, let image = UIImage(data: data) else { return }
      let size = CGSize(width: 30, height: 30)
      let circle = UIGraphicsImageRenderer(size: size).image { _ in
        UIBezierPath(ovalIn: CGRect(origin: .zero, size: size)).addClip()
        // Fill the circle, cropping the longer side.
        let scale = max(size.width / image.size.width, size.height / image.size.height)
        let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(
          x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
          width: drawn.width, height: drawn.height))
      }.withRenderingMode(.alwaysOriginal)
      DispatchQueue.main.async {
        guard let self, self.avatarURL == url else { return }
        item?.image = circle
      }
    }
    avatarTask?.resume()
  }

  private func cancelAvatar() {
    avatarTask?.cancel()
    avatarTask = nil
    avatarURL = nil
  }

  private func requestTool(_ id: String) {
    guard barsVisible, !canGoBack, !toolInFlight else { return }
    // One page per tap, as with the back button.
    toolInFlight = true
    onTool?(id) { [weak self] in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        self?.toolInFlight = false
      }
    }
  }

  private var hasVerticalBar: Bool {
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        return traitCollection.verticalBarEdge != .unspecified
      }
    #endif
    return false
  }

  private func updateBars() {
    guard !updatingBars, isViewLoaded, let content = topViewController else { return }
    updatingBars = true
    defer { updatingBars = false }

    let visible = hasVerticalBar && !verticalBarHidden
    let showsBack = visible && canGoBack
    let showsTools = visible && !canGoBack && !toolGroups.isEmpty
    let leadingItems: [[UIBarButtonItem]] =
      showsBack ? [[backItem]] : showsTools ? toolGroups : []
    let signature = leadingItems.map { $0.map(ObjectIdentifier.init) }
    // UIKit rebuilds the navigation bar, and drops these groups, when the
    // scene moves between the inner and outer display, so compare with what it
    // actually holds rather than only with what was last set.
    let realized = content.navigationItem.leadingItemGroups.map {
      $0.barButtonItems.map(ObjectIdentifier.init)
    }
    if signature != leadingSignature || realized != signature {
      leadingSignature = signature
      content.navigationItem.hidesBackButton = true
      content.navigationItem.leadingItemGroups = leadingItems.map {
        .fixedGroup(representativeItem: nil, items: $0)
      }
      #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
          content.navigationItem.verticalBarCompressionBehavior = .prefersBarItems
        }
      #endif
    }

    // Keep the navigation bar shown on every page while there is a vertical
    // bar, so pushing and popping does not change the safe area.
    if isNavigationBarHidden == visible {
      let animate = view.window != nil && !UIAccessibility.isReduceMotionEnabled
      setNavigationBarHidden(!visible, animated: animate)
    }
    // The page's own buttons go in the toolbar, which UIKit puts in the lower
    // part of the vertical bar; secondary pages have no tab bar there.
    let showsActions = visible && !pageActions.isEmpty
    // UIKit rebuilds the vertical bar for the other display when the device
    // folds or unfolds, and the custom views of the count buttons do not come
    // along: the bar shows an empty group. Make new items for the new display.
    let displaySize = view.window?.bounds.size
    if displaySize != actionDisplaySize {
      actionDisplaySize = displaySize
      actionCache.removeAll()
    }
    let actionItems = showsActions ? pageActions.compactMap(makeActionItem) : []
    let currentItems = (content.toolbarItems ?? []).filter {
      $0.identifier != Self.toolbarSpaceID
    }
    if currentItems.map(ObjectIdentifier.init) != actionItems.map(ObjectIdentifier.init) {
      let space = UIBarButtonItem(systemItem: .flexibleSpace)
      space.identifier = Self.toolbarSpaceID
      content.setToolbarItems(actionItems.isEmpty ? nil : [space] + actionItems, animated: false)
    }
    if isToolbarHidden == showsActions {
      let animate = view.window != nil && !UIAccessibility.isReduceMotionEnabled
      setToolbarHidden(!showsActions, animated: animate)
    }
    let changed = showsBack != backButtonVisible || showsActions != actionsVisible
    barsVisible = visible
    backButtonVisible = showsBack
    actionsVisible = showsActions
    if changed { onVisibilityChange?(showsBack, showsActions) }
    // Not tied to the current page or the video page hiding the bar, so the
    // home page does not change layout while it is covered.
    let toolsAvailable = hasVerticalBar && !toolGroups.isEmpty
    if toolsAvailable != toolsShown {
      toolsShown = toolsAvailable
      onToolsShownChange?(toolsAvailable)
    }
    if hasVerticalBar != backAvailable {
      backAvailable = hasVerticalBar
      onBackAvailableChange?(hasVerticalBar)
    }
  }

  private static let toolbarSpaceID = "piliplus.toolbar.space"
  private var actionCache: [String: (NSDictionary, UIBarButtonItem)] = [:]
  private var actionDisplaySize: CGSize?
  private var actionsInFlight = Set<String>()

  /// A page button. With a `count`, a compact button with the icon on top and
  /// the count below, so it fits the vertical bar's width.
  private func makeActionItem(_ descriptor: [String: Any]) -> UIBarButtonItem? {
    guard let id = descriptor["id"] as? String, !id.isEmpty else { return nil }
    let owner = actionsOwner
    var signature = descriptor
    signature["owner"] = owner
    let key = NSDictionary(dictionary: signature)
    if let cached = actionCache[id], cached.0 == key { return cached.1 }

    let title = descriptor["title"] as? String ?? ""
    let count = descriptor["count"] as? String
    let selected = descriptor["selected"] as? Bool ?? false
    let enabled = descriptor["enabled"] as? Bool ?? true
    let color: UIColor? =
      selected ? (descriptor["selectedColor"] as? Int).map(Self.color(argb:)) ?? .tintColor : nil
    let image = UIImage(systemName: Self.actionSymbol(id, selected: selected))
    let handler: UIActionHandler = { [weak self] _ in
      self?.requestPageAction(owner: owner, id: id)
    }
    let item: UIBarButtonItem
    if let count {
      var configuration = UIButton.Configuration.plain()
      configuration.image = image
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: 18.5)
      configuration.title = count
      configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
        var attributes = $0
        attributes.font = UIFont.preferredFont(forTextStyle: .caption1)
        return attributes
      }
      configuration.titleLineBreakMode = .byClipping
      configuration.imagePlacement = .top
      configuration.imagePadding = 3
      configuration.contentInsets = .zero
      configuration.baseForegroundColor = color ?? .label
      // Not a primaryAction: its title would replace the count.
      let button = RailPressButton(configuration: configuration, primaryAction: nil)
      button.addAction(UIAction(handler: handler), for: .touchUpInside)
      button.isEnabled = enabled
      button.accessibilityLabel = "\(title)，\(count)"
      button.accessibilityTraits = selected ? [.button, .selected] : .button
      let size = CGSize(width: 44, height: 56)
      button.frame = CGRect(origin: .zero, size: size)
      let container = UIView(frame: button.frame)
      container.addSubview(button)
      container.widthAnchor.constraint(equalToConstant: size.width).isActive = true
      container.heightAnchor.constraint(equalToConstant: size.height).isActive = true
      item = UIBarButtonItem(customView: container)
      // Shown when the bar is too short and the item moves into a menu.
      item.menuRepresentation = UIAction(title: title, image: image, handler: handler)
    } else {
      item = UIBarButtonItem(
        title: title, image: image,
        primaryAction: UIAction(title: title, image: image, handler: handler))
      item.tintColor = color
    }
    item.title = title
    item.identifier = "piliplus.page.\(id)"
    item.isEnabled = enabled
    // A standalone button, such as the reply button, gets its own background
    // instead of joining the group of its neighbours.
    item.sharesBackground = !(descriptor["standalone"] as? Bool ?? false)
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) { item.axisBehavior = .verticalPreferred }
    #endif
    actionCache[id] = (key, item)
    return item
  }

  private static func actionSymbol(_ id: String, selected: Bool) -> String {
    switch id {
    case "repost": return "arrowshape.turn.up.right"
    case "share": return "square.and.arrow.up"
    case "comment": return "bubble.right"
    case "like": return selected ? "hand.thumbsup.fill" : "hand.thumbsup"
    case "reply": return "arrowshape.turn.up.left.fill"
    default: return "ellipsis"
    }
  }

  private static func color(argb: Int) -> UIColor {
    UIColor(
      red: CGFloat((argb >> 16) & 0xff) / 255, green: CGFloat((argb >> 8) & 0xff) / 255,
      blue: CGFloat(argb & 0xff) / 255, alpha: CGFloat((argb >> 24) & 0xff) / 255)
  }

  private func requestPageAction(owner: Int, id: String) {
    guard barsVisible, owner == actionsOwner else { return }
    // One action at a time per button: a like waits for the request.
    let key = "\(owner):\(id)"
    guard actionsInFlight.insert(key).inserted else { return }
    onPageAction?(owner, id) { [weak self] in self?.actionsInFlight.remove(key) }
  }

  private func requestBack() {
    guard barsVisible, canGoBack, !backInFlight else { return }
    // One back per tap, even if UIKit delivers the tap twice or the user taps
    // again while the page is leaving.
    backInFlight = true
    onBack? { [weak self] in
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
        self?.backInFlight = false
      }
    }
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    topViewController?.supportedInterfaceOrientations ?? super.supportedInterfaceOrientations
  }
  override var childForStatusBarStyle: UIViewController? { topViewController }
  override var childForStatusBarHidden: UIViewController? { topViewController }
  override var childForHomeIndicatorAutoHidden: UIViewController? { topViewController }
  override var childForScreenEdgesDeferringSystemGestures: UIViewController? {
    topViewController
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
    child.view.frame = view.bounds
    child.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    view.addSubview(child.view)
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

// iPhone Duo: Flutter locks the interface to portrait on the outer display.
// UIKit picks the inner display's orientation from the lock in effect before
// the device unfolds, so a portrait-only lock leaves the interface in the inner
// display's native orientation, rotated relative to the device. Release the
// lock as soon as the hinge leaves the closed state, before the scene moves to
// the inner display. Dart restores it after the device closes again.
class DuoFlutterViewController: FlutterViewController {
  private var isHingeOpen = false

  override func viewDidLoad() {
    super.viewDidLoad()
    // UIHinge ships in the iOS 27.1 SDK (Xcode 27, Swift 6.4); older Xcode
    // versions build without hinge handling.
    #if compiler(>=6.4)
      if #available(iOS 27.1, *) {
        let interaction = UIHingeInteraction { [weak self] _, update in
          self?.hingeDidUpdate(update.hinge)
        }
        view.addInteraction(interaction)
      }
    #endif
  }

  #if compiler(>=6.4)
    @available(iOS 27.1, *)
    private func hingeDidUpdate(_ hinge: UIHinge?) {
      let isOpen = hinge.map { $0.status != .closed && $0.status != .unknown } ?? false
      guard isOpen != isHingeOpen else { return }
      isHingeOpen = isOpen
      setNeedsUpdateOfSupportedInterfaceOrientations()
      // Flutter also stores the lock as the scene's geometry preference, which
      // UIKit uses when the scene moves to the inner display. Clear it while the
      // scene is still on the outer display, where programmatic changes are
      // allowed.
      if isOpen, let windowScene = view.window?.windowScene {
        windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: .all))
      }
    }
  #endif

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    isHingeOpen ? .all : super.supportedInterfaceOrientations
  }

  // When hosted in NativeTabBarController, UIKit reads orientations from the
  // root controller, so forward Flutter's update requests to it.
  @available(iOS 16.0, *)
  override func setNeedsUpdateOfSupportedInterfaceOrientations() {
    super.setNeedsUpdateOfSupportedInterfaceOrientations()
    if let root = view.window?.rootViewController, root !== self {
      root.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
  }
}
