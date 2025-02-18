import AppKit

class GlobalObserver {
    private static func onNotif(_ notification: Notification) {
        // Third line of defence against lock screen window. See: closedWindowsCache
        // Second and third lines of defence are technically needed only to avoid potential flickering
        if (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier == lockScreenAppBundleId {
            return
        }
        refreshAndLayout(.globalObserver(notification.name.rawValue), screenIsDefinitelyUnlocked: false)
    }

    private static func onHideApp(_ notification: Notification) {
        refreshSession(.globalObserver(notification.name.rawValue), screenIsDefinitelyUnlocked: false) {
            if TrayMenuModel.shared.isEnabled && config.automaticallyUnhideMacosHiddenApps {
                if let w = prevFocus?.windowOrNil,
                   w.macAppUnsafe.nsApp.isHidden,
                   // "Hide others" (cmd-alt-h) -> don't force focus
                   // "Hide app" (cmd-h) -> force focus
                   MacApp.allAppsMap.values.filter({ $0.nsApp.isHidden }).count == 1
                {
                    // Force focus
                    _ = w.focusWindow()
                    _ = w.nativeFocus()
                }
                // Iterate over all apps and only unhide those not in the exceptions list.
                for app in MacApp.allAppsMap.values {
                    if let bundleId = app.nsApp.bundleIdentifier,
                       config.automaticallyUnhideMacosHiddenAppsExceptions.contains(bundleId) {
                        // Skip un-hiding this app because it's in the exceptions list.
                        continue
                    }
                    app.nsApp.unhide()
                }
            }
        }
    }

    static func initObserver() {
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didHideApplicationNotification, object: nil, queue: .main, using: onHideApp)
        nc.addObserver(forName: NSWorkspace.didUnhideApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didDeactivateApplicationNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main, using: onNotif)
        nc.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main, using: onNotif)

        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { _ in // todo reduce number of refreshSession
            resetClosedWindowsCache()
            resetManipulatedWithMouseIfPossible()
            let mouseLocation = mouseLocation
            let clickedMonitor = mouseLocation.monitorApproximation
            let focus = focus
            switch () {
                // Detect clicks on desktop of different monitors
                case _ where clickedMonitor.activeWorkspace != focus.workspace:
                    _ = refreshSession(.globalObserverLeftMouseUp, screenIsDefinitelyUnlocked: true) {
                        clickedMonitor.activeWorkspace.focusWorkspace()
                    }
                // Detect close button clicks for unfocused windows. Yes, kAXUIElementDestroyedNotification is that unreliable
                case _ where  focus.windowOrNil?.getRect()?.contains(mouseLocation) == false: // todo replace getRect with preflushRect when it later becomes available
                    refreshAndLayout(.globalObserverLeftMouseUp, screenIsDefinitelyUnlocked: true)
                default:
                    break
            }
        }
    }
}
