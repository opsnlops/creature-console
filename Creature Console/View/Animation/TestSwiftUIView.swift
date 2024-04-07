//
//  TestSwiftUIView.swift
//  Creature Console
//
//  Created by April White on 3/27/24.
//

import SwiftUI

struct TestSwiftUIView: View {
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
            .font(.largeTitle)
            .foregroundColor(Color.blue)
            .lineLimit(nil)
            .padding(.bottom, 30.0)
            .opacity(/*@START_MENU_TOKEN@*/0.5/*@END_MENU_TOKEN@*/)
         
         
            
            
            
        Text("hop hop")
            .font(.callout)
            .fontWeight(.bold)
    }
}

#Preview {
    TestSwiftUIView()
}
