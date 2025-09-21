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
    var body: some View {
        ZStack{
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0] , [0.5, 0.0], [1.0, 0.0],
                appear3 ? [0.0, 0.4] : [0.0, 0.6], appear2 ? [0.8, 0.5] : [0.2, 0.7], [1.0, 0.5],
                [0.0, 1.0], appear ? [0.4, 1.0] : [0.6, 1.0], [1.0, 1.0]
            ], colors: [
                .blue.opacity(0.3), .teal.opacity(0.4), .black.opacity(0.1),
                .black.opacity(0.1), .blue.opacity(0.2), .blue.opacity(0.3),
                .blue.opacity(0.2), .teal.opacity(0.2), .black.opacity(0.4),
            ])
            .ignoresSafeArea()
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0] , appear2 ? [0.2, 0.0] : [0.6, 0.0], [1, 0.0],
                appear ? [0.0, 0.2] : [0.0, 0.8], appear3 ? [0.3, 0.8] : [0.8, 0.5], appear ? [1.0, 0.2] : [1.0, 0.7],
                [0.0, 1.0], appear2 ? [0.3, 1.0] : [0.8, 1.0], [1.0, 1.0]
            ], colors: [
                .black.opacity(0.5), .blue.opacity(0.2), .cyan.opacity(0.4),
                .blue.opacity(0.2), .black.opacity(0.3), .black.opacity(0.3),
                .black.opacity(0.7), .cyan.opacity(0.2), .blue.opacity(0.4)
            ])
        .ignoresSafeArea()
        .onAppear {
            withAnimation (.easeInOut(duration: 6).repeatForever(autoreverses: true).delay(2)){
                appear.toggle()
            }
            withAnimation (.easeInOut(duration: 4).repeatForever(autoreverses: true).delay(1)){
                appear2.toggle()
            }
            withAnimation (.easeInOut(duration: 5).repeatForever(autoreverses: true).delay(4)){
                appear3.toggle()
            }
        }
        
    }
    }
}

#Preview {
    BeautifulMechGradient()
}
