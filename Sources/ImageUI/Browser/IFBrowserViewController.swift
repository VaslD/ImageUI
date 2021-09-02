import UIKit

//
//  IFBrowserViewController.swift
//
//  Copyright © 2020 ImageUI - Alberto Saltarelli
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

public protocol IFBrowserViewControllerDelegate: AnyObject {
    func browserViewController(_ browserViewController: IFBrowserViewController, didSelectActionWith identifier: String,
                               forImageAt index: Int)
    func browserViewController(_ browserViewController: IFBrowserViewController, willDeleteItemAt index: Int,
                               completion: @escaping (Bool) -> Void)
    func browserViewController(_ browserViewController: IFBrowserViewController, didDeleteItemAt index: Int,
                               isEmpty: Bool)
    func browserViewController(_ browserViewController: IFBrowserViewController, willDisplayImageAt index: Int)
}

public extension IFBrowserViewControllerDelegate {
    func browserViewController(_ browserViewController: IFBrowserViewController, didSelectActionWith identifier: String,
                               forImageAt index: Int) {}
    func browserViewController(_ browserViewController: IFBrowserViewController, willDeleteItemAt index: Int,
                               completion: @escaping (Bool) -> Void) {
        completion(true)
    }

    func browserViewController(_ browserViewController: IFBrowserViewController, didDeleteItemAt index: Int,
                               isEmpty: Bool) {}
    func browserViewController(_ browserViewController: IFBrowserViewController, willDisplayImageAt index: Int) {}
}

open class IFBrowserViewController: UIViewController {
    private enum Constants {
        static let toolbarContentInset = UIEdgeInsets(top: -1, left: 0, bottom: 0, right: 0)
    }

    // MARK: - View

    private let pageContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let collectionToolbar: UIToolbar = {
        let toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        return toolbar
    }()

    private let toolbarMaskLayer: CALayer = {
        let layer = CALayer()
        layer.backgroundColor = UIColor.black.cgColor
        return layer
    }()

    private let collectionContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    // MARK: - Public properties

    public weak var delegate: IFBrowserViewControllerDelegate?
    public var configuration = Configuration() {
        didSet {
            imageManager.prefersAspectFillZoom = configuration.prefersAspectFillZoom
            setupBars()
            updateBars(toggle: false)
        }
    }

    override open var prefersStatusBarHidden: Bool {
        isFullScreenMode
    }

    override open var prefersHomeIndicatorAutoHidden: Bool {
        self.isFullScreenMode
    }

    // MARK: - Accessory properties

    private let imageManager: IFImageManager
    private var shouldUpdateTitle = true

    private lazy var tapGesture = UITapGestureRecognizer(target: self, action: #selector(gestureRecognizerDidChange))
    private lazy var doubleTapGesture: UITapGestureRecognizer = {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(gestureRecognizerDidChange))
        gesture.numberOfTapsRequired = 2
        return gesture
    }()

    private lazy var pinchGesture = UIPinchGestureRecognizer(target: self,
                                                             action: #selector(gestureRecognizerDidChange))
    private lazy var pageViewController = IFPageViewController(imageManager: imageManager)
    private lazy var collectionViewController = IFCollectionViewController(imageManager: imageManager)

    private var shouldResetBarStatus = false
    private var isFullScreenMode = false

    private var shouldShowCancelButton: Bool {
        navigationController.map { $0.presentingViewController != nil && $0.viewControllers.first === self } ?? false
    }

    private var isCollectionViewEnabled: Bool {
        self.imageManager.images.count > 1
    }

    private var isNavigationBarEnabled: Bool {
        self.configuration.alwaysShowNavigationBar || !self.configuration.isNavigationBarHidden
    }

    private var isToolbarEnabled: Bool {
        switch (traitCollection.verticalSizeClass, traitCollection.horizontalSizeClass) {
        case let (.regular, horizontalClass) where horizontalClass != .regular:
            return self.configuration.alwaysShowToolbar || !self.configuration.actions.isEmpty
        default:
            return false
        }
    }

    private var defaultBackgroundColor: UIColor {
        if #available(iOS 13.0, *) {
            return .systemBackground
        } else {
            return .white
        }
    }

    // MARK: - Initializer

    public init(images: [IFImage], initialImageIndex: Int = 0) {
        self.imageManager = IFImageManager(images: images, initialImageIndex: initialImageIndex)
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        self.imageManager = IFImageManager(images: [])
        super.init(coder: coder)
    }

    // MARK: - Lifecycle

    override public func loadView() {
        view = UIView()
        view.backgroundColor = self.defaultBackgroundColor

        [self.pageContainerView, self.collectionToolbar, self.collectionContainerView].forEach(view.addSubview)

        NSLayoutConstraint.activate([
            self.pageContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            self.pageContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            self.pageContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            self.pageContainerView.topAnchor.constraint(equalTo: view.topAnchor),
            self.collectionToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            self.collectionToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            self.collectionToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            self.collectionContainerView.centerXAnchor.constraint(equalTo: self.collectionToolbar.centerXAnchor),
            self.collectionContainerView.centerYAnchor.constraint(equalTo: self.collectionToolbar.centerYAnchor),
            self.collectionContainerView.widthAnchor.constraint(equalTo: self.collectionToolbar.widthAnchor),
            self.collectionContainerView.heightAnchor.constraint(equalTo: self.collectionToolbar.heightAnchor),
        ])
    }

    override open func viewDidLoad() {
        super.viewDidLoad()
        self.setup()
        self.updateTitleIfNeeded()
        self.setupBars()
    }

    override open func willMove(toParent parent: UIViewController?) {
        super.willMove(toParent: parent)
        self.shouldResetBarStatus = true
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.shouldResetBarStatus {
            self.shouldResetBarStatus = false
            var configuration = self.configuration
            configuration.isNavigationBarHidden = navigationController?.isNavigationBarHidden == true
            configuration.isToolbarHidden = navigationController?.isToolbarHidden == true
            self.configuration = configuration
        }
    }

    override open func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if self.shouldResetBarStatus {
            self.shouldResetBarStatus = false
            navigationController?.isNavigationBarHidden = self.configuration.isNavigationBarHidden
            navigationController?.isToolbarHidden = self.configuration.isToolbarHidden
        }
    }

    override open func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if traitCollection.verticalSizeClass != previousTraitCollection?.verticalSizeClass {
            self.setupBars()
            self.updateBars(toggle: false)
        }
    }

    // MARK: - Style

    private func setup() {
        if self.shouldShowCancelButton, navigationItem.leftBarButtonItem == nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel,
                                                               target: self, action: #selector(self.cancelButtonDidTap))
        }

        self.shouldUpdateTitle = title == nil && navigationItem.title == nil && navigationItem.titleView == nil

        [self.tapGesture, self.doubleTapGesture, self.pinchGesture].forEach {
            $0.delegate = self
            view.addGestureRecognizer($0)
        }

        if let customShadow = navigationController?.toolbar.shadowImage(forToolbarPosition: .bottom) {
            self.collectionToolbar.setShadowImage(customShadow, forToolbarPosition: .bottom)
        }
        navigationController?.toolbar.setShadowImage(UIImage(), forToolbarPosition: .bottom)
        self.collectionToolbar.barTintColor = navigationController?.toolbar.barTintColor

        addChild(self.pageViewController)
        self.pageViewController.progressDelegate = self
        self.pageContainerView.addSubview(self.pageViewController.view)
        self.pageViewController.view.frame = self.pageContainerView.bounds
        self.pageViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        addChild(self.collectionViewController)
        self.collectionViewController.delegate = self
        self.collectionContainerView.addSubview(self.collectionViewController.view)
        self.collectionViewController.view.frame = self.collectionContainerView.bounds
        self.collectionViewController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    private func setupBars() {
        guard isViewLoaded else { return }

        let barButtonItems = self.configuration.actions.map { $0.barButtonItem(target: self,
                                                                               action: #selector(actionButtonDidTap)) }

        if self.isToolbarEnabled {
            navigationItem.setRightBarButtonItems([], animated: true)
            let toolbarItems = barButtonItems.isEmpty ? [] : (0..<barButtonItems.count * 2 - 1).map {
                $0.isMultiple(of: 2)
                    ? barButtonItems[$0 / 2]
                    : UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
            }
            setToolbarItems(toolbarItems, animated: true)
        } else {
            navigationItem.setRightBarButtonItems(barButtonItems.reversed(), animated: true)
            setToolbarItems([], animated: true)
        }

        self.collectionToolbar.invalidateIntrinsicContentSize()
    }

    private func updateBars(toggle: Bool) {
        guard isViewLoaded else { return }
        guard !toggle else {
            self.animateBarsToggling()
            return
        }

        let shouldHideToolbar = !self.isToolbarEnabled || self.isFullScreenMode
        navigationController?.setToolbarHidden(shouldHideToolbar, animated: false)

        if !self.isCollectionViewEnabled, !self.collectionContainerView.isHidden {
            self.updateToolbarMask()
            UIView.animate(
                withDuration: TimeInterval(UINavigationController.hideShowBarDuration),
                animations: { [weak self] in
                    [self?.collectionToolbar, self?.collectionContainerView].forEach { $0?.alpha = 0 }
                },
                completion: { [weak self] _ in
                    [self?.collectionToolbar, self?.collectionContainerView].forEach { $0?.isHidden = true }
                    self?.collectionToolbar.layer.mask = nil
                }
            )
        }
    }

    private func animateBarsToggling() {
        let isToolbarHidden = navigationController?.isToolbarHidden == true
        let isCollectionViewHidden = self.collectionContainerView.isHidden

        if self.isNavigationBarEnabled, self.isFullScreenMode {
            navigationController?.setNavigationBarHidden(false, animated: false)
            navigationController?.navigationBar.alpha = 0
        }

        if self.isToolbarEnabled, isToolbarHidden {
            navigationController?.isToolbarHidden = false
        }

        if self.isCollectionViewEnabled, isCollectionViewHidden {
            [self.collectionToolbar, self.collectionContainerView].forEach {
                $0.isHidden = false
                $0.alpha = 0
            }
        }

        self.updateToolbarMask()
        self.isFullScreenMode.toggle()

        DispatchQueue.main.async {
            if self.isToolbarEnabled, isToolbarHidden {
                self.navigationController?.toolbar.alpha = 0
            }

            UIView.animate(
                withDuration: TimeInterval(UINavigationController.hideShowBarDuration),
                animations: {
                    self.view.backgroundColor = self.isFullScreenMode ? .black : self.defaultBackgroundColor
                    self.navigationController?.navigationBar.alpha = self.isFullScreenMode && self
                        .isNavigationBarEnabled ? 0 : 1
                    if self.isToolbarEnabled {
                        self.navigationController?.toolbar.alpha = isToolbarHidden ? 1 : 0
                    }

                    if self.isCollectionViewEnabled {
                        [self.collectionToolbar, self.collectionContainerView]
                            .forEach { $0.alpha = isCollectionViewHidden ? 1 : 0 }
                    }

                    self.setNeedsStatusBarAppearanceUpdate()
                    self.setNeedsUpdateOfHomeIndicatorAutoHidden()
                }, completion: { _ in
                    if self.isFullScreenMode, self.isNavigationBarEnabled {
                        self.navigationController?.setNavigationBarHidden(true, animated: true)
                        self.navigationController?.navigationBar.alpha = 0
                    }

                    if self.isToolbarEnabled, !isToolbarHidden {
                        self.navigationController?.isToolbarHidden = true
                    }

                    if self.isCollectionViewEnabled {
                        [self.collectionToolbar, self.collectionContainerView]
                            .forEach { $0.isHidden = !isCollectionViewHidden }
                        self.collectionToolbar.layer.mask = nil
                    }
                }
            )
        }
    }

    private func updateTitleIfNeeded(imageIndex: Int? = nil) {
        guard self.shouldUpdateTitle else { return }
        title = self.imageManager.images[safe: imageIndex ?? self.imageManager.displayingImageIndex]?.title
    }

    private func updateToolbarMask() {
        self.toolbarMaskLayer.frame = CGRect(
            x: Constants.toolbarContentInset.left,
            y: Constants.toolbarContentInset.top,
            width: self.collectionToolbar.frame
                .width - (Constants.toolbarContentInset.left + Constants.toolbarContentInset.right),
            height: self.collectionToolbar.frame
                .height - (Constants.toolbarContentInset.top + Constants.toolbarContentInset.bottom)
        )
        self.collectionToolbar.layer.mask = navigationController?.isToolbarHidden == true ? nil : self.toolbarMaskLayer
    }

    private func presentShareViewController(sender: UIBarButtonItem) {
        self.imageManager.sharingImage(forImageAt: self.imageManager.displayingImageIndex) { [weak self] result in
            guard case let .success(sharingImage) = result else { return }
            let viewController = UIActivityViewController(activityItems: [sharingImage], applicationActivities: nil)
            viewController.modalPresentationStyle = .popover
            viewController.popoverPresentationController?.barButtonItem = sender
            self?.present(viewController, animated: true)
        }
    }

    private func handleRemove() {
        let removingIndex = self.imageManager.displayingImageIndex
        self.imageManager.removeDisplayingImage()

        let group = DispatchGroup()
        group.enter()
        self.pageViewController.removeDisplayingImage { group.leave() }
        group.enter()
        self.collectionViewController.removeDisplayingImage { group.leave() }

        let view = navigationController?.view ?? self.view
        view?.isUserInteractionEnabled = false
        group.notify(queue: .main) { [weak self, weak view] in
            view?.isUserInteractionEnabled = true
            if let self = self {
                self.delegate?.browserViewController(
                    self,
                    didDeleteItemAt: removingIndex,
                    isEmpty: self.imageManager.images.isEmpty
                )
            }
        }
    }

    // MARK: - UI Actions

    @objc
    private func gestureRecognizerDidChange(_ sender: UIGestureRecognizer) {
        switch sender {
        case self.tapGesture,
             self.doubleTapGesture where !self.isFullScreenMode,
             self.pinchGesture where sender.state == .began && !self.isFullScreenMode:

            self.updateBars(toggle: true)
        default:
            break
        }
    }

    @objc
    private func cancelButtonDidTap() {
        dismiss(animated: true)
    }

    @objc
    private func actionButtonDidTap(_ sender: UIBarButtonItem) {
        let senderIndex: Int?
        if navigationController?.isToolbarHidden == true {
            senderIndex = navigationItem.rightBarButtonItems?.reversed().firstIndex(of: sender)
        } else {
            senderIndex = toolbarItems?.firstIndex(of: sender).map { $0 / 2 }
        }

        guard let actionIndex = senderIndex, let action = configuration.actions[safe: actionIndex] else { return }
        self.collectionViewController.scrollToDisplayingImageIndex()
        self.pageViewController.invalidateDataSourceIfNeeded()

        switch action {
        case .share:
            self.presentShareViewController(sender: sender)
        case .delete:
            if let delegate = delegate {
                delegate
                    .browserViewController(self,
                                           willDeleteItemAt: self.imageManager
                                               .displayingImageIndex) { [weak self] shouldRemove in
                        guard shouldRemove else { return }
                        self?.handleRemove()
                    }
            } else {
                self.handleRemove()
            }
        case let .custom(identifier, _):
            self.delegate?.browserViewController(
                self,
                didSelectActionWith: identifier,
                forImageAt: self.imageManager.displayingImageIndex
            )
        }
    }
}

// MARK: - IFBrowserViewController + UIGestureRecognizerDelegate

extension IFBrowserViewController: UIGestureRecognizerDelegate {
    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        switch (gestureRecognizer, otherGestureRecognizer) {
        case (self.doubleTapGesture, is UITapGestureRecognizer), (self.pinchGesture, is UIPinchGestureRecognizer):
            return true
        default:
            return false
        }
    }

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        self.collectionContainerView.isHidden || !self.collectionContainerView.frame.contains(touch.location(in: view))
    }

    public func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === self.tapGesture && otherGestureRecognizer === self.doubleTapGesture
    }
}

// MARK: - IFBrowserViewController + IFPageViewControllerDelegate

extension IFBrowserViewController: IFPageViewControllerDelegate {
    func pageViewController(
        _ pageViewController: IFPageViewController,
        didScrollFrom startIndex: Int,
        direction: UIPageViewController.NavigationDirection,
        progress: CGFloat
    ) {
        let endIndex = direction == .forward ? startIndex + 1 : startIndex - 1
        self.collectionViewController.scroll(toItemAt: endIndex, progress: progress)
    }

    func pageViewController(_ pageViewController: IFPageViewController, didUpdatePage index: Int) {
        self.updateTitleIfNeeded(imageIndex: index)
        self.delegate?.browserViewController(self, willDisplayImageAt: index)
    }

    func pageViewControllerDidResetScroll(_ pageViewController: IFPageViewController) {
        self.collectionViewController.scrollToDisplayingImageIndex()
        self.updateTitleIfNeeded(imageIndex: self.imageManager.displayingImageIndex)
        self.delegate?.browserViewController(self, willDisplayImageAt: self.imageManager.displayingImageIndex)
    }
}

// MARK: - IFBrowserViewController + IFCollectionViewControllerDelegate

extension IFBrowserViewController: IFCollectionViewControllerDelegate {
    func collectionViewController(_ collectionViewController: IFCollectionViewController, didSelectItemAt index: Int) {
        self.pageViewController.updateVisibleImage(index: index)
        self.updateTitleIfNeeded(imageIndex: index)
        self.delegate?.browserViewController(self, willDisplayImageAt: index)
    }

    func collectionViewControllerWillBeginScrolling(_ collectionViewController: IFCollectionViewController) {
        self.pageViewController.invalidateDataSourceIfNeeded()
    }
}

private extension IFBrowserViewController.Action {
    func barButtonItem(target: Any?, action: Selector?) -> UIBarButtonItem {
        switch self {
        case .share:
            return UIBarButtonItem(barButtonSystemItem: .action, target: target, action: action)
        case .delete:
            return UIBarButtonItem(barButtonSystemItem: .trash, target: target, action: action)
        case let .custom(_, image):
            return UIBarButtonItem(image: image, style: .plain, target: target, action: action)
        }
    }
}
