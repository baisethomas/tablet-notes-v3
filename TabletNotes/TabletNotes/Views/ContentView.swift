//
//  ContentView.swift
//  TabletNotes
//
//  Created by Baise Thomas on 6/6/25.
//

import Foundation
import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var showServiceTypeModal = false
    @State private var selectedServiceType: String? = nil
    var onStartRecording: ((String) -> Void)?
    var onViewPastSermons: (() -> Void)?
    let serviceTypes = ["Sermon", "Bible Study", "Youth Group", "Conference"]

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(title: "TabletNotes", showLogo: true, showSearch: true, showSettings: true)
            Spacer(minLength: 0)
            VStack(spacing: 24) {
                Text("Tablet Notes Home")
                    .font(.largeTitle)
                    .padding()
                Button("Start Recording") {
                    onStartRecording?("")
                }
                .buttonStyle(.borderedProminent)
                Button("View Past Sermons") {
                    onViewPastSermons?()
                }
                .foregroundColor(.blue)
                .padding(.top, 16)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview {
    ContentView()
}
