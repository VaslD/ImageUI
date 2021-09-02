import UIKit

//
//  IFPageViewController.swift
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

protocol IFPageViewControllerDelegate: AnyObject {
    func pageViewController(_ pageViewController: IFPageViewController, didScrollFrom startIndex: Int,
                            direction: UIPageViewController.NavigationDirection, progress: CGFloat)
    func pageViewController(_ pageViewController: IFPageViewController, didUpdatePage index: Int)
    func pageViewControllerDidResetScroll(_ pageViewController: IFPageViewController)
}

class IFPageViewController: UIPageViewController {
    private enum Constants {
        static let interPageSpacing: CGFloat = 40
    }

    // MARK: - View

    private var scrollView: UIScrollView? {
        view.subviews.first { $0 is UIScrollView } as? UIScrollView
    }

    // MARK: - Public properties

    weak var progressDelegate: IFPageViewControllerDelegate?

    let imageManager: IFImageManager

    // MARK: - Accessory properties

    private var contentOffsetObservation: NSKeyValueObservation?
    private var isRemovingPage = false
    private var beforeViewController: IFImageViewController?
    private var visibleViewController: IFImageViewController? {
        viewControllers?.first as? IFImageViewController
    }

    private var afterViewController: IFImageViewController?

    // MARK: - Initializer

    override private init(transitionStyle style: UIPageViewController.TransitionStyle,
                          navigationOrientation: UIPageViewController.NavigationOrientation,
                          options: [UIPageViewController.OptionsKey: Any]? = nil) {
        self.imageManager = IFImageManager(images: [])
        super.init(transitionStyle: style, navigationOrientation: navigationOrientation, options: options)
    }

    init(imageManager: IFImageManager) {
        self.imageManager = imageManager
        super.init(
            transitionStyle: .scroll,
            navigationOrientation: .horizontal,
            options: [.interPageSpacing: Constants.interPageSpacing]
        )
    }

    required init?(coder: NSCoder) {
        self.imageManager = IFImageManager(images: [])
        super.init(coder: coder)
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setup()
    }

    // MARK: - Public methods

    func updateVisibleImage(index: Int) {
        guard isViewLoaded, let visibleViewController = visibleViewController else { return }
        self.reloadDataSourceIfNeeded(forImageAt: index)
        self.beforeViewController?.displayingImageIndex = index - 1
        self.afterViewController?.displayingImageIndex = index + 1
        visibleViewController.displayingImageIndex = index
    }

    func removeDisplayingImage(completion: (() -> Void)? = nil) {
        guard let displayingImageIndex = visibleViewController?.displayingImageIndex else { return }
        let removingDirection: NavigationDirection = displayingImageIndex > self.imageManager
            .displayingImageIndex ? .reverse : .forward
        let viewController = IFImageViewController(imageManager: imageManager)
        isRemovingPage = true
        self.visibleViewController?.prepareForRemoval { [weak self] in
            if self?.imageManager.images.isEmpty == true {
                self?.isRemovingPage = false
                completion?()
            } else {
                self?.setViewControllers([viewController], direction: removingDirection, animated: true) { _ in
                    self?.isRemovingPage = false
                    completion?()
                }
            }
        }
    }

    func invalidateDataSourceIfNeeded() {
        guard let scrollView = scrollView, scrollView.isDragging || scrollView.isDecelerating else { return }
        self.invalidateDataSource()
    }

    // Disable gesture-based navigation.
    private func invalidateDataSource() {
        dataSource = nil
        [self.beforeViewController, self.afterViewController].forEach { $0?.removeFromParent() }
        self.beforeViewController = nil
        self.afterViewController = nil
        dataSource = self
    }

    private func reloadDataSourceIfNeeded(forImageAt index: Int) {
        switch (self.visibleViewController?.displayingImageIndex, index) {
        case (0, _), (self.imageManager.images.count - 1, _), (_, 0), (_, self.imageManager.images.count - 1):
            self.invalidateDataSource()
        default:
            break
        }
    }

    // MARK: - Private methods

    private func setup() {
        dataSource = self
        delegate = self
        self.contentOffsetObservation = self.scrollView?
            .observe(\.contentOffset, options: .old) { [weak self] scrollView, change in
                guard let oldValue = change.oldValue, oldValue != scrollView.contentOffset else { return }
                self?.handleContentOffset(in: scrollView, oldValue: oldValue)
            }

        let initialViewController = IFImageViewController(imageManager: imageManager)
        setViewControllers([initialViewController], direction: .forward, animated: false)
    }

    private func handleContentOffset(in scrollView: UIScrollView, oldValue: CGPoint) {
        switch scrollView.panGestureRecognizer.state {
        case .cancelled:
            DispatchQueue.main.async {
                self.invalidateDataSource()
                self.progressDelegate?.pageViewControllerDidResetScroll(self)
            }
        default:
            guard self.isRemovingPage || scrollView.isDragging || scrollView.isDecelerating else { break }

            let oldProgress = (oldValue.x - scrollView.bounds.width) / scrollView.bounds.width
            let oldNormalizedProgress = min(max(abs(oldProgress), 0), 1)
            let progress = (scrollView.contentOffset.x - scrollView.bounds.width) / scrollView.bounds.width
            let normalizedProgress = min(max(abs(progress), 0), 1)

            let direction: NavigationDirection = progress < 0 ? .reverse : .forward
            if !self.isRemovingPage {
                self.progressDelegate?.pageViewController(
                    self,
                    didScrollFrom: self.imageManager.displayingImageIndex,
                    direction: direction,
                    progress: normalizedProgress
                )
            }

            switch (oldNormalizedProgress, normalizedProgress) {
            case (CGFloat(0.nextUp)..<0.5, 0.5..<1):
                let index: Int
                if self.isRemovingPage {
                    index = self.imageManager.displayingImageIndex
                } else {
                    index = direction == .forward ? self.imageManager.displayingImageIndex + 1 : self.imageManager
                        .displayingImageIndex - 1
                }
                self.progressDelegate?.pageViewController(self, didUpdatePage: index)
            case (CGFloat(0.5.nextUp)..<1, CGFloat(0.nextUp)...0.5):
                self.progressDelegate?.pageViewController(self, didUpdatePage: self.imageManager.displayingImageIndex)
            default:
                break
            }
        }
    }
}

// MARK: - IFPageViewController + UIPageViewControllerDataSource

extension IFPageViewController: UIPageViewControllerDataSource {
    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        let previousIndex = self.imageManager.displayingImageIndex - 1
        guard self.imageManager.images.indices.contains(previousIndex) else { return nil }
        self.beforeViewController = IFImageViewController(
            imageManager: self.imageManager,
            displayingImageIndex: previousIndex
        )
        return self.beforeViewController
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        let nextIndex = self.imageManager.displayingImageIndex + 1
        guard self.imageManager.images.indices.contains(nextIndex) else { return nil }
        self.afterViewController = IFImageViewController(
            imageManager: self.imageManager,
            displayingImageIndex: nextIndex
        )
        return self.afterViewController
    }
}

// MARK: - IFPageViewController + UIPageViewControllerDelegate

extension IFPageViewController: UIPageViewControllerDelegate {
    func pageViewController(_ pageViewController: UIPageViewController,
                            didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        guard
            completed,
            let previousViewController = previousViewControllers.first as? IFImageViewController,
            let visibleViewController = visibleViewController else { return }

        switch visibleViewController {
        case self.afterViewController:
            self.beforeViewController = previousViewController
        case self.beforeViewController:
            self.afterViewController = previousViewController
        default:
            break
        }
        self.imageManager.updatedisplayingImage(index: visibleViewController.displayingImageIndex)
    }
}
