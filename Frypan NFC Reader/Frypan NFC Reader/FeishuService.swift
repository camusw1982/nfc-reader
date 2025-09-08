//
//  FeishuService.swift
//  Frypan NFC Reader
//
//  Created by Claude on 8/9/2025.
//

import Foundation
import os.log

class FeishuService: ObservableObject {
    @Published var isValidating = false
    @Published var lastError: String?
    @Published var characterData: [String: Any]?
    
    private let logger = Logger(subsystem: "com.frypan.nfc.reader", category: "FeishuService")
    
    // Web Server 配置
    private let webServerBaseURL = "http://145.79.12.177:10001"
    
    // MARK: - Public Methods
    
    /// 驗證 character ID 是否有效並獲取 character 數據
    func validateCharacterID(_ characterID: String, completion: @escaping (Bool, [String: Any]?) -> Void) {
        guard !characterID.isEmpty else {
            handleError("Character ID 為空", completion: completion)
            return
        }
        
        logger.info("🔍 開始驗證 Character ID: \(characterID)")
        isValidating = true
        lastError = nil
        characterData = nil
        
        // 通過 web server 驗證 character ID
        validateCharacterIDViaWebServer(characterID, completion: completion)
    }
    
    /// 通過 web server 獲取 character 數據
    func getCharacterData(_ characterID: String, completion: @escaping ([String: Any]?) -> Void) {
        logger.info("📥 獲取 Character 數據: \(characterID)")
        
        let urlString = "\(webServerBaseURL)/api/character/\(characterID)"
        guard let url = URL(string: urlString) else {
            logger.error("❌ 無效的 URL: \(urlString)")
            completion(nil)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                self?.logger.error("❌ 網絡錯誤: \(error.localizedDescription)")
                completion(nil)
                return
            }
            
            guard let data = data else {
                self?.logger.error("❌ 無獲取到數據")
                completion(nil)
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    self?.logger.info("✅ 成功獲取 Character 數據")
                    completion(json)
                } else {
                    self?.logger.error("❌ 無法解析 Character 數據")
                    completion(nil)
                }
            } catch {
                self?.logger.error("❌ 解析 JSON 失敗: \(error.localizedDescription)")
                completion(nil)
            }
        }
        
        task.resume()
    }
    
    // MARK: - Private Methods
    
    /// 通過 web server 驗證 character ID
    private func validateCharacterIDViaWebServer(_ characterID: String, completion: @escaping (Bool, [String: Any]?) -> Void) {
        let urlString = "\(webServerBaseURL)/api/validate-character/\(characterID)"
        guard let url = URL(string: urlString) else {
            handleError("無效的 URL", completion: completion)
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0
        
        logger.info("🌐 請求 URL: \(urlString)")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isValidating = false
                
                if let error = error {
                    self?.handleError("網絡錯誤: \(error.localizedDescription)", completion: completion)
                    return
                }
                
                guard let data = data else {
                    self?.handleError("無獲取到數據", completion: completion)
                    return
                }
                
                // 解析響應
                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                        self?.logger.info("📥 收到響應: \(json)")
                        
                        // 檢查響應狀態
                        if let success = json["success"] as? Bool, success {
                            // 驗證成功
                            self?.logger.info("✅ Character ID \(characterID) 驗證成功")
                            
                            // 提取 character 數據
                            var characterData: [String: Any] = [:]
                            if let data = json["data"] as? [String: Any] {
                                characterData = data
                            }
                            
                            // 確保基本字段存在
                            characterData["character_id"] = characterID
                            self?.characterData = characterData
                            
                            completion(true, characterData)
                        } else {
                            // 驗證失敗
                            let errorMessage = json["message"] as? String ?? "Character ID 驗證失敗"
                            self?.handleError(errorMessage, completion: completion)
                        }
                    } else {
                        self?.handleError("無法解析服務器響應", completion: completion)
                    }
                } catch {
                    self?.handleError("解析 JSON 失敗: \(error.localizedDescription)", completion: completion)
                }
            }
        }
        
        task.resume()
    }
    
    private func handleError(_ message: String, completion: @escaping (Bool, [String: Any]?) -> Void) {
        DispatchQueue.main.async {
            self.isValidating = false
            self.lastError = message
            self.logger.error("❌ \(message)")
            completion(false, nil)
        }
    }
    
    // MARK: - 測試用方法（開發時使用）
    
    /// 測試用的驗證方法（模擬網絡請求）
    func testValidateCharacterID(_ characterID: String, completion: @escaping (Bool, [String: Any]?) -> Void) {
        logger.info("🧪 測試驗證 Character ID: \(characterID)")
        isValidating = true
        lastError = nil
        characterData = nil
        
        // 模擬網絡延遲
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.isValidating = false
            
            // 簡單的驗證邏輯：ID 必須是數字且在 1-6 之間
            if let id = Int(characterID), id >= 1 && id <= 6 {
                self.logger.info("✅ 測試：Character ID \(characterID) 驗證成功")
                
                // 模擬 character 數據
                let characterData: [String: Any] = [
                    "character_id": id,
                    "name": "Character \(id)",
                    "prompt": "這是 Character \(id) 的提示詞",
                    "voice_id": "voice_\(id)",
                    "available": true
                ]
                
                self.characterData = characterData
                completion(true, characterData)
            } else {
                self.handleError("測試：Character ID \(characterID) 無效（必須是 1-6 的數字）", completion: completion)
            }
        }
    }
}