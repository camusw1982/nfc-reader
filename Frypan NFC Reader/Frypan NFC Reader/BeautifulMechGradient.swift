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
    @State var appear3 = false
    var colorLiter = #colorLiteral(red: 0.8078431487, green: 0.02745098062, blue: 0.3333333433, alpha: 1)
    var body: some View {
        ZStack{
            MeshGradient(width: 2,
                         height: 2,
                         points: [
                            [0.0, 0.0] , [1.0, 0.0],
                            [0.0, 1.0] , [1.0, 1.0]
            ], colors: [.blue.opacity(0.2), .purple.opacity(0.2),
                        .purple.opacity(0.1), .blue.opacity(0.2)
            ])
            .ignoresSafeArea()
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0] , appear2 ? [0.2, 0.0] : [0.6, 0.0], [1, 0.0],
                appear2 ? [0.0, 0.0] : [0.0, 0.8], appear3 ? [0.5, 0.1] : [0.3, 0.9], appear ? [1.0, 0.3] : [1.0, 0.8],
                [0.0, 1.0], appear3 ? [0.2, 1.0] : [0.5, 1.0], [1.0, 1.0]
            ], colors: [
                .black.opacity(0.5), .blue.opacity(0.2), .cyan.opacity(0.4),
                .cyan.opacity(0.2), .black.opacity(0.3), .black.opacity(0.3),
                .black.opacity(0.7), .cyan.opacity(0.2), .blue.opacity(0.4)
            ])
        .onAppear {
            withAnimation (.easeInOut(duration: 6).repeatForever(autoreverses: true)){
                appear.toggle()
            }
            withAnimation (.easeInOut(duration: 3).repeatForever(autoreverses: true)){
                appear2.toggle()
            }
            withAnimation (.easeInOut(duration: 8).repeatForever(autoreverses: true)){
                appear3.toggle()
            }
        }
        .ignoresSafeArea()
    }
    }
}

#Preview {
    BeautifulMechGradient()
}
