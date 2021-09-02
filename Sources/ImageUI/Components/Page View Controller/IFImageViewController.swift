import UIKit

//
//  IFImageViewController.swift
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

class IFImageViewController: UIViewController {
    private enum Constants {
        static let minimumMaximumZoomFactor: CGFloat = 3
        static let doubleTapZoomMultiplier: CGFloat = 0.85
        static let preferredAspectFillRatio: CGFloat = 0.9
    }

    // MARK: - View

    private let scrollView: UIScrollView = {
        let view = UIScrollView()
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentInsetAdjustmentBehavior = .never
        return view
    }()

    private let imageView: UIImageView = {
        let view = UIImageView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.isUserInteractionEnabled = true
        return view
    }()

    // MARK: - Public properties

    let imageManager: IFImageManager
    var displayingImageIndex: Int {
        didSet {
            guard self.displayingImageIndex != oldValue else { return }
            self.update()
        }
    }

    // MARK: - Accessory properties

    private var aspectFillZoom: CGFloat = 1
    private var needsFirstLayout = true

    // MARK: - Initializer

    public init(imageManager: IFImageManager, displayingImageIndex: Int? = nil) {
        self.imageManager = imageManager
        self.displayingImageIndex = displayingImageIndex ?? imageManager.displayingImageIndex
        super.init(nibName: nil, bundle: nil)
    }

    public required init?(coder: NSCoder) {
        self.imageManager = IFImageManager(images: [])
        self.displayingImageIndex = 0
        super.init(coder: coder)
    }

    // MARK: - Lifecycle

    override func loadView() {
        view = UIView()
        view.addSubview(self.scrollView)
        self.scrollView.addSubview(self.imageView)

        NSLayoutConstraint.activate([
            self.scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            self.scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            self.scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            self.scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            self.imageView.leadingAnchor.constraint(equalTo: self.scrollView.leadingAnchor),
            self.imageView.bottomAnchor.constraint(equalTo: self.scrollView.bottomAnchor),
            self.imageView.trailingAnchor.constraint(equalTo: self.scrollView.trailingAnchor),
            self.imageView.topAnchor.constraint(equalTo: self.scrollView.topAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.setup()
        self.update()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.scrollView.zoomScale = self.scrollView.minimumZoomScale
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if self.needsFirstLayout {
            self.needsFirstLayout = false
            self.updateScrollView()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        let centerOffsetRatioX = (scrollView.contentOffset.x + self.scrollView.frame.width / 2) / self.scrollView
            .contentSize.width
        let centerOffsetRatioY = (scrollView.contentOffset.y + self.scrollView.frame.height / 2) / self.scrollView
            .contentSize.height

        coordinator.animate(alongsideTransition: { _ in
            self.updateScrollView(resetZoom: false)
            self.updateContentOffset(previousOffsetRatio: CGPoint(x: centerOffsetRatioX, y: centerOffsetRatioY))
        })
        super.viewWillTransition(to: size, with: coordinator)
    }

    private func setup() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(self.imageViewDidDoubleTap))
        tapGesture.numberOfTapsRequired = 2
        self.imageView.addGestureRecognizer(tapGesture)
        self.scrollView.delegate = self
        self.scrollView.decelerationRate = .fast
        self.scrollView.contentInsetAdjustmentBehavior = .never
    }

    private func update() {
        guard isViewLoaded else { return }
        UIView.performWithoutAnimation {
            imageManager.loadImage(
                at: displayingImageIndex,
                options: IFImage.LoadOptions(kind: .original),
                sender: imageView
            ) { [weak self] _ in
                self?.updateScrollView()
            }
        }
    }

    private func updateScrollView(resetZoom: Bool = true) {
        guard let image = imageView.image, image.size.width > 0, image.size.height > 0, view.frame != .zero else {
            return
        }

        let aspectFitZoom = min(view.frame.width / image.size.width, view.frame.height / image.size.height)
        self.aspectFillZoom = max(view.frame.width / image.size.width, view.frame.height / image.size.height)
        let zoomMultiplier = (scrollView.zoomScale - self.scrollView.minimumZoomScale) /
            (self.scrollView.maximumZoomScale - self.scrollView.minimumZoomScale)

        let minimumZoomScale: CGFloat
        if self.imageManager.prefersAspectFillZoom,
           aspectFitZoom / self.aspectFillZoom >= Constants.preferredAspectFillRatio {
            minimumZoomScale = self.aspectFillZoom
        } else {
            minimumZoomScale = aspectFitZoom
        }

        self.scrollView.minimumZoomScale = minimumZoomScale
        self.scrollView.maximumZoomScale = max(
            minimumZoomScale * Constants.minimumMaximumZoomFactor,
            self.aspectFillZoom
        )

        let zoomScale = resetZoom ? minimumZoomScale :
            (minimumZoomScale + (self.scrollView.maximumZoomScale - minimumZoomScale) * zoomMultiplier)
        self.scrollView.zoomScale = zoomScale
        self.updateContentInset()
    }

    private func updateContentInset() {
        guard let image = imageView.image else { return }
        self.scrollView.contentInset.top = max(
            (self.scrollView.frame.height - image.size.height * self.scrollView.zoomScale) / 2,
            0
        )
        self.scrollView.contentInset.left = max(
            (self.scrollView.frame.width - image.size.width * self.scrollView.zoomScale) / 2,
            0
        )
    }

    private func updateContentOffset(previousOffsetRatio: CGPoint) {
        guard self.scrollView.contentSize.width > 0, self.scrollView.contentSize.height > 0 else { return }
        let proposedContentOffsetX = (previousOffsetRatio.x * self.scrollView.contentSize.width) -
            (self.scrollView.frame.width / 2)
        let proposedContentOffsetY = (previousOffsetRatio.y * self.scrollView.contentSize.height) -
            (self.scrollView.frame.height / 2)

        let minimumContentOffsetX = -self.scrollView.contentInset.left.rounded(.up)
        let maximumContentOffsetX: CGFloat
        if self.scrollView.contentSize.width <= self.scrollView.frame.width {
            maximumContentOffsetX = minimumContentOffsetX
        } else {
            maximumContentOffsetX = (self.scrollView.contentSize.width - self.scrollView.frame.width + self.scrollView
                .contentInset.right).rounded(.down)
        }

        let minimumContentOffsetY = -self.scrollView.contentInset.top.rounded(.up)
        let maximumContentOffsetY: CGFloat
        if self.scrollView.contentSize.height <= self.scrollView.frame.height {
            maximumContentOffsetY = minimumContentOffsetY
        } else {
            maximumContentOffsetY = (self.scrollView.contentSize.height - self.scrollView.frame.height + self.scrollView
                .contentInset.bottom).rounded(.down)
        }

        let targetContentOffsetX = min(max(proposedContentOffsetX, minimumContentOffsetX), maximumContentOffsetX)
        let targetContentOffsetY = min(max(proposedContentOffsetY, minimumContentOffsetY), maximumContentOffsetY)

        scrollView.contentOffset = CGPoint(x: targetContentOffsetX, y: targetContentOffsetY)
    }

    // MARK: - UI Actions

    @objc
    private func imageViewDidDoubleTap(_ sender: UITapGestureRecognizer) {
        switch self.scrollView.zoomScale {
        case self.scrollView.minimumZoomScale:
            let targetZoomScale = min(aspectFillZoom, scrollView.maximumZoomScale * Constants.doubleTapZoomMultiplier)
            let zoomWidth = self.scrollView.bounds.width / targetZoomScale
            let zoomHeight = self.scrollView.bounds.height / targetZoomScale
            let zoomRect = CGRect(
                x: imageView.bounds.midX - zoomWidth / 2,
                y: self.imageView.bounds.midY - zoomHeight / 2,
                width: zoomWidth,
                height: zoomHeight
            )
            self.scrollView.zoom(to: zoomRect, animated: true)

        default:
            self.scrollView.setZoomScale(self.scrollView.minimumZoomScale, animated: true)
        }
    }
}

// MARK: - IFImageViewController + UIScrollViewDelegate

extension IFImageViewController: UIScrollViewDelegate {
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        self.imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        self.updateContentInset()
    }
}

// MARK: - IFImageViewController + IFImageContainerProvider

extension IFImageViewController: IFImageContainerProvider {
    var imageContainerView: UIView {
        self.scrollView
    }
}
