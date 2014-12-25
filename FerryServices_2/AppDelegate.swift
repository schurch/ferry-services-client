//
//  AppDelegate.swift
//  FerryServices_2
//
//  Created by Stefan Church on 19/07/2014.
//  Copyright (c) 2014 Stefan Church. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
                            
    var window: UIWindow?

    func application(application: UIApplication!, didFinishLaunchingWithOptions launchOptions: NSDictionary!) -> Bool {
        
        Flurry.setCrashReportingEnabled(false)
        Flurry.startSession("48Q89W7B39FXGJK9BSW6")
        
        Crashlytics.startWithAPIKey("9aad7798d2e2d712649ba35bd1747beeac29b07f")

        AFNetworkActivityIndicatorManager.sharedManager().enabled = true
        
        self.window?.tintColor = UIColor(red:0.13, green:0.75, blue:0.67, alpha:1)
        
        return true
    }
}

