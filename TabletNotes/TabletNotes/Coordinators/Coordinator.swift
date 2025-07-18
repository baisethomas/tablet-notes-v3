import Foundation
import SwiftUI

// ContentView is now in Views/ContentView.swift

protocol Coordinator: ObservableObject {
    associatedtype ContentViewType: View
    @ViewBuilder func start() -> ContentViewType
}

