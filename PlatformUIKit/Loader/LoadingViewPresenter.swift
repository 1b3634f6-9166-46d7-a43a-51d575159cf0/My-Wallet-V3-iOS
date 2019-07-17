//
//  LoadingViewDisplayer.swift
//  PlatformUIKit
//
//  Created by Chris Arriola on 4/19/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import Foundation
import UIKit

/// Presenter in charge of displaying a loading overlay, that entirely covers the current context
@objc final public class LoadingViewPresenter: NSObject, LoadingViewPresenting {

    // MARK: - Types
    
    /// The style of the loading view
    enum LoadingViewStyle {
        
        /// Activity indicator style (legacy design)
        case activityIndicator
        
        /// Circle style (new design)
        case circle
    }
    
    /// Describes the state of the loader
    enum State {
        
        /// Animating state with associated `String?` as textual display
        case animating(String?)
        
        /// Hidden state
        case hidden
        
        /// Returns `true` if the loader is currently animating
        var isAnimating: Bool {
            switch self {
            case .animating:
                return true
            case .hidden:
                return false
            }
        }
    }
    
    // MARK: - Properties
    
    /// The shared instance of the loading view
    public static let shared = LoadingViewPresenter()
    
    /// sharedInstance function declared so that the LoadingViewPresenter singleton can be accessed
    /// from Obj-C. Should deprecate this once all Obj-c references have been removed.
    @objc public class func sharedInstance() -> LoadingViewPresenter { return shared }

    /// Returns `true` if the loader is currently visible and animating
    @objc public var isVisible: Bool {
        return state.isAnimating
    }
        
    /// Controls the availability of the loader from outside.
    /// In case `isEnabled` is `false`, the loader does not show.
    /// `isEnabled` is thread-safe.
    @objc public var isEnabled: Bool {
        set {
            lock.lock()
            defer { lock.unlock() }
            self._isEnabled = newValue
        }
        get {
            lock.lock()
            defer { lock.unlock() }
            return _isEnabled
        }
    }
    
    // Should be privately used by exposed `isEnabled` only.
    private var _isEnabled = true
    
    // The container of the loader. Allocated on demand, when done spinning it should be deallocated.
    private var view: LoadingViewProtocol!
    
    // Recursive lock for shared resources held by that class
    private let lock = NSRecursiveLock()
    
    /// The state of the loader
    private var state = State.hidden {
        didSet {
            switch (oldValue, state) {
            case (.hidden, .animating(let string)):
                view.animate(from: oldValue, text: string)
            case (.animating(let oldString), .animating(let newString)) where oldString != newString:
                view.animate(from: oldValue, text: newString)
            case (.animating, .hidden):
                view.fadeOut()
            case (.hidden, .hidden), (.animating, .animating):
                break
            }
        }
    }
    
    // MARK: - API

    /// Hides the loader
    @objc public func hide() {
        Execution.MainQueue.dispatch { [weak self] in
            guard let self = self else { return }
            guard self.view != nil else { return }
            self.state = .hidden
            self.view = nil
        }
    }
    
    /// Shows the circular loader
    /// - Parameter superview: An optional `UIView` to show the loader in.
    /// if `nil` the loader is shown in one of the windows.
    /// - Parameter text: an optional String to be displayed
    @objc public func showCircular(in superview: UIView? = nil, with text: String? = nil) {
        Execution.MainQueue.dispatch { [weak self] in
            guard let self = self, self.isEnabled else { return }
            self.setupViewIfNeeded(in: superview, style: .circle)
            self.state = .animating(text)
        }
    }
    
    /// Shows the legacy loader
    /// - Parameter superview: An optional `UIView` to show the loader in.
    /// if `nil` the loader is shown in one of the windows.
    /// - Parameter text: an optional String to be displayed
    @objc public func show(in superview: UIView? = nil, with text: String? = nil) {
        Execution.MainQueue.dispatch { [weak self] in
            guard let self = self, self.isEnabled else { return }
            self.setupViewIfNeeded(in: superview, style: .activityIndicator)
            self.state = .animating(text)
        }
    }
    
    /// Shows the circular loader (attached to a window)
    /// - Parameter text: an optional String to be displayed
    @objc public func showCircular(with text: String? = nil) {
        showCircular(in: nil, with: text)
    }
    
    /// Shows the legacy loader (attached to a window)
    /// - Parameter text: an optional String to be displayed
    @objc public func show(with text: String? = nil) {
        show(in: nil, with: text)
    }
    
    // MARK: - Accessors
    
    private func setupViewIfNeeded(in superview: UIView? = nil, style: LoadingViewPresenter.LoadingViewStyle) {
        guard view == nil else { return }
        switch style {
        case .circle:
            view = LoadingContainerView()
        case .activityIndicator:
            view = ActivityIndicatorLoadingContainerView()
        }
        if let superview = superview {
            attach(to: superview)
        } else {
            attachToTopWindow()
        }
    }
    
    /// Add the view to a superview
    private func attach(to superview: UIView) {
        superview.addSubview(view.viewRepresentation)
        view.viewRepresentation.layoutToSuperview(.horizontal, .vertical)
        superview.layoutIfNeeded()
    }

    /* TODO: Might be better to move this logic to a "presentation manager", with a queuing
     mechanism, in a disignated window, and give it the highest display priority.
     That's how we will be able to manage contexts of `UIView`s and `UIViewController`s
     in a more sofisticated way, worries-free. */
    /// Attach the view to the current top window
    private func attachToTopWindow() {
        guard !isVisible else { return }

        // Extract the top window. must not be `nil`
        let topWindow = UIApplication.shared.windows
            .reversed()
            .first { window -> Bool in
                let onMainScreen = window.screen == .main
                let isVisible = !window.isHidden && window.alpha > 0
                
                let isLevelNormalOrStatusBar = window.windowLevel == .normal || window.windowLevel == .statusBar
                return onMainScreen && isVisible && isLevelNormalOrStatusBar
        }!
        attach(to: topWindow)
    }
}
