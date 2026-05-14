//
//  SceneDelegate.swift
//  iOS (App)
//
//  Created by Jacob Forcier on 4/28/26.
//

import UIKit
import SwiftUI

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: RootView())
        // Ripple is a dark-themed brand — lock the app to dark.
        window.overrideUserInterfaceStyle = .dark
        self.window = window
        window.makeKeyAndVisible()
    }
}
