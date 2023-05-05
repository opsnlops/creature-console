//
//  AnimationDetail.swift
//  Creature Console
//
//  Created by April White on 5/4/23.
//

import SwiftUI

struct AnimationDetail: View {
    let objectDetails: [String] = [
        "Detail 1", "Detail 2", "Detail 3",
        "Detail 4", "Detail 5", "Detail 6",
        "Detail 7", "Detail 8", "Detail 9"
    ]
    
    var body: some View {
        ScrollView(.horizontal) {
            LazyHGrid(rows: Array(repeating: .init(.flexible()), count: 3), spacing: 16) {
                ForEach(objectDetails, id: \.self) { detail in
                    Text(detail)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding()
            LazyHGrid(rows: Array(repeating: .init(.flexible()), count: 3), spacing: 16) {
                ForEach(objectDetails, id: \.self) { detail in
                    Text(detail)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .padding()
        }
    }
}

struct AnimationDetail_Preview: PreviewProvider {
    static var previews: some View {
        AnimationDetail()
    }
}
