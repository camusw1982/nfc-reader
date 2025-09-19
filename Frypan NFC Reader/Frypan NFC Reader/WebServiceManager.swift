import Foundation
import os.log

class WebServiceManager: ObservableObject {
    @Published var isSending = false
    @Published var lastError: String?
    @Published var lastResponse: String?

    private let serverURL: URL
    private let logger = Logger(subsystem: "com.frypan.nfc.reader", category: "WebService")

    init() {
        self.serverURL = Self.createServerURL()
        logger.info("WebServiceManager 初始化完成，服務器地址: \(self.serverURL.absoluteString)")
    }

    private static func createServerURL() -> URL {
        if let customURL = ProcessInfo.processInfo.environment["SERVER_URL"],
           let url = URL(string: customURL) {
            return url
        }

        return URL(string: "http://145.79.12.177:10000/api/speech-result")!
    }
  
    func sendSpeechResult(text: String, completion: @escaping (Bool) -> Void) {
        guard !text.isEmpty else {
            handleError("語音識別結果為空", completion: completion)
            return
        }

        logger.info("開始發送語音識別結果，長度: \(text.count) 字符")

        isSending = true
        lastError = nil

        sendViaHTTP(text: text, completion: completion)
    }
      
    private func sendViaHTTP(text: String, completion: @escaping (Bool) -> Void) {
        let requestData: [String: Any] = [
            "text": text,
            "timestamp": Date().timeIntervalSince1970,
            "language": "zh-HK",
            "device": "iOS"
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestData, options: [])

            var request = URLRequest(url: serverURL)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = jsonData

            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                DispatchQueue.main.async {
                    self?.isSending = false

                    if let error = error {
                        self?.handleError("網絡錯誤: \(error.localizedDescription)", completion: completion)
                        return
                    }

                    if let httpResponse = response as? HTTPURLResponse {
                        if httpResponse.statusCode == 200 {
                            if let data = data,
                               let responseString = String(data: data, encoding: .utf8) {
                                self?.lastResponse = responseString
                            }
                            completion(true)
                        } else {
                            self?.handleError("服務器錯誤 (狀態碼: \(httpResponse.statusCode))", completion: completion)
                        }
                    }
                }
            }

            task.resume()

        } catch {
            handleError("數據序列化失敗: \(error.localizedDescription)", completion: completion)
        }
    }

    private func handleError(_ message: String, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            self.isSending = false
            self.lastError = message
            self.logger.error("\(message)")
            completion(false)
        }
    }
}