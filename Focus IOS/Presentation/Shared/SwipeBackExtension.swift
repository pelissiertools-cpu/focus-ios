import UIKit
import ObjectiveC

// Replaces the edge-only back gesture with a full-width swipe-to-go-back gesture.
extension UINavigationController {
    override open func viewDidLoad() {
        super.viewDidLoad()
        setupFullWidthBackGesture()
    }

    private func setupFullWidthBackGesture() {
        guard let targets = interactivePopGestureRecognizer?.value(forKey: "targets") as? [AnyObject] else { return }

        let fullWidthGesture = UIPanGestureRecognizer()
        fullWidthGesture.setValue(targets, forKey: "targets")

        let gestureDelegate = FullWidthBackGestureDelegate(navigationController: self)
        fullWidthGesture.delegate = gestureDelegate

        // Retain delegate so it isn't deallocated
        objc_setAssociatedObject(self, &AssociatedKeys.gestureDelegate, gestureDelegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        view.addGestureRecognizer(fullWidthGesture)
        interactivePopGestureRecognizer?.isEnabled = false
    }
}

private enum AssociatedKeys {
    static var gestureDelegate: UInt8 = 0
}

private class FullWidthBackGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    weak var navigationController: UINavigationController?

    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = navigationController,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }

        // Block during an active transition
        guard nav.transitionCoordinator == nil else { return false }

        let velocity = pan.velocity(in: nav.view)

        // Only fire for a left-to-right swipe that is primarily horizontal
        return nav.viewControllers.count > 1
            && velocity.x > 0
            && abs(velocity.x) > abs(velocity.y)
    }
}
