//
//  BeautifulMechGradient.swift
//  Frypan NFC Reader
//
//  Created by Wong Chi Man on 20/9/2025.
//

import SwiftUI

struct BeautifulMechGradient: View {
    @State var appear = false
    @State var appear2 = false
    var body: some View {
        
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0] , [0.5, 0.0], [1, 0.0],
                [0.0, 0.5], appear ? [0.5, 0.5] : [0.8, 0.5], appear ? [1.0, 0.5] : [1.0, 0.8],
                [0.0, 1.0], appear2 ? [0.1, 1.0] : [0.5, 1.0], [1.0, 1.0]
            ], colors: [
                .black.opacity(0.4), .blue.opacity(0.4), .brown.opacity(0.5),
                .brown.opacity(0.2), .black.opacity(0.6), .blue.opacity(0.2),
                .black.opacity(0.5), .blue.opacity(0.3), .blue.opacity(0.1)
            ])
        .onAppear {
            withAnimation (.easeInOut(duration: 6).repeatForever(autoreverses: true)){
                appear.toggle()
            }
            withAnimation (.easeInOut(duration: 3).repeatForever(autoreverses: true)){
                appear2.toggle()
            }
        }
        .ignoresSafeArea()
    }
}

#Preview {
    BeautifulMechGradient()
}
