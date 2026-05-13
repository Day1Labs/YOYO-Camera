import UIKit

protocol CameraGestureHandlerDelegate: AnyObject {
    func didPinch(scale: CGFloat, state: UIGestureRecognizer.State)
    func didTap(at point: CGPoint)
    func didLongPress(at point: CGPoint, state: UIGestureRecognizer.State)
    func didSwipeLeft()
    func didSwipeRight()
    func didSwipeUp()
    func didSwipeDown()
    func didPanVerticallyOnLeftSide(delta: CGFloat, state: UIGestureRecognizer.State)
    func didPanVerticallyOnRightSide(delta: CGFloat, state: UIGestureRecognizer.State)
    func didPanVerticallyInCenter(delta: CGFloat, state: UIGestureRecognizer.State)
}

final class CameraGestureHandler: NSObject, UIGestureRecognizerDelegate {
    weak var delegate: CameraGestureHandlerDelegate?

    private weak var view: UIView?
    private let orientationManager: OrientationManager
    private var pinchGestureRecognizer: UIPinchGestureRecognizer!
    private var tapGestureRecognizer: UITapGestureRecognizer!
    private var longPressGestureRecognizer: UILongPressGestureRecognizer!
    private var panGestureRecognizer: UIPanGestureRecognizer!
    private var leftSwipeGestureRecognizer: UISwipeGestureRecognizer!
    private var rightSwipeGestureRecognizer: UISwipeGestureRecognizer!
    private var upSwipeGestureRecognizer: UISwipeGestureRecognizer!
    private var downSwipeGestureRecognizer: UISwipeGestureRecognizer!

    /// verticalrelated
    private enum PanSide {
        case left
        case right
        case center
    }

    private var currentPanSide: PanSide = .center
    private var lastPanTranslation: CGFloat = 0
    private var hasStartedVerticalPan: Bool = false

    init(view: UIView, delegate: CameraGestureHandlerDelegate, orientationManager: OrientationManager) {
        self.view = view
        self.delegate = delegate
        self.orientationManager = orientationManager
        super.init()
        setupGestures()
    }

    private func setupGestures() {
        guard let view else { return }

        pinchGestureRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGestureRecognizer.delegate = self
        view.addGestureRecognizer(pinchGestureRecognizer)

        tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGestureRecognizer.delegate = self
        view.addGestureRecognizer(tapGestureRecognizer)

        longPressGestureRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGestureRecognizer.minimumPressDuration = 0.5
        longPressGestureRecognizer.delegate = self
        view.addGestureRecognizer(longPressGestureRecognizer)

        panGestureRecognizer = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGestureRecognizer.delegate = self
        view.addGestureRecognizer(panGestureRecognizer)

        leftSwipeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleLeftSwipe(_:)))
        leftSwipeGestureRecognizer.direction = .left
        leftSwipeGestureRecognizer.delegate = self
        view.addGestureRecognizer(leftSwipeGestureRecognizer)

        rightSwipeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleRightSwipe(_:)))
        rightSwipeGestureRecognizer.direction = .right
        rightSwipeGestureRecognizer.delegate = self
        view.addGestureRecognizer(rightSwipeGestureRecognizer)

        upSwipeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleUpSwipe(_:)))
        upSwipeGestureRecognizer.direction = .up
        upSwipeGestureRecognizer.delegate = self
        view.addGestureRecognizer(upSwipeGestureRecognizer)

        downSwipeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(handleDownSwipe(_:)))
        downSwipeGestureRecognizer.direction = .down
        downSwipeGestureRecognizer.delegate = self
        view.addGestureRecognizer(downSwipeGestureRecognizer)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        delegate?.didPinch(scale: gesture.scale, state: gesture.state)
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: view)
        delegate?.didTap(at: point)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: view)
        delegate?.didLongPress(at: point, state: gesture.state)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let view else { return }

        switch gesture.state {
        case .began:
            lastPanTranslation = 0
            hasStartedVerticalPan = false
            let point = gesture.location(in: view)
            let orientation = orientationManager.currentDeviceOrientation

            // checkgesture(left side, right sidemiddle)
            // deviceorientation
            if orientation == .landscapeLeft {
                // Home button on the right, device top on the left. The user's left side is the device top area.
                let leftSideThreshold = view.bounds.height * 0.3
                let rightSideThreshold = view.bounds.height * 0.7

                if point.y <= leftSideThreshold {
                    currentPanSide = .left
                } else if point.y >= rightSideThreshold {
                    currentPanSide = .right
                } else {
                    currentPanSide = .center
                }
            } else if orientation == .landscapeRight {
                // Home button on the left, device top on the right. The user's left side is the device bottom area.
                let leftSideThreshold = view.bounds.height * 0.7
                let rightSideThreshold = view.bounds.height * 0.3

                if point.y >= leftSideThreshold {
                    currentPanSide = .left
                } else if point.y <= rightSideThreshold {
                    currentPanSide = .right
                } else {
                    currentPanSide = .center
                }
            } else {
                // portrait
                let leftSideThreshold = view.bounds.width * 0.3
                let rightSideThreshold = view.bounds.width * 0.7

                if point.x <= leftSideThreshold {
                    currentPanSide = .left
                } else if point.x >= rightSideThreshold {
                    currentPanSide = .right
                } else {
                    currentPanSide = .center
                }
            }

        case .changed:
            // onlyvertical
            if isPanGestureUserVertical(gesture) {
                // ifnot yet start,.began
                if !hasStartedVerticalPan {
                    switch currentPanSide {
                    case .left:
                        delegate?.didPanVerticallyOnLeftSide(delta: 0, state: .began)
                    case .right:
                        delegate?.didPanVerticallyOnRightSide(delta: 0, state: .began)
                    case .center:
                        delegate?.didPanVerticallyInCenter(delta: 0, state: .began)
                    }
                    hasStartedVerticalPan = true
                }

                switch currentPanSide {
                case .left:
                    handleLeftSideVerticalPan(gesture)
                case .right:
                    handleRightSideVerticalPan(gesture)
                case .center:
                    handleCenterVerticalPan(gesture)
                }
            }

        case .ended, .cancelled:
            // endneed to validateorientation, ifstart, end
            if hasStartedVerticalPan || isPanGestureUserVertical(gesture) {
                switch currentPanSide {
                case .left:
                    handleLeftSideVerticalPan(gesture)
                case .right:
                    handleRightSideVerticalPan(gesture)
                case .center:
                    handleCenterVerticalPan(gesture)
                }
            }
            hasStartedVerticalPan = false
            currentPanSide = .center

        default:
            break
        }
    }

    private func handleLeftSideVerticalPan(_ gesture: UIPanGestureRecognizer) {
        let userVerticalTranslation = getUserVerticalTranslation(gesture)

        let delta = userVerticalTranslation - lastPanTranslation
        lastPanTranslation = userVerticalTranslation

        delegate?.didPanVerticallyOnLeftSide(delta: delta, state: gesture.state)
    }

    private func handleRightSideVerticalPan(_ gesture: UIPanGestureRecognizer) {
        let userVerticalTranslation = getUserVerticalTranslation(gesture)

        let delta = userVerticalTranslation - lastPanTranslation
        lastPanTranslation = userVerticalTranslation

        delegate?.didPanVerticallyOnRightSide(delta: delta, state: gesture.state)
    }

    private func handleCenterVerticalPan(_ gesture: UIPanGestureRecognizer) {
        let userVerticalTranslation = getUserVerticalTranslation(gesture)

        let delta = userVerticalTranslation - lastPanTranslation
        lastPanTranslation = userVerticalTranslation

        delegate?.didPanVerticallyInCenter(delta: delta, state: gesture.state)
    }

    /// getvertical
    private func getUserVerticalTranslation(_ gesture: UIPanGestureRecognizer) -> CGFloat {
        guard let view else { return 0 }
        let translation = gesture.translation(in: view)
        let orientation = orientationManager.currentDeviceOrientation

        switch orientation {
        case .landscapeLeft:
            // Home button on the right; the device left side is below the user
            // Correction: dragging upward (toward the device right side) should be positive
            return -translation.x
        case .landscapeRight:
            // Home button on the left; the device right side is below the user
            // Correction: dragging upward (toward the device left side) should be positive
            return translation.x
        case .portraitUpsideDown:
            return -translation.y
        default:
            return translation.y
        }
    }

    /// Pan gesturewhetherverticalorientation(deviceorientation)
    private func isPanGestureUserVertical(_ gesture: UIPanGestureRecognizer) -> Bool {
        guard let view else { return false }

        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        let orientation = orientationManager.currentDeviceOrientation

        let userX: CGFloat
        let userY: CGFloat
        let userVX: CGFloat
        let userVY: CGFloat

        switch orientation {
        case .landscapeRight:
            userX = translation.y
            userY = translation.x
            userVX = velocity.y
            userVY = velocity.x
        case .landscapeLeft:
            userX = -translation.y
            userY = -translation.x
            userVX = -velocity.y
            userVY = -velocity.x
        case .portraitUpsideDown:
            userX = -translation.x
            userY = -translation.y
            userVX = -velocity.x
            userVY = -velocity.y
        default:
            userX = translation.x
            userY = translation.y
            userVX = velocity.x
            userVY = velocity.y
        }

        // The vertical component must be clearly larger than the horizontal component (at least 1.5x)
        let isVerticalByTranslation = abs(userY) > abs(userX) * 1.5
        let isVerticalByVelocity = abs(userVY) > abs(userVX) * 1.5

        // Either method is sufficient
        return isVerticalByTranslation || isVerticalByVelocity
    }

    @objc private func handleLeftSwipe(_ gesture: UISwipeGestureRecognizer) {
        if gesture.state == .recognized {
            handleDirectionalSwipe(physicalDirection: .left)
        }
    }

    @objc private func handleRightSwipe(_ gesture: UISwipeGestureRecognizer) {
        if gesture.state == .recognized {
            handleDirectionalSwipe(physicalDirection: .right)
        }
    }

    @objc private func handleUpSwipe(_ gesture: UISwipeGestureRecognizer) {
        if gesture.state == .recognized {
            handleDirectionalSwipe(physicalDirection: .up)
        }
    }

    @objc private func handleDownSwipe(_ gesture: UISwipeGestureRecognizer) {
        if gesture.state == .recognized {
            handleDirectionalSwipe(physicalDirection: .down)
        }
    }

    private func handleDirectionalSwipe(physicalDirection: UISwipeGestureRecognizer.Direction) {
        let userDirection = mapPhysicalDirectionToUserDirection(physicalDirection)

        switch userDirection {
        case .left:
            delegate?.didSwipeLeft()
        case .right:
            delegate?.didSwipeRight()
        case .up:
            delegate?.didSwipeUp()
        case .down:
            delegate?.didSwipeDown()
        default:
            break
        }
    }

    private func mapPhysicalDirectionToUserDirection(_ physicalDirection: UISwipeGestureRecognizer.Direction) -> UISwipeGestureRecognizer.Direction {
        let orientation = orientationManager.currentDeviceOrientation
        switch orientation {
        case .landscapeLeft: // Home button right. Device Top is User Left.
            switch physicalDirection {
            case .left: return .down // Device Left is User Bottom
            case .right: return .up // Device Right is User Top
            case .up: return .left // Device Top is User Left
            case .down: return .right // Device Bottom is User Right
            default: return physicalDirection
            }
        case .landscapeRight: // Home button left. Device Top is User Right.
            switch physicalDirection {
            case .left: return .up // Device Left is User Top
            case .right: return .down // Device Right is User Bottom
            case .up: return .right // Device Top is User Right
            case .down: return .left // Device Bottom is User Left
            default: return physicalDirection
            }
        case .portraitUpsideDown:
            switch physicalDirection {
            case .left: return .right
            case .right: return .left
            case .up: return .down
            case .down: return .up
            default: return physicalDirection
            }
        default:
            return physicalDirection
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        shouldAllowSimultaneousRecognition(between: gestureRecognizer, and: otherGestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer == panGestureRecognizer {
            let orientation = orientationManager.currentDeviceOrientation
            // Dynamic rule: the pan gesture (used to adjust parameters in the user's vertical direction) should wait for the filter-switch gesture (the user's horizontal direction) to fail
            if orientation == .landscapeLeft || orientation == .landscapeRight {
                // In landscape, the user's horizontal direction maps to physical up/down
                if otherGestureRecognizer == upSwipeGestureRecognizer || otherGestureRecognizer == downSwipeGestureRecognizer {
                    return true
                }
            } else {
                // In portrait, the user's horizontal direction maps to physical left/right
                if otherGestureRecognizer == leftSwipeGestureRecognizer || otherGestureRecognizer == rightSwipeGestureRecognizer {
                    return true
                }
            }
        }

        // The tap gesture must wait for the long-press gesture to fail before it can fire
        if gestureRecognizer is UITapGestureRecognizer, otherGestureRecognizer is UILongPressGestureRecognizer {
            return true
        }
        return false
    }

    private func shouldAllowSimultaneousRecognition(
        between _: UIGestureRecognizer,
        and _: UIGestureRecognizer
    ) -> Bool {
        // All gestures are currently forced to be mutually exclusive so a single touch triggers only one event
        false
    }
}
