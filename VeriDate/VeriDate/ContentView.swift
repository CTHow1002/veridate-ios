//
//  ContentView.swift
//  VeriDate
//
//  Created by Teik How Chan on 24/04/2026.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text(AppLanguageManager.localized("welcome_title"))
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
