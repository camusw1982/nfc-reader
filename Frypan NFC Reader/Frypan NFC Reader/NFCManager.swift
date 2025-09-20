//
//  NFCManager.swift
//  Frypan NFC Reader
//
//  Created by Wong Chi Man on 3/9/2025.
//

import Foundation
import CoreNFC
import SwiftUI

class NFCManager: NSObject, ObservableObject, NFCNDEFReaderSessionDelegate {

    // 統一消息常量
    static let defaultMessage = "準備讀取人物"

    @Published var message: String = defaultMessage
    @Published var isReading: Bool = false
    @Published var detectedTag: String?
    @Published var nfcTextContent: String = ""
    
    func startReading() {
        guard NFCTagReaderSession.readingAvailable else {
            DispatchQueue.main.async { [weak self] in
                self?.message = "此設備不支援 NFC 功能"
            }
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // 清空之前的內容
            self.nfcTextContent = ""
            self.detectedTag = nil
            self.isReading = true
            self.message = "正在讀取 NFC 標籤..."
        }
        
        // 使用 NDEF 讀取會話來讀取文本內容
        let ndefSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        ndefSession.alertMessage = "" // 清空系統提示
        ndefSession.begin()
    }
    
    func stopReading() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.isReading = false
            self.message = Self.defaultMessage
            self.detectedTag = nil
            self.nfcTextContent = ""
        }
    }
    
    // MARK: - 重置方法
    
    func reset() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.isReading = false
            self.message = Self.defaultMessage
            self.detectedTag = nil
            self.nfcTextContent = ""
        }
    }
    
    // MARK: - NFCNDEFReaderSessionDelegate
    
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        DispatchQueue.main.async { [weak self] in
            self?.message = "NFC 讀取器已啟動"
        }
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.isReading = false

            // 簡化錯誤處理 - 總是重置為預設消息
            self.message = Self.defaultMessage
        }
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // 這個方法在 iOS 13+ 中被棄用，使用下面的方法
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let firstTag = tags.first else {
            session.invalidate()
            return
        }
        
        session.connect(to: firstTag) { [weak self] error in
            if let error = error {
                session.invalidate(errorMessage: "連接失敗: \(error.localizedDescription)")
                return
            }
            
            guard let self = self else { return }
            
            firstTag.queryNDEFStatus { [weak self] status, capacity, error in
                if let error = error {
                    DispatchQueue.main.async {
                        self?.message = "查詢 NDEF 狀態失敗: \(error.localizedDescription)"
                    }
                    session.invalidate()
                    return
                }
                
                guard let self = self else { return }
                
                switch status {
                case .notSupported:
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.message = "此標籤不支援 NDEF 格式"
                        self.detectedTag = "不支援 NDEF 的標籤"
                    }
                    session.invalidate()
                    
                case .readOnly:
                    self.readNDEFMessage(from: firstTag, session: session)
                    
                case .readWrite:
                    self.readNDEFMessage(from: firstTag, session: session)
                    
                @unknown default:
                    DispatchQueue.main.async { [weak self] in
                        self?.message = "未知的 NDEF 狀態"
                    }
                    session.invalidate()
                }
            }
        }
    }
    
    private func readNDEFMessage(from tag: NFCNDEFTag, session: NFCNDEFReaderSession) {
        tag.readNDEF { [weak self] ndefMessage, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.message = "讀取 NDEF 消息失敗: \(error.localizedDescription)"
                }
                session.invalidate()
                return
            }
            
            guard let self = self else { return }
            
            if let ndefMessage = ndefMessage {
                self.parseNDEFMessage(ndefMessage)
            } else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.message = "NFC 標籤為空"
                    self.detectedTag = "空標籤"
                }
            }
            
            session.invalidate()
        }
    }
    
    private func parseNDEFMessage(_ ndefMessage: NFCNDEFMessage) {
        var textContents: [String] = []
        var tagInfo = "NDEF 標籤\n記錄數量: \(ndefMessage.records.count)"
        
        for (index, record) in ndefMessage.records.enumerated() {
            let payload = record.payload
            
            // 解析文本記錄
            if record.typeNameFormat == .nfcWellKnown && record.type == Data([0x54]) { // "T" for Text
                if let text = parseTextRecord(payload) {
                    textContents.append(text)
                    tagInfo += "\n記錄 \(index + 1): 文本\n內容: \(text)"
                }
            }
            // 解析 URI 記錄
            else if record.typeNameFormat == .nfcWellKnown && record.type == Data([0x55]) { // "U" for URI
                if let uri = parseURIRecord(payload) {
                    textContents.append(uri)
                    tagInfo += "\n記錄 \(index + 1): URI\n內容: \(uri)"
                }
            }
            // 顯示其他類型的記錄
            else {
                tagInfo += "\n記錄 \(index + 1): 未知類型\n類型: \(record.type.hexString)\n數據: \(payload.hexString)"
            }
        }
        
        // 確保在主線程更新 UI
        DispatchQueue.main.async {
            self.nfcTextContent = textContents.joined(separator: "\n")
            self.detectedTag = tagInfo
            self.message = textContents.isEmpty ? "未找到文本內容" : "成功讀取 NFC 標籤"
        }
    }
    
    private func parseTextRecord(_ payload: Data) -> String? {
        guard payload.count > 0 else { return nil }
        
        // 第一個字節包含語言長度和編碼
        let header = payload[0]
        let languageLength = Int(header & 0x3F) // 後6位是語言長度
        let isUTF16 = (header & 0x80) != 0 // 最高位表示編碼 (0=UTF-8, 1=UTF-16)
        
        guard payload.count > languageLength else { return nil }
        
        // 跳過語言代碼，獲取文本內容
        let textData = payload.subdata(in: (1 + languageLength)..<payload.count)
        
        if isUTF16 {
            return String(data: textData, encoding: .utf16)
        } else {
            return String(data: textData, encoding: .utf8)
        }
    }
    
    private func parseURIRecord(_ payload: Data) -> String? {
        guard payload.count > 0 else { return nil }
        
        // 第一個字節是 URI 前綴代碼
        let prefixCode = payload[0]
        let uriData = payload.subdata(in: 1..<payload.count)
        
        // URI 前綴映射
        let prefixes = [
            "", "http://www.", "https://www.", "http://", "https://",
            "tel:", "mailto:", "ftp://anonymous:anonymous@", "ftp://ftp.",
            "ftps://", "sftp://", "smb://", "nfs://", "ftp://", "dav://", "news:",
            "telnet://", "imap:", "rtsp://", "urn:", "pop:", "sip:", "sips:",
            "tftp:", "btspp://", "btl2cap://", "btgoep://", "tcpobex://",
            "irdaobex://", "file://", "urn:epc:id:", "urn:epc:tag:", "urn:epc:pat:",
            "urn:epc:raw:", "urn:epc:", "urn:nfc:"
        ]
        
        guard Int(prefixCode) < prefixes.count else { return nil }
        let prefix = prefixes[Int(prefixCode)]
        guard let uriString = String(data: uriData, encoding: .utf8) else { return nil }
        
        return prefix + uriString
    }
}

// Data 擴展用於轉換為十六進制字符串
extension Data {
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}