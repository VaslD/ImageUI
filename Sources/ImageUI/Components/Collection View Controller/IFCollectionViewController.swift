import Nuke
import UIKit

//
//  IFCollectionViewController.swift
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

protocol IFCollectionViewControllerDelegate: AnyObject {
    func collectionViewController(_ collectionViewController: IFCollectionViewController, didSelectItemAt index: Int)
    func collectionViewControllerWillBeginScrolling(_ collectionViewController: IFCollectionViewController)
}

class IFCollectionViewController: UIViewController {
    private enum Constants {
        static let carouselScrollingTransitionDuration: TimeInterval = 0.34
        static let carouselTransitionDuration: TimeInterval = 0.16
        static let carouselSelectionDuration: TimeInterval = 0.22
        static let flowTransitionDuration: TimeInterval = 0.24
    }

    enum PendingInvalidation {
        case bouncing
        case dragging(targetIndexPath: IndexPath)
    }

    // MARK: - View

    private lazy var collectionView: IFCollectionView = {
        let initialIndexPath = IndexPath(item: imageManager.displayingImageIndex, section: 0)
        let layout = IFCollectionViewFlowLayout(centerIndexPath: initialIndexPath, needsInitialContentOffset: true)
        let view = IFCollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private var horizontalConstraints: [NSLayoutConstraint] = []

    // MARK: - Public properties

    weak var delegate: IFCollectionViewControllerDelegate?
    let imageManager: IFImageManager

    // MARK: - Accessory properties

    private let prefetcher = ImagePreheater()
    private let bouncer = IFScrollViewBouncingManager()
    private var pendingInvalidation: PendingInvalidation?

    private var collectionViewLayout: IFCollectionViewFlowLayout {
        // swiftlint:disable:next force_cast
        self.collectionView.collectionViewLayout as! IFCollectionViewFlowLayout
    }

    // MARK: - Initializer

    init(imageManager: IFImageManager) {
        self.imageManager = imageManager
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.imageManager = IFImageManager(images: [])
        super.init(coder: coder)
    }

    deinit {
        prefetcher.stopPreheating()
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = UIView()
        view.clipsToBounds = true
        view.addSubview(self.collectionView)
        let leading = self.collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor)
        let bottom = view.bottomAnchor.constraint(equalTo: self.collectionView.bottomAnchor)
        let trailing = view.trailingAnchor.constraint(equalTo: self.collectionView.trailingAnchor)
        let top = self.collectionView.topAnchor.constraint(equalTo: view.topAnchor)
        self.horizontalConstraints = [leading, trailing]
        NSLayoutConstraint.activate([leading, bottom, trailing, top])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setup()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.update()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        self.collectionViewLayout.invalidateLayout()
        super.viewWillTransition(to: size, with: coordinator)
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        self.collectionView.prefetchDataSource = nil
        self.prefetcher.stopPreheating()
    }

    // MARK: - Public methods

    func scroll(toItemAt index: Int, progress: CGFloat) {
        guard isViewLoaded else { return }

        if self.collectionView.isDecelerating {
            self.updateCollectionViewLayout(style: .carousel)
        } else {
            let transitionIndexPath = IndexPath(item: index, section: 0)
            updateCollectionViewLayout(transitionIndexPath: transitionIndexPath, progress: progress)
        }
    }

    func scrollToDisplayingImageIndex() {
        guard self.collectionViewLayout.isTransitioning || self.collectionViewLayout.centerIndexPath.item != self
            .imageManager.displayingImageIndex else { return }
        self.updateCollectionViewLayout(style: .carousel)
    }

    func removeDisplayingImage(completion: (() -> Void)? = nil) {
        guard let cell = collectionView.cellForItem(at: collectionViewLayout.centerIndexPath) else { return }
        let currentIndexPath = self.collectionViewLayout.centerIndexPath
        self.collectionViewLayout
            .update(centerIndexPath: IndexPath(item: self.imageManager.displayingImageIndex, section: 0))

        let removingAnimation = {
            self.collectionView.performBatchUpdates({
                self.collectionView.deleteItems(at: [currentIndexPath])
            }, completion: { _ in
                let targetContentOffset = self.collectionViewLayout
                    .targetContentOffset(forProposedContentOffset: self.collectionView.contentOffset)
                self.collectionView.setContentOffset(targetContentOffset, animated: false)
                completion?()
            })
        }

        if let cell = cell as? IFImageContainerProvider {
            cell.prepareForRemoval {
                if self.imageManager.images.isEmpty {
                    completion?()
                } else {
                    removingAnimation()
                }
            }
        } else {
            removingAnimation()
        }
    }

    // MARK: - Private methods

    private func setup() {
        self.collectionView.register(
            IFCollectionViewCell.self,
            forCellWithReuseIdentifier: IFCollectionViewCell.identifier
        )
        self.collectionView.showsVerticalScrollIndicator = false
        self.collectionView.showsHorizontalScrollIndicator = false
        self.collectionView.dataSource = self
        self.collectionView.prefetchDataSource = self
        self.collectionView.delegate = self
        self.collectionView.alwaysBounceHorizontal = true
        self.collectionView.panGestureRecognizer.addTarget(self, action: #selector(self.pangestureDidChange))
        self.bouncer.startObserving(scrollView: self.collectionView, bouncingDirections: [.left, .right])
        self.bouncer.delegate = self
    }

    private func update() {
        if self.collectionView.bounds.width < view.bounds.width + self.collectionViewLayout.preferredOffBoundsPadding {
            self.horizontalConstraints.forEach {
                $0.constant = -collectionViewLayout.preferredOffBoundsPadding
            }
            self.collectionView.layoutIfNeeded()
            self.collectionViewLayout.invalidateLayout()
        }
    }

    @discardableResult
    private func updatedisplayingImageIndexIfNeeded(with index: Int) -> Bool {
        guard self.imageManager.displayingImageIndex != index else { return false }
        self.imageManager.updatedisplayingImage(index: index)
        self.collectionViewLayout.update(centerIndexPath: IndexPath(item: index, section: 0))
        self.delegate?.collectionViewController(self, didSelectItemAt: index)
        return true
    }

    private func updateCollectionViewLayout(style: IFCollectionViewFlowLayout.Style) {
        let indexPath = IndexPath(item: imageManager.displayingImageIndex, section: 0)
        let layout = IFCollectionViewFlowLayout(style: style, centerIndexPath: indexPath)
        let duration: TimeInterval

        switch self.pendingInvalidation {
        case .dragging:
            duration = Constants.carouselScrollingTransitionDuration
        default:
            duration = style == .carousel ? Constants.carouselTransitionDuration : Constants.flowTransitionDuration
        }

        self.pendingInvalidation = nil
        UIView.transition(
            with: self.collectionView,
            duration: duration,
            options: .curveEaseOut,
            animations: {
                if #available(iOS 13.0, *) {
                    self.collectionView.setCollectionViewLayout(layout, animated: true)
                } else {
                    self.collectionView.setCollectionViewLayout(layout, animated: true)
                    self.collectionView.layoutIfNeeded()
                }
            }
        )
    }

    private func updateCollectionViewLayout(transitionIndexPath: IndexPath, progress: CGFloat) {
        let indexPath = IndexPath(item: imageManager.displayingImageIndex, section: 0)
        let layout = IFCollectionViewFlowLayout(centerIndexPath: indexPath)
        layout.style = self.collectionViewLayout.style
        layout.setupTransition(to: transitionIndexPath, progress: progress)
        self.collectionView.setCollectionViewLayout(layout, animated: false)
    }

    private func updateCollectionViewLayout(forPreferredSizeAt indexPath: IndexPath) {
        guard
            self.collectionViewLayout.shouldInvalidateLayout(forPreferredItemSizeAt: indexPath),
            !self.collectionView.isDragging,
            !self.collectionView.isDecelerating else { return }
        self.updateCollectionViewLayout(style: .carousel)
    }

    @objc
    private func pangestureDidChange(_ sender: UIPanGestureRecognizer) {
        switch sender.state {
        case .cancelled,
             .ended where self.pendingInvalidation == nil:
            self.updateCollectionViewLayout(style: .carousel)
        default:
            break
        }
    }
}

// MARK: - IFCollectionViewController + UICollectionViewDataSource

extension IFCollectionViewController: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        self.imageManager.images.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: IFCollectionViewCell.identifier,
            for: indexPath
        )
        if let cell = cell as? IFCollectionViewCell {
            self.imageManager.loadImage(
                at: indexPath.item,
                options: IFImage.LoadOptions(preferredSize: self.collectionViewLayout.itemSize, kind: .thumbnail),
                sender: cell
            ) { [weak self] result in
                guard let self = self, case .success = result else { return }
                self.updateCollectionViewLayout(forPreferredSizeAt: indexPath)
            }
        }
        return cell
    }
}

// MARK: - IFCollectionViewController + UICollectionViewDataSourcePrefetching

extension IFCollectionViewController: UICollectionViewDataSourcePrefetching {
    func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
        guard collectionView.isDragging || collectionView.isDecelerating else { return }
        let urls = indexPaths.compactMap { imageManager.images[safe: $0.item]?.thumbnail?.url }
        self.prefetcher.startPreheating(with: urls)
    }

    func collectionView(_ collectionView: UICollectionView, cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
        let urls = indexPaths.compactMap { imageManager.images[safe: $0.item]?.thumbnail?.url }
        self.prefetcher.stopPreheating(with: urls)
    }
}

// MARK: - IFCollectionViewController + IFCollectionViewDelegate

extension IFCollectionViewController: IFCollectionViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView.isDragging, !self.collectionViewLayout.isTransitioning else { return }
        let centerIndexPath = self.collectionViewLayout.indexPath(forContentOffset: self.collectionView.contentOffset)
        guard
            self.updatedisplayingImageIndexIfNeeded(with: centerIndexPath.item),
            case let .dragging(targetIndexPath) = self.pendingInvalidation,
            targetIndexPath == centerIndexPath else { return }
        self.updateCollectionViewLayout(style: .carousel)
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        self.pendingInvalidation = nil
        guard self.collectionViewLayout.style == .carousel else { return }
        let contentOffset = self.collectionView.contentOffset
        self.updateCollectionViewLayout(style: .flow)
        let updatedContentOffset = self.collectionView.contentOffset
        self.collectionView.panGestureRecognizer.setTranslation(
            CGPoint(x: contentOffset.x - updatedContentOffset.x, y: 0),
            in: self.collectionView
        )
        self.delegate?.collectionViewControllerWillBeginScrolling(self)
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint,
                                   targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard velocity.x != 0 else { return }
        let minimumContentOffsetX = -scrollView.contentInset.left.rounded(.up)
        let maximumContentOffsetX =
            (scrollView.contentSize.width - scrollView.bounds.width + scrollView.contentInset.right).rounded(.down)
        if targetContentOffset.pointee.x > minimumContentOffsetX,
           targetContentOffset.pointee.x < maximumContentOffsetX {
            let targetIndexPath = self.collectionViewLayout.indexPath(forContentOffset: targetContentOffset.pointee)
            self.pendingInvalidation = .dragging(targetIndexPath: targetIndexPath)
        } else {
            self.pendingInvalidation = .bouncing
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard self.pendingInvalidation != nil else { return }
        let centerIndexPath = self.collectionViewLayout.indexPath(forContentOffset: self.collectionView.contentOffset)
        self.updatedisplayingImageIndexIfNeeded(with: centerIndexPath.item)
        self.updateCollectionViewLayout(style: .carousel)
    }

    func collectionView(_ collectionView: UICollectionView, touchBegan itemIndexPath: IndexPath?) {
        guard self.collectionViewLayout.isTransitioning else { return }
        self.updateCollectionViewLayout(style: .carousel)
        self.delegate?.collectionViewControllerWillBeginScrolling(self)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard self.updatedisplayingImageIndexIfNeeded(with: indexPath.item) else { return }

        UIView.transition(
            with: collectionView,
            duration: Constants.carouselSelectionDuration,
            options: .curveEaseOut,
            animations: {
                self.collectionViewLayout.setupTransition(to: indexPath)
                self.collectionViewLayout.invalidateLayout()
                self.collectionView.layoutIfNeeded()
            }
        )
    }
}

// MARK: - IFCollectionViewController + IFScrollViewBouncingDelegate

extension IFCollectionViewController: IFScrollViewBouncingDelegate {
    func scrollView(_ scrollView: UIScrollView, didReverseBouncing direction: UIScrollView.BouncingDirection) {
        let indexPath: IndexPath
        switch direction {
        case .left:
            indexPath = IndexPath(item: 0, section: 0)
        case .right:
            indexPath = IndexPath(item: self.imageManager.images.count - 1, section: 0)
        default:
            return
        }
        self.updatedisplayingImageIndexIfNeeded(with: indexPath.item)
        self.updateCollectionViewLayout(style: .carousel)
    }
}
