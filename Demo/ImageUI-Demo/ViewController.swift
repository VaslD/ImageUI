import ImageUI
import Photos
import UIKit

//
//  ViewController.swift
//  ImageUI-Demo
//
//  Created by Alberto Saltarelli on 12/05/2020.
//  Copyright © 2020 Alberto Saltarelli. All rights reserved.
//

class ViewController: UIViewController {
    private var assets: [PHAsset] = []

    var browserViewController: IFBrowserViewController {
        let images = IFImage.mock + self.assets.map { IFImage(photoAsset: $0) }
        let viewController = IFBrowserViewController(images: images, initialImageIndex: .random(in: images.indices))
        viewController.configuration.actions = [.share, .delete]
        viewController.delegate = self
        return viewController
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        let assets = PHAsset.fetchAssets(with: .image, options: nil)
        self.assets = assets.objects(at: IndexSet(integersIn: 0..<assets.count))
    }

    @IBAction
    private func pushButtonDidTap() {
        navigationController?.pushViewController(self.browserViewController, animated: true)
    }

    @IBAction
    private func presentButtonDidTap() {
        let navigationController = UINavigationController(rootViewController: browserViewController)
        navigationController.modalPresentationStyle = .fullScreen
        present(navigationController, animated: true)
    }
}

// MARK: - ViewController + IFBrowserViewControllerDelegate

extension ViewController: IFBrowserViewControllerDelegate {
    func browserViewController(_ browserViewController: IFBrowserViewController,
                               didDeleteItemAt index: Int,
                               isEmpty: Bool) {
        guard isEmpty else { return }
        if navigationController?.topViewController === browserViewController {
            navigationController?.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
}
