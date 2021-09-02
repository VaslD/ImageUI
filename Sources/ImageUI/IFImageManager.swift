import Nuke
import Photos
import LinkPresentation

//
//  IFImageManager.swift
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

class IFImageManager {
    private(set) var images: [IFImage]
    private let pipeline = ImagePipeline()
    private let photosManager = PHCachingImageManager()

    var prefersAspectFillZoom = false
    var placeholderImage: UIImage?
    private var previousDisplayingImageIndex: Int?
    private(set) var displayingImageIndex: Int {
        didSet { self.previousDisplayingImageIndex = oldValue }
    }

    private lazy var displayingLinkMetadata: LPLinkMetadata? = nil
    private var linkMetadataTask: ImageTask? {
        didSet { oldValue?.cancel() }
    }

    init(images: [IFImage], initialImageIndex: Int = 0) {
        self.images = images
        self.displayingImageIndex = min(max(initialImageIndex, 0), images.count - 1)
            prepareDisplayingMetadata()
    }

    func updateDisplayingImage(index: Int) {
        guard self.images.indices.contains(index) else { return }
        self.displayingImageIndex = index
            prepareDisplayingMetadata()
    }

    func removeDisplayingImage() {
        let removingIndex = self.displayingImageIndex
        let displayingIndex = (previousDisplayingImageIndex ?? removingIndex) > removingIndex
            ? removingIndex - 1
            : removingIndex
        self.images.remove(at: removingIndex)
        self.updateDisplayingImage(index: min(max(displayingIndex, 0), self.images.count - 1))
    }

    func loadImage(at index: Int, options: IFImage.LoadOptions,
                   sender: ImageDisplayingView,
                   completion: ((IFImage.Result) -> Void)? = nil) {
        guard let image = images[safe: index] else { return }

        switch image[options.kind] {
        case let .image(image):
            sender.nuke_display(image: image, data: nil)
            completion?(.success((options.kind, image)))

        case let .asset(asset):
            // Required
            let size = options.preferredSize ?? CGSize(width: asset.pixelWidth, height: asset.pixelHeight)
#if DEBUG
            print("[ImageUI]", "Requesting \(asset.localIdentifier) at size \(size).")
#endif

            let request = PHImageRequestOptions()
            // Avoid resizing if no preference is set.
            if options.preferredSize == nil {
                request.resizeMode = .none
            }
            // Determine system delivery mode according to various options.
            switch options.deliveryMode {
            case .highQuality:
                request.deliveryMode = .highQualityFormat
            case .opportunistic:
                request.deliveryMode = .opportunistic
            }

            self.photosManager.requestImage(for: asset,
                                            targetSize: size,
                                            contentMode: .aspectFit, options: request) { image, userInfo in
                if let image = image {
#if DEBUG
                    print("[ImageUI]", "Loaded \(asset.localIdentifier) at size \(image.size).")
#endif
                    sender.nuke_display(image: image, data: nil)

                    if (userInfo?[PHImageResultIsDegradedKey] as? NSNumber)?.boolValue == true {
                        completion?(.success((kind: .thumbnail, resource: image)))
                        return
                    }

                    completion?(.success((kind: .original, resource: image)))
                    return
                }

#if DEBUG
                print("[ImageUI]", "Loading of \(asset.localIdentifier) failed.")
#endif

                if (userInfo?[PHImageCancelledKey] as? NSNumber)?.boolValue == true {
                    completion?(.failure(IFError.cancelled))
                    return
                }

                if let error = userInfo?[PHImageErrorKey] as? Error {
                    completion?(.failure(error))
                    return
                }

                completion?(.failure(IFError.failed))
            }

        case .url:
            guard let url = image[options.kind].url else { return }

            if options.allowsThumbnail, let thumbnailImage = thumbnailImage(at: index) {
                completion?(.success((.thumbnail, thumbnailImage)))
            }

            let priority: ImageRequest.Priority

            if index == self.displayingImageIndex {
                priority = options.kind == .original ? .veryHigh : .high
            } else {
                priority = .normal
            }

            let request = ImageRequest(
                url: url,
                processors: options.preferredSize.map { [ImageProcessors.Resize(size: $0)] } ?? [],
                priority: priority
            )

            var loadingOptions = ImageLoadingOptions(
                placeholder: image.placeholder ?? self.placeholderImage,
                transition: .fadeIn(duration: 0.1, options: .curveEaseOut)
            )
            loadingOptions.pipeline = self.pipeline

            Nuke.loadImage(with: request, options: loadingOptions, into: sender, completion: { result in
                completion?(result.map { (options.kind, $0.image) }.mapError { $0 })
            })
        }
    }

    private func thumbnailImage(at index: Int) -> UIImage? {
        guard let thumbnail = images[safe: index]?.thumbnail else { return nil }
        switch thumbnail {
        case let .image(image):
            return image
        default:
            guard let url = thumbnail.url else { return nil }
            return self.pipeline.cache[url]?.image
        }
    }

    func sharingImage(forImageAt index: Int, completion: @escaping (Result<IFSharingImage, Error>) -> Void) {
        guard let image = images[safe: index] else { return }

        let prepareSharingImage = { [weak self] (result: Result<UIImage, Error>) in
            let sharingResult: Result<IFSharingImage, Error> = result
                .map {
                    if #available(iOS 13.0, *) {
                        self?.prepareDisplayingMetadataIfNeeded()
                        return IFSharingImage(container: image, image: $0, metadata: self?.displayingLinkMetadata)
                    } else {
                        return IFSharingImage(container: image, image: $0)
                    }
                }.mapError { $0 }

            completion(sharingResult)
        }

        switch image[.original] {
        case let .image(image):
            prepareSharingImage(.success(image))
        case let source:
            guard let url = source.url else { return }
            self.pipeline.loadImage(with: url, completion: { result in
                prepareSharingImage(result.map(\.image).mapError { $0 })
            })
        }
    }

    private func prepareDisplayingMetadataIfNeeded() {
        guard self.displayingLinkMetadata?.imageProvider == nil else { return }
        self.prepareDisplayingMetadata()
    }

    private func prepareDisplayingMetadata() {
        guard let image = images[safe: displayingImageIndex] else { return }
        let metadata = LPLinkMetadata()
        metadata.title = image.title
        metadata.originalURL = image.original.url

        switch image[.original] {
        case let .image(image):
            self.linkMetadataTask = nil
            let provider = NSItemProvider(object: image)
            metadata.imageProvider = provider
            metadata.iconProvider = provider
        case let source:
            guard let url = source.url else { return }
            let request = ImageRequest(url: url, priority: .low)
            linkMetadataTask = self.pipeline.loadImage(with: request, completion: { result in
                if case let .success(response) = result {
                    let provider = NSItemProvider(object: response.image)
                    metadata.imageProvider = provider
                    metadata.iconProvider = provider
                }
            })
        }

        self.displayingLinkMetadata = metadata
    }
}
