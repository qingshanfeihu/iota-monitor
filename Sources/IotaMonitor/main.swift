//
//  main.swift
//  IotaMonitor
//

import Cocoa
import IotaMonitorCore

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
