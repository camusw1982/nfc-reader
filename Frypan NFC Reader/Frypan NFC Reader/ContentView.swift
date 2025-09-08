//
//  ContentView.swift
//  Frypan NFC Reader
//
//  Created by Wong Chi Man on 3/9/2025.
//

import SwiftUI
import CoreNFC

struct ContentView: View {
    var body: some View {
        NFCReaderView()
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
