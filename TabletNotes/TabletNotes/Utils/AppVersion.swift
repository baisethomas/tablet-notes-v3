//
//  AppVersion.swift
//  TabletNotes
//
//  Created by Claude for app version management.
//

import Foundation

/// Utility for managing app version information from the bundle
struct AppVersion {
    
    /// App version string (e.g., "1.0.0")
    static var version: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }
    
    /// Build number string (e.g., "123")
    static var build: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
    }
    
    /// Combined version and build string (e.g., "1.0.0 (Build 123)")
    static var versionAndBuild: String {
        return "Version: \(version) (Build \(build))"
    }
    
    /// Short version string for display (e.g., "v1.0.0")
    static var shortVersion: String {
        return "Version \(version)"
    }
    
    /// App name from bundle
    static var appName: String {
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
               Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ??
               "TabletNotes"
    }
    
    /// Bundle identifier
    static var bundleIdentifier: String {
        return Bundle.main.bundleIdentifier ?? "com.tabletnotes.app"
    }
    
    /// Check if this is a debug build
    static var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    /// Check if this is a TestFlight build
    static var isTestFlightBuild: Bool {
        guard let appStoreReceiptURL = Bundle.main.appStoreReceiptURL else {
            return false
        }
        return appStoreReceiptURL.lastPathComponent == "sandboxReceipt"
    }
    
    /// Check if this is an App Store build
    static var isAppStoreBuild: Bool {
        guard let appStoreReceiptURL = Bundle.main.appStoreReceiptURL else {
            return false
        }
        return appStoreReceiptURL.lastPathComponent == "receipt"
    }
    
    /// Build environment description
    static var buildEnvironment: String {
        if isDebugBuild {
            return "Debug"
        } else if isTestFlightBuild {
            return "TestFlight"
        } else if isAppStoreBuild {
            return "App Store"
        } else {
            return "Release"
        }
    }
    
    /// Full version info for debugging
    static var fullVersionInfo: String {
        return """
        \(appName) \(version) (\(build))
        Bundle ID: \(bundleIdentifier)
        Environment: \(buildEnvironment)
        """
    }
}