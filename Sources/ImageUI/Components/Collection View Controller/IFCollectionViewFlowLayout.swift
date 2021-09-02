import UIKit

//
//  IFCollectionViewFlowLayout.swift
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

class IFCollectionViewFlowLayout: UICollectionViewFlowLayout {
    enum Style {
        case carousel
        case flow
    }

    struct Transition {
        let indexPath: IndexPath
        let progress: CGFloat

        init(indexPath: IndexPath, progress: CGFloat = 1) {
            self.indexPath = indexPath
            self.progress = progress
        }
    }

    // MARK: - Public properties

    var style: Style
    private(set) var centerIndexPath: IndexPath
    var verticalPadding: CGFloat = 1
    var minimumItemWidthMultiplier: CGFloat = 0.5
    var maximumItemWidthMultiplier: CGFloat = 34 / 9
    var maximumLineSpacingMultiplier: CGFloat = 0.26

    var maximumItemWidth: CGFloat {
        itemSize.width * self.maximumItemWidthMultiplier
    }

    var preferredOffBoundsPadding: CGFloat {
        if let collectionView = collectionView {
            return collectionView.bounds.width / 4
        } else {
            return (self.maximumLineSpacing - minimumLineSpacing) * 2 + (self.maximumItemWidth - itemSize.width)
        }
    }

    var isTransitioning: Bool {
        self.transition.progress > 0 && self.transition.progress < 1
    }

    // MARK: - Accessory properties

    private var transition: Transition
    private var animatedLayoutAttributes: [IndexPath: UICollectionViewLayoutAttributes] = [:]
    private var deletingIndexPath: IndexPath?
    private var centerIndexPathBeforeUpdate: IndexPath?
    private var preferredItemsRatio: [IndexPath: CGFloat] = [:]
    private lazy var maximumLineSpacing = minimumLineSpacing
    private var needsInitialContentOffset: Bool

    init(style: Style = .carousel, centerIndexPath: IndexPath, needsInitialContentOffset: Bool = false) {
        self.style = style
        self.centerIndexPath = centerIndexPath
        self.needsInitialContentOffset = needsInitialContentOffset
        self.transition = Transition(indexPath: centerIndexPath)
        super.init()
        self.setup()
    }

    required init?(coder: NSCoder) {
        self.style = .carousel
        self.centerIndexPath = IndexPath(item: 0, section: 0)
        self.needsInitialContentOffset = false
        self.transition = Transition(indexPath: self.centerIndexPath)
        super.init(coder: coder)
        self.setup()
    }

    private func setup() {
        minimumLineSpacing = 1
        scrollDirection = .horizontal
    }
}

extension IFCollectionViewFlowLayout {
    // MARK: - Public methods

    func indexPath(forContentOffset contentOffset: CGPoint) -> IndexPath {
        let itemsRange = (0...(collectionView.map { $0.numberOfItems(inSection: 0) - 1 } ?? 0))
        let itemIndex = (contentOffset.x + minimumLineSpacing / 2) / (itemSize.width + minimumLineSpacing)
        let normalizedIndex = min(max(Int(itemIndex), itemsRange.lowerBound), itemsRange.upperBound)
        return IndexPath(item: normalizedIndex, section: 0)
    }

    func shouldInvalidateLayout(forPreferredItemSizeAt indexPath: IndexPath) -> Bool {
        guard indexPath == self.centerIndexPath, self.style == .carousel, !self.isTransitioning else { return false }
        let previousRatio = self.preferredItemsRatio[indexPath]
        updatePreferredItemSize()
        return previousRatio != self.preferredItemsRatio[indexPath]
    }

    func update(centerIndexPath: IndexPath, shouldInvalidate: Bool = false) {
        self.centerIndexPath = centerIndexPath
        self.transition = Transition(indexPath: centerIndexPath)
        updatePreferredItemSize()

        guard shouldInvalidate else { return }

        if let collectionView = collectionView {
            let context = UICollectionViewFlowLayoutInvalidationContext()
            context.contentOffsetAdjustment.x = contentOffsetX(forItemAt: centerIndexPath) - collectionView
                .contentOffset.x
            invalidateLayout(with: context)
        } else {
            invalidateLayout()
        }
    }

    func setupTransition(to indexPath: IndexPath, progress: CGFloat = 1) {
        let progress = min(max(progress, 0), 1)
        transition = Transition(indexPath: indexPath, progress: progress)
        updatePreferredItemSize()

        if progress == 1 {
            self.centerIndexPath = indexPath
        }
    }
}

// MARK: - UICollectionViewFlowLayout - Overrides

extension IFCollectionViewFlowLayout {
    override func prepare() {
        self.update()
        setInitialContentOffsetIfNeeded()
        super.prepare()
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        guard let superAttributes = super.layoutAttributesForElements(in: rect) else { return nil }

        var layoutAttributes: [UICollectionViewLayoutAttributes] = []
        for superAttribute in superAttributes {
            guard let layoutAttribute = superAttribute.copy() as? UICollectionViewLayoutAttributes else { continue }
            layoutAttribute.size = size(forItemAt: layoutAttribute.indexPath)
            layoutAttribute.frame.origin = CGPoint(
                x: originX(forItemAt: layoutAttribute.indexPath),
                y: self.verticalPadding
            )
            layoutAttributes.append(layoutAttribute)
        }

        return layoutAttributes
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        guard let superAttributes = super.layoutAttributesForItem(at: indexPath) else { return nil }
        guard let layoutAttributes = superAttributes.copy() as? UICollectionViewLayoutAttributes
        else { return superAttributes }
        layoutAttributes.size = size(forItemAt: layoutAttributes.indexPath)
        layoutAttributes.frame.origin = CGPoint(
            x: originX(forItemAt: layoutAttributes.indexPath),
            y: self.verticalPadding
        )
        return layoutAttributes
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        let isSameSize = collectionView?.bounds.size == newBounds.size
        return !isSameSize || !self.animatedLayoutAttributes.isEmpty || self.deletingIndexPath != nil
    }

    override func shouldInvalidateLayout(
        forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
    ) -> Bool {
        let oldRatio = self.preferredItemsRatio[preferredAttributes.indexPath]
        let newRatio = preferredAttributes.size.width / preferredAttributes.size.height
        self.preferredItemsRatio[preferredAttributes.indexPath] = newRatio
        return oldRatio != newRatio
    }

    override func invalidationContext(
        forPreferredLayoutAttributes preferredAttributes: UICollectionViewLayoutAttributes,
        withOriginalAttributes originalAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutInvalidationContext {
        let context = UICollectionViewFlowLayoutInvalidationContext()
        switch originalAttributes.indexPath {
        case self.centerIndexPath, self.transition.indexPath:
            if let collectionView = collectionView, style == .carousel, !isTransitioning {
                context.contentOffsetAdjustment.x =
                    contentOffsetX(forItemAt: self.centerIndexPath) - collectionView.contentOffset.x
            }
        default:
            break
        }

        return context
    }

    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint,
        withScrollingVelocity velocity: CGPoint
    ) -> CGPoint {
        guard let collectionView = collectionView else { return proposedContentOffset }
        let minimumContentOffsetX = -collectionView.contentInset.left.rounded(.up)
        let maximumContentOffsetX = (collectionView.contentSize.width - collectionView.bounds.width + collectionView
            .contentInset.right).rounded(.down)
        if proposedContentOffset.x <= minimumContentOffsetX || proposedContentOffset.x >= maximumContentOffsetX {
            return proposedContentOffset
        } else {
            let targetIndexPath = self.indexPath(forContentOffset: proposedContentOffset)
            return CGPoint(x: contentOffsetX(forItemAt: targetIndexPath), y: proposedContentOffset.y)
        }
    }

    override func targetContentOffset(forProposedContentOffset proposedContentOffset: CGPoint) -> CGPoint {
        if let centerIndexPathBeforeUpdate = centerIndexPathBeforeUpdate {
            let centerItemOffsetX = contentOffsetX(forItemAt: centerIndexPathBeforeUpdate)
            let contentOffsetX = centerIndexPathBeforeUpdate > self
                .centerIndexPath ? centerItemOffsetX - minimumLineSpacing - itemSize.width : centerItemOffsetX
            return CGPoint(x: contentOffsetX, y: proposedContentOffset.y)
        } else {
            let centerItemOffsetX = contentOffsetX(forItemAt: centerIndexPath)
            let transitionItemOffsetX = contentOffsetX(forItemAt: transition.indexPath)
            let targetOffsetX = centerItemOffsetX - self.transition
                .progress * (centerItemOffsetX - transitionItemOffsetX)
            return CGPoint(x: targetOffsetX, y: proposedContentOffset.y)
        }
    }
}

// MARK: - UICollectionViewFlowLayout - Updates

extension IFCollectionViewFlowLayout {
    override func prepare(forCollectionViewUpdates updateItems: [UICollectionViewUpdateItem]) {
        defer { super.prepare(forCollectionViewUpdates: updateItems) }
        guard let collectionView = collectionView else { return }
        assert(updateItems.count == 1 && updateItems[0].updateAction == .delete,
               "IFCollectionViewFlowLayout \(self) does not support multiple collection view updates")

        if let updateItem = updateItems.first(where: { $0.updateAction == .delete }) {
            self.deletingIndexPath = updateItem.indexPathBeforeUpdate
            if self.centerIndexPath == self.deletingIndexPath {
                let item = min(centerIndexPath.item + 1, collectionView.numberOfItems(inSection: 0))
                self.centerIndexPathBeforeUpdate = IndexPath(item: item, section: 0)
            } else {
                self.centerIndexPathBeforeUpdate = self.centerIndexPath
            }
        }

        if collectionView.numberOfItems(inSection: 0) > 0 {
            updatePreferredItemSize(forItemIndexPaths: self.centerIndexPathBeforeUpdate.map { [$0] })
        }
    }

    override func finalizeCollectionViewUpdates() {
        defer { super.finalizeCollectionViewUpdates() }
        guard let deletingIndexPath = deletingIndexPath else { return }
        self.preferredItemsRatio = self.preferredItemsRatio.reduce(into: [:]) { result, tuple in
            switch tuple.key.item {
            case 0..<deletingIndexPath.item:
                result[tuple.key] = tuple.value
            case deletingIndexPath.item:
                return
            default:
                result[IndexPath(item: tuple.key.item - 1, section: tuple.key.section)] = tuple.value
            }
        }

        self.deletingIndexPath = nil
        self.centerIndexPathBeforeUpdate = nil
    }

    override func prepare(forAnimatedBoundsChange oldBounds: CGRect) {
        defer { super.prepare(forAnimatedBoundsChange: oldBounds) }
        guard let collectionView = collectionView, oldBounds.size != collectionView.bounds.size else { return }
        self.update()
        let rect = collectionView.bounds.union(oldBounds)
        self.animatedLayoutAttributes = self.layoutAttributesForElements(in: rect)?
            .reduce(into: [:]) { $0[$1.indexPath] = $1 } ?? [:]
    }

    override func finalizeAnimatedBoundsChange() {
        self.animatedLayoutAttributes = [:]
        super.finalizeAnimatedBoundsChange()
    }

    override func prepareForTransition(to newLayout: UICollectionViewLayout) {
        defer { super.prepareForTransition(to: newLayout) }
        guard let flowLayout = newLayout as? IFCollectionViewFlowLayout else { return }
        updatePreferredItemSize(forItemIndexPaths: [
            self.centerIndexPath,
            self.transition.indexPath,
            flowLayout.centerIndexPath,
            flowLayout.transition.indexPath,
        ])
        flowLayout.preferredItemsRatio = self.preferredItemsRatio
    }

    override func initialLayoutAttributesForAppearingItem(at itemIndexPath: IndexPath)
    -> UICollectionViewLayoutAttributes? {
        guard self.animatedLayoutAttributes[itemIndexPath] == nil
        else { return self.animatedLayoutAttributes[itemIndexPath]! }
        let attribute = super.initialLayoutAttributesForAppearingItem(at: itemIndexPath)
        attribute?.alpha = 1
        attribute?.size = size(forItemAt: itemIndexPath)
        attribute?.frame.origin = CGPoint(x: originX(forItemAt: itemIndexPath), y: self.verticalPadding)
        return attribute
    }

    override func finalLayoutAttributesForDisappearingItem(at itemIndexPath: IndexPath)
    -> UICollectionViewLayoutAttributes? {
        let attribute = super.finalLayoutAttributesForDisappearingItem(at: itemIndexPath)
        attribute?.alpha = 1
        attribute?.size = finalLayoutAttributesSize(forItemAt: itemIndexPath)
        attribute?.frame.origin = CGPoint(
            x: finalLayoutAttributesOriginX(forItemAt: itemIndexPath),
            y: self.verticalPadding
        )
        return attribute
    }
}

// MARK: - Private methods

private extension IFCollectionViewFlowLayout {
    // MARK: Size

    func size(forItemAt indexPath: IndexPath) -> CGSize {
        guard self.style == .carousel,
              indexPath == self.centerIndexPath || indexPath == self.transition.indexPath else { return itemSize }

        let preferredWidth = self.preferredSize(forItemAt: indexPath).width
        let sizeMultiplier = indexPath == self.transition.indexPath ? self.transition
            .progress : (1 - self.transition.progress)
        let width = itemSize.width + (preferredWidth - itemSize.width) * sizeMultiplier
        return CGSize(width: width, height: itemSize.height)
    }

    func preferredSize(forItemAt indexPath: IndexPath) -> CGSize {
        guard self.style == .carousel, let preferredItemRatio = preferredItemsRatio[indexPath] else { return itemSize }
        let widthRange = itemSize.width...self.maximumItemWidth
        let preferredWidth = min(
            max(itemSize.height * preferredItemRatio, widthRange.lowerBound),
            widthRange.upperBound
        )
        return CGSize(width: preferredWidth, height: itemSize.height)
    }

    func finalLayoutAttributesSize(forItemAt indexPath: IndexPath) -> CGSize {
        switch indexPath {
        case self.deletingIndexPath:
            return CGSize(width: 0, height: itemSize.height)
        case self.centerIndexPathBeforeUpdate:
            return self.preferredSize(forItemAt: indexPath)
        default:
            return self.size(forItemAt: indexPath)
        }
    }

    // MARK: Position

    /// It computes the origin's x-coordinate of a layout attribute.
    ///
    ///      [][][][][][]  [  ]  [][][]   [   ]   [][][][]
    ///     |   before   | min  | mid  |   max   |  over  |
    ///
    /// - Parameter indexPath: The layout attribute's index path
    /// - Returns: The x-coordinate of the point that specifies the coordinates of the layout attribute's origin.
    func originX(forItemAt indexPath: IndexPath) -> CGFloat {
        let minimumPreviewingIndexPath = min(centerIndexPath, transition.indexPath)
        let maximumPreviewingIndexPath = max(centerIndexPath, transition.indexPath)

        guard self.style == .carousel, indexPath >= minimumPreviewingIndexPath else { // before
            return CGFloat(indexPath.item) * minimumLineSpacing + CGFloat(indexPath.item) * itemSize
                .width + sectionInset.left
        }

        let centerIndexLineSpacing = minimumLineSpacing + (maximumLineSpacing - minimumLineSpacing) *
            (1 - self.transition.progress)
        let transitionIndexLineSpacing = minimumLineSpacing + (maximumLineSpacing - minimumLineSpacing) * self
            .transition.progress
        let minimumPreviewingLineSpacing = minimumPreviewingIndexPath == self.centerIndexPath && self.transition
            .indexPath != self.centerIndexPath ? centerIndexLineSpacing : transitionIndexLineSpacing
        let maximumPreviewingLineSpacing = maximumPreviewingIndexPath == self
            .centerIndexPath ? centerIndexLineSpacing : transitionIndexLineSpacing
        let minimumPreviewingWidth = self.size(forItemAt: minimumPreviewingIndexPath).width
        let maximumPreviewingWidth = self.size(forItemAt: maximumPreviewingIndexPath).width
        let numberOfMiddleItems = CGFloat(max(maximumPreviewingIndexPath.item - minimumPreviewingIndexPath.item - 1, 0))
        let numberOfMiddleSpaces = CGFloat(max(numberOfMiddleItems - 1, 0))
        let beforeItemsMaxX = CGFloat(minimumPreviewingIndexPath.item) * itemSize
            .width + max(CGFloat(minimumPreviewingIndexPath.item - 1), 0) * minimumLineSpacing + sectionInset.left

        let itemPositionX: CGFloat
        switch indexPath {
        case minimumPreviewingIndexPath: // min
            itemPositionX = beforeItemsMaxX + minimumPreviewingLineSpacing
        case let indexPath
            where indexPath > minimumPreviewingIndexPath && indexPath < maximumPreviewingIndexPath: // middle
            let previousItemsMaxX = beforeItemsMaxX + minimumPreviewingLineSpacing * 2
            switch indexPath.item {
            case minimumPreviewingIndexPath.item + 1:
                itemPositionX = previousItemsMaxX + minimumPreviewingWidth
            default:
                let middleItemsMultiplier = CGFloat(indexPath.item - minimumPreviewingIndexPath.item - 1)
                itemPositionX = previousItemsMaxX + minimumPreviewingWidth + middleItemsMultiplier * itemSize
                    .width + middleItemsMultiplier * minimumLineSpacing
            }
        case maximumPreviewingIndexPath: // max
            let minimumPreviewingOffset = beforeItemsMaxX + minimumPreviewingLineSpacing * 2 + minimumPreviewingWidth
            let middleItemsOffset = numberOfMiddleItems * itemSize.width + numberOfMiddleSpaces * minimumLineSpacing
            itemPositionX = minimumPreviewingOffset + middleItemsOffset + maximumPreviewingLineSpacing
        default: // over
            let minimumPreviewingOffset = beforeItemsMaxX + minimumPreviewingLineSpacing * 2 + minimumPreviewingWidth
            let middleItemsOffset = numberOfMiddleItems * itemSize.width + numberOfMiddleSpaces * minimumLineSpacing
            let maximumPreviewingOffset = self.transition.indexPath != self
                .centerIndexPath ? maximumPreviewingLineSpacing * 2 + maximumPreviewingWidth : 0
            let overItemsMultiplier = CGFloat(indexPath.item - maximumPreviewingIndexPath.item - 1)
            itemPositionX = minimumPreviewingOffset + middleItemsOffset + maximumPreviewingOffset +
                overItemsMultiplier *
                itemSize.width + overItemsMultiplier * minimumLineSpacing
        }

        return itemPositionX
    }

    func finalLayoutAttributesOriginX(forItemAt indexPath: IndexPath) -> CGFloat {
        guard
            let deletingIndexPath = deletingIndexPath,
            let centerIndexPathBeforeUpdate = centerIndexPathBeforeUpdate else {
            return self.originX(forItemAt: indexPath)
        }

        switch indexPath {
        case deletingIndexPath:
            let defaultOriginX = self.originX(forItemAt: indexPath)
            if indexPath < centerIndexPathBeforeUpdate {
                return defaultOriginX - self.maximumLineSpacing
            } else {
                return defaultOriginX - minimumLineSpacing
            }
        case centerIndexPathBeforeUpdate:
            let defaultOriginX = self.originX(forItemAt: indexPath)

            if indexPath < deletingIndexPath {
                return defaultOriginX
            } else {
                return defaultOriginX -
                    (self.preferredSize(forItemAt: deletingIndexPath).width + self.maximumLineSpacing)
            }
        case let indexPath where (0..<deletingIndexPath.item).contains(indexPath.item):
            return self.originX(forItemAt: indexPath)
        default:
            var defaultOriginX = self.originX(forItemAt: indexPath)

            if centerIndexPathBeforeUpdate > deletingIndexPath {
                let deletingSizeDelta = self.preferredSize(forItemAt: centerIndexPathBeforeUpdate).width - self
                    .preferredSize(forItemAt: deletingIndexPath).width
                defaultOriginX += deletingSizeDelta
            }

            return defaultOriginX - itemSize.width - minimumLineSpacing
        }
    }

    func contentOffsetX(forItemAt indexPath: IndexPath) -> CGFloat {
        let previousItemOffset = CGFloat(indexPath.item) * itemSize
            .width + CGFloat(indexPath.item - 1) * minimumLineSpacing

        switch self.style {
        case .flow:
            return previousItemOffset + minimumLineSpacing + itemSize.width / 2
        case .carousel:
            return previousItemOffset + self.maximumLineSpacing + self.preferredSize(forItemAt: indexPath).width / 2
        }
    }

    func update() {
        guard let collectionView = collectionView else { return }
        let height = collectionView.bounds.height - self.verticalPadding * 2
        itemSize = CGSize(width: height * self.minimumItemWidthMultiplier, height: height)
        let horizontalPadding = collectionView.bounds.width / 2
        sectionInset = UIEdgeInsets(
            top: self.verticalPadding,
            left: horizontalPadding,
            bottom: self.verticalPadding,
            right: horizontalPadding
        )
        self.maximumLineSpacing = height * self.maximumLineSpacingMultiplier
    }

    func setInitialContentOffsetIfNeeded() {
        guard self.needsInitialContentOffset, let collectionView = collectionView else { return }
        self.needsInitialContentOffset = false
        collectionView.contentOffset.x = self.contentOffsetX(forItemAt: self.centerIndexPath)
    }

    func updatePreferredItemSize(forItemIndexPaths indexPaths: [IndexPath]? = nil) {
        guard let collectionView = collectionView else { return }
        let preferredIndexPaths = indexPaths ?? [centerIndexPath, transition.indexPath]
        var processedIndices: Set<IndexPath> = []

        for preferredIndexPath in preferredIndexPaths where !processedIndices.contains(preferredIndexPath) {
            defer { processedIndices.insert(preferredIndexPath) }

            guard
                let layoutAttribute = layoutAttributesForItem(at: preferredIndexPath),
                let cell = collectionView.cellForItem(at: preferredIndexPath) else { continue }

            let preferredAttribute = cell.preferredLayoutAttributesFitting(layoutAttribute)
            preferredItemsRatio[preferredIndexPath] = preferredAttribute.size.width / preferredAttribute.size.height
        }
    }
}
