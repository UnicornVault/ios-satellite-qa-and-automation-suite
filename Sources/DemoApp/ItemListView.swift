//
//  ItemListView.swift
//  DemoApp
//
//  Navigation title "ItemList" matches what testSuccessfulLogin in
//  LoginTests.swift waits for via app.navigationBars["ItemList"].
//
//  Author: UnicornVault
//

import SwiftUI

struct ItemListView: View {
    private let items = ["Item 1", "Item 2", "Item 3"]

    var body: some View {
        List(items, id: \.self) { item in
            Text(item)
        }
        .navigationTitle("ItemList")
    }
}

#Preview {
    NavigationStack {
        ItemListView()
    }
}
