//
//  SuggestionChipsView.swift
//  TabletNotes
//
//  Created by Claude Code
//

import SwiftUI

struct SuggestionChipsView: View {
    let questions: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Suggested Questions")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.adaptiveSecondaryText)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(questions, id: \.self) { question in
                        Button(action: {
                            onSelect(question)
                        }) {
                            Text(question)
                                .font(.subheadline)
                                .foregroundColor(.adaptivePrimaryText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                .background(Color.adaptiveCardBackground)
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(Color.adaptiveBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 12)
    }
}
