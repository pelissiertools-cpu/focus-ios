//
//  ShareSheetHelper.swift
//  Focus IOS
//

import SwiftUI
import LinkPresentation

/// Presents the native share sheet for sharing a task/project/list via link.
@MainActor
enum ShareSheetHelper {
    private static let shareRepository = ShareRepository()

    static func share(task: FocusTask) {
        _Concurrency.Task { @MainActor in
            do {
                let token = try await shareRepository.createShare(taskId: task.id, ownerId: task.userId)
                let url = URL(string: "focusapp://share/\(token)")!

                // Delay to let context menu dismiss before presenting
                try? await _Concurrency.Task.sleep(for: .milliseconds(600))

                presentShareSheet(with: url, title: task.title)
            } catch {
                print("[ShareSheetHelper] Failed to create share: \(error)")
            }
        }
    }

    private static func presentShareSheet(with url: URL, title: String) {
        let itemSource = ShareItemSource(url: url, title: title)

        let activityVC = UIActivityViewController(
            activityItems: [itemSource],
            applicationActivities: nil
        )

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first?.rootViewController else { return }

        // Find the topmost presented controller
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        // iPad popover anchor
        if let popover = activityVC.popoverPresentationController {
            popover.sourceView = topVC.view
            popover.sourceRect = CGRect(x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }

        topVC.present(activityVC, animated: true)
    }
}

// MARK: - Rich Link Preview

/// Provides rich metadata (title + app icon) for the share sheet preview.
private final class ShareItemSource: NSObject, UIActivityItemSource {
    let url: URL
    let title: String

    init(url: URL, title: String) {
        self.url = url
        self.title = title
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        url
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        title
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.originalURL = url
        metadata.title = title

        // Generate a hero image for a large card-style preview in Messages.
        // imageProvider gives a big card; iconProvider gives a tiny badge.
        if let heroImage = Self.renderShareImage() {
            metadata.imageProvider = NSItemProvider(object: heroImage)
        }

        return metadata
    }

    /// Renders the app icon centered on a branded background for the share card.
    private static func renderShareImage() -> UIImage? {
        guard let appIcon = UIImage(named: "AppIcon60x60") else { return nil }

        let size = CGSize(width: 300, height: 300)
        let iconSize: CGFloat = 120
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            // Background matching app theme
            UIColor(red: 45/255, green: 27/255, blue: 61/255, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Draw app icon centered with rounded corners
            let iconRect = CGRect(
                x: (size.width - iconSize) / 2,
                y: (size.height - iconSize) / 2,
                width: iconSize,
                height: iconSize
            )
            let clipPath = UIBezierPath(roundedRect: iconRect, cornerRadius: iconSize * 0.22)
            clipPath.addClip()
            appIcon.draw(in: iconRect)
        }
    }
}
