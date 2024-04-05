//
//  FetchAnisetteDataOperation.swift
//  AltStore
//
//  Created by Riley Testut on 1/7/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CommonCrypto
import Starscream

import AltStoreCore
import AltSign
import Roxas

@objc(FetchAnisetteDataOperation)
final class FetchAnisetteDataOperation: ResultOperation<ALTAnisetteData>, WebSocketDelegate
{
    let context: OperationContext
    var socket: WebSocket!
    
    var url: URL?
    var startProvisioningURL: URL?
    var endProvisioningURL: URL?
    
    var clientInfo: String?
    var userAgent: String?
    
    var mdLu: String?
    var deviceId: String?
    
    init(context: OperationContext)
    {
        self.context = context
    }
    
    override func main()
    {
        super.main()
        
        if let error = self.context.error
        {
            self.finish(.failure(error))
            return
        }
        
        self.url = AnisetteManager.currentURL
        print("Anisette URL: \(self.url!.absoluteString)")
        
        if let identifier = Keychain.shared.identifier,
           let adiPb = Keychain.shared.adiPb {
            fetchAnisetteV3(identifier, adiPb)
        } else {
            provision()
        }
    }
    
    // MARK: - COMMON
    
    func extractAnisetteData(_ data: Data, _ response: HTTPURLResponse?, v3: Bool) throws {
        // make sure this JSON is in the format we expect
        // convert data to json
        if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
            if v3 {
                if json["result"] == "GetHeadersError" {
                    let message = json["message"]
                    print("Error getting V3 headers: \(message ?? "no message")")
                    if let message = message,
                       message.contains("-45061") {
                        print("Error message contains -45061 (not provisioned), resetting adi.pb and retrying")
                        Keychain.shared.adiPb = nil
                        return provision()
                    } else { throw OperationError.anisetteV3Error(message: message ?? "Unknown error") }
                }
            }
            
            // try to read out a dictionary
            // for some reason serial number isn't needed but it doesn't work unless it has a value
            var formattedJSON: [String: String] = ["deviceSerialNumber": "0"]
            if let machineID = json["X-Apple-I-MD-M"] { formattedJSON["machineID"] = machineID }
            if let oneTimePassword = json["X-Apple-I-MD"] { formattedJSON["oneTimePassword"] = oneTimePassword }
            if let routingInfo = json["X-Apple-I-MD-RINFO"] { formattedJSON["routingInfo"] = routingInfo }
            
            if v3 {
                formattedJSON["deviceDescription"] = self.clientInfo!
                formattedJSON["localUserID"] = self.mdLu!
                formattedJSON["deviceUniqueIdentifier"] = self.deviceId!
                
                // Generate date stuff on client
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.timeZone = TimeZone.current
                formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
                let dateString = formatter.string(from: Date())
                formattedJSON["date"] = dateString
                formattedJSON["locale"] = Locale.current.identifier
                formattedJSON["timeZone"] = TimeZone.current.abbreviation()
            } else {
                if let deviceDescription = json["X-MMe-Client-Info"] { formattedJSON["deviceDescription"] = deviceDescription }
                if let localUserID = json["X-Apple-I-MD-LU"] { formattedJSON["localUserID"] = localUserID }
                if let deviceUniqueIdentifier = json["X-Mme-Device-Id"] { formattedJSON["deviceUniqueIdentifier"] = deviceUniqueIdentifier }
                
                if let date = json["X-Apple-I-Client-Time"] { formattedJSON["date"] = date }
                if let locale = json["X-Apple-Locale"] { formattedJSON["locale"] = locale }
                if let timeZone = json["X-Apple-I-TimeZone"] { formattedJSON["timeZone"] = timeZone }
            }
            
            if let response = response,
               let version = response.value(forHTTPHeaderField: "Implementation-Version") {
                print("Implementation-Version: \(version)")
            } else { print("No Implementation-Version header") }
            
            print("Anisette used: \(formattedJSON)")
            print("Original JSON: \(json)")
            if let anisette = ALTAnisetteData(json: formattedJSON) {
                print("Anisette is valid!")
                self.finish(.success(anisette))
            } else {
                print("Anisette is invalid!!!!")
                if v3 {
                    throw OperationError.anisetteV3Error(message: "Invalid anisette (the returned data may not have all the required fields)")
                } else {
                    throw OperationError.anisetteV1Error(message: "Invalid anisette (the returned data may not have all the required fields)")
                }
            }
        } else {
            if v3 {
                throw OperationError.anisetteV3Error(message: "Invalid anisette (the returned data may not be in JSON)")
            } else {
                throw OperationError.anisetteV1Error(message: "Invalid anisette (the returned data may not be in JSON)")
            }
        }
    }
    
    // MARK: - V1
    
    func handleV1() {
        print("Server is V1")
        
        if UserDefaults.shared.trustedServerURL == AnisetteManager.currentURLString {
            print("Server has already been trusted, fetching anisette")
            return self.fetchAnisetteV1()
        }
        
        print("Alerting user about outdated server")
        let alert = UIAlertController(title: "WARNING: Outdated anisette server", message: "We've detected you are using an older anisette server. Using this server has a higher likelihood of locking your account and causing other issues. Are you sure you want to continue?", preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title: "Continue", style: UIAlertAction.Style.destructive, handler: { action in
            print("Fetching anisette via V1")
            UserDefaults.shared.trustedServerURL = AnisetteManager.currentURLString
            self.fetchAnisetteV1()
        }))
        alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertAction.Style.cancel, handler: { action in
            print("Cancelled anisette operation")
            self.finish(.failure(OperationError.cancelled))
        }))

        let keyWindow = UIApplication.shared.windows.filter { $0.isKeyWindow }.first

        DispatchQueue.main.async {
            if let presentingController = keyWindow?.rootViewController?.presentedViewController {
                presentingController.present(alert, animated: true)
            } else {
                keyWindow?.rootViewController?.present(alert, animated: true)
            }
        }
    }
    
    func fetchAnisetteV1() {
        print("Fetching anisette V1")
        URLSession.shared.dataTask(with: self.url!) { data, response, error in
            do {
                guard let data = data, error == nil else { throw OperationError.anisetteV1Error(message: "Unable to fetch data\(error != nil ? " (\(error!.localizedDescription))" : "")") }
                
                try self.extractAnisetteData(data, response as? HTTPURLResponse, v3: false)
            } catch let error as NSError {
                print("Failed to load: \(error.localizedDescription)")
                self.finish(.failure(error))
            }
        }.resume()
    }
    
    // MARK: - V3: PROVISIONING
    
    func provision() {
        fetchClientInfo {
            print("Getting provisioning URLs")
            var request = self.buildAppleRequest(url: URL(string: "https://gsa.apple.com/grandslam/GsService2/lookup")!)
            request.httpMethod = "GET"
            URLSession.shared.dataTask(with: request) { data, response, error in
                if let data = data,
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? Dictionary<String, Dictionary<String, Any>>,
                   let startProvisioningString = plist["urls"]?["midStartProvisioning"] as? String,
                   let startProvisioningURL = URL(string: startProvisioningString),
                   let endProvisioningString = plist["urls"]?["midFinishProvisioning"] as? String,
                   let endProvisioningURL = URL(string: endProvisioningString) {
                    self.startProvisioningURL = startProvisioningURL
                    self.endProvisioningURL = endProvisioningURL
                    print("startProvisioningURL: \(self.startProvisioningURL!.absoluteString)")
                    print("endProvisioningURL: \(self.endProvisioningURL!.absoluteString)")
                    print("Starting a provisioning session")
                    self.startProvisioningSession()
                } else {
                    print("Apple didn't give valid URLs! Got response: \(String(data: data ?? Data("nothing".utf8), encoding: .utf8) ?? "not utf8")")
                    self.finish(.failure(OperationError.provisioningError(result: "Apple didn't give valid URLs. Please try again later", message: nil)))
                }
            }.resume()
        }
    }
    
    func startProvisioningSession() {
        let provisioningSessionURL = self.url!.appendingPathComponent("v3").appendingPathComponent("provisioning_session")
        var wsRequest = URLRequest(url: provisioningSessionURL)
        wsRequest.timeoutInterval = 5
        self.socket = WebSocket(request: wsRequest)
        self.socket.delegate = self
        self.socket.connect()
    }
    
    func didReceive(event: WebSocketEvent, client: WebSocketClient) {
        switch event {
        case .text(let string):
            do {
                if let json = try JSONSerialization.jsonObject(with: string.data(using: .utf8)!, options: []) as? [String: Any] {
                    guard let result = json["result"] as? String else {
                        print("The server didn't give us a result")
                        client.disconnect(closeCode: 0)
                        self.finish(.failure(OperationError.provisioningError(result: "The server didn't give us a result", message: nil)))
                        return
                    }
                    print("Received result: \(result)")
                    switch result {
                    case "GiveIdentifier":
                        print("Giving identifier")
                        client.json(["identifier": Keychain.shared.identifier!])
                        
                    case "GiveStartProvisioningData":
                        print("Getting start provisioning data")
                        let body = [
                            "Header": [String: Any](),
                            "Request": [String: Any](),
                        ]
                        var request = self.buildAppleRequest(url: self.startProvisioningURL!)
                        request.httpMethod = "POST"
                        request.httpBody = try! PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
                        URLSession.shared.dataTask(with: request) { data, response, error in
                            if let data = data,
                               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? Dictionary<String, Dictionary<String, Any>>,
                               let spim = plist["Response"]?["spim"] as? String {
                                print("Giving start provisioning data")
                                client.json(["spim": spim])
                            } else {
                                print("Apple didn't give valid start provisioning data! Got response: \(String(data: data ?? Data("nothing".utf8), encoding: .utf8) ?? "not utf8")")
                                client.disconnect(closeCode: 0)
                                self.finish(.failure(OperationError.provisioningError(result: "Apple didn't give valid start provisioning data. Please try again later", message: nil)))
                            }
                        }.resume()
                        
                    case "GiveEndProvisioningData":
                        print("Getting end provisioning data")
                        guard let cpim = json["cpim"] as? String else {
                            print("The server didn't give us a cpim")
                            client.disconnect(closeCode: 0)
                            self.finish(.failure(OperationError.provisioningError(result: "The server didn't give us a cpim", message: nil)))
                            return
                        }
                        let body = [
                            "Header": [String: Any](),
                            "Request": [
                                "cpim": cpim,
                            ],
                        ]
                        var request = self.buildAppleRequest(url: self.endProvisioningURL!)
                        request.httpMethod = "POST"
                        request.httpBody = try! PropertyListSerialization.data(fromPropertyList: body, format: .xml, options: 0)
                        URLSession.shared.dataTask(with: request) { data, response, error in
                            if let data = data,
                               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? Dictionary<String, Dictionary<String, Any>>,
                               let ptm = plist["Response"]?["ptm"] as? String,
                               let tk = plist["Response"]?["tk"] as? String {
                                print("Giving end provisioning data")
                                client.json(["ptm": ptm, "tk": tk])
                            } else {
                                print("Apple didn't give valid end provisioning data! Got response: \(String(data: data ?? Data("nothing".utf8), encoding: .utf8) ?? "not utf8")")
                                client.disconnect(closeCode: 0)
                                self.finish(.failure(OperationError.provisioningError(result: "Apple didn't give valid end provisioning data. Please try again later", message: nil)))
                            }
                        }.resume()
                        
                    case "ProvisioningSuccess":
                        print("Provisioning succeeded!")
                        client.disconnect(closeCode: 0)
                        guard let adiPb = json["adi_pb"] as? String else {
                            print("The server didn't give us an adi.pb file")
                            self.finish(.failure(OperationError.provisioningError(result: "The server didn't give us an adi.pb file", message: nil)))
                            return
                        }
                        Keychain.shared.adiPb = adiPb
                        self.fetchAnisetteV3(Keychain.shared.identifier!, Keychain.shared.adiPb!)
                        
                    default:
                        if result.contains("Error") || result.contains("Invalid") || result == "ClosingPerRequest" || result == "Timeout" || result == "TextOnly" {
                            print("Failing because of \(result)")
                            self.finish(.failure(OperationError.provisioningError(result: result, message: json["message"] as? String)))
                        }
                    }
                }
            } catch let error as NSError {
                print("Failed to handle text: \(error.localizedDescription)")
                self.finish(.failure(OperationError.provisioningError(result: error.localizedDescription, message: nil)))
            }
            
        case .connected:
            print("Connected")
            
        case .disconnected(let string, let code):
            print("Disconnected: \(code); \(string)")
            
        case .error(let error):
            print("Got error: \(String(describing: error))")
            
        default:
            print("Unknown event: \(event)")
        }
    }
    
    func buildAppleRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(self.clientInfo!, forHTTPHeaderField: "X-Mme-Client-Info")
        request.setValue(self.userAgent!, forHTTPHeaderField: "User-Agent")
        request.setValue("text/x-xml-plist", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")

        request.setValue(self.mdLu!, forHTTPHeaderField: "X-Apple-I-MD-LU")
        request.setValue(self.deviceId!, forHTTPHeaderField: "X-Mme-Device-Id")

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        let dateString = formatter.string(from: Date())
        request.setValue(dateString, forHTTPHeaderField: "X-Apple-I-Client-Time")
        request.setValue(Locale.current.identifier, forHTTPHeaderField: "X-Apple-Locale")
        request.setValue(TimeZone.current.abbreviation(), forHTTPHeaderField: "X-Apple-I-TimeZone")
        return request
    }
    
    // MARK: - V3: FETCHING
    
    func fetchClientInfo(_ callback: @escaping () -> Void) {
        if  self.clientInfo != nil &&
                self.userAgent != nil &&
                self.mdLu != nil &&
                self.deviceId != nil &&
                Keychain.shared.identifier != nil {
            print("Skipping client_info fetch since all the properties we need aren't nil")
            return callback()
        }
        print("Trying to get client_info")
        let clientInfoURL = self.url!.appendingPathComponent("v3").appendingPathComponent("client_info")
        URLSession.shared.dataTask(with: clientInfoURL) { data, response, error in
            do {
                guard let data = data, error == nil else {
                    return self.finish(.failure(OperationError.anisetteV3Error(message: "Couldn't fetch client info. The server may be down\(error != nil ? " (\(error!.localizedDescription))" : "")")))
                }
                
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: String] {
                    if let clientInfo = json["client_info"] {
                        print("Server is V3")
                        
                        self.clientInfo = clientInfo
                        self.userAgent = json["user_agent"]!
                        print("Client-Info: \(self.clientInfo!)")
                        print("User-Agent: \(self.userAgent!)")
                        
                        if Keychain.shared.identifier == nil {
                            print("Generating identifier")
                            var bytes = [Int8](repeating: 0, count: 16)
                            let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
                            
                            if status != errSecSuccess {
                                print("ERROR GENERATING IDENTIFIER!!! \(status)")
                                return self.finish(.failure(OperationError.provisioningError(result: "Couldn't generate identifier", message: nil)))
                            }
                            
                            Keychain.shared.identifier = Data(bytes: &bytes, count: bytes.count).base64EncodedString()
                        }
                        
                        let decoded = Data(base64Encoded: Keychain.shared.identifier!)!
                        self.mdLu = decoded.sha256().hexEncodedString()
                        print("X-Apple-I-MD-LU: \(self.mdLu!)")
                        let uuid: UUID = decoded.object()
                        self.deviceId = uuid.uuidString.uppercased()
                        print("X-Mme-Device-Id: \(self.deviceId!)")
                        
                        callback()
                    } else { self.handleV1() }
                } else { self.finish(.failure(OperationError.anisetteV3Error(message: "Couldn't fetch client info. The returned data may not be in JSON"))) }
            } catch let error as NSError {
                print("Failed to load: \(error.localizedDescription)")
                self.handleV1()
            }
        }.resume()
    }
    
    func fetchAnisetteV3(_ identifier: String, _ adiPb: String) {
        fetchClientInfo {
            print("Fetching anisette V3")
            var request = URLRequest(url: self.url!.appendingPathComponent("v3").appendingPathComponent("get_headers"))
            request.httpMethod = "POST"
            request.httpBody = try! JSONSerialization.data(withJSONObject: [
                "identifier": identifier,
                "adi_pb": adiPb
            ], options: [])
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            URLSession.shared.dataTask(with: request) { data, response, error in
                do {
                    guard let data = data, error == nil else { throw OperationError.anisetteV3Error(message: "Couldn't fetch anisette") }
                    
                    try self.extractAnisetteData(data, response as? HTTPURLResponse, v3: true)
                } catch let error as NSError {
                    print("Failed to load: \(error.localizedDescription)")
                    self.finish(.failure(error))
                }
            }.resume()
        }
    }
}

extension WebSocketClient {
    func json(_ dictionary: [String: String]) {
        let data = try! JSONSerialization.data(withJSONObject: dictionary, options: [])
        self.write(string: String(data: data, encoding: .utf8)!)
    }
}

extension Data {
    // https://stackoverflow.com/a/25391020
    func sha256() -> Data {
        var hash = [UInt8](repeating: 0,  count: Int(CC_SHA256_DIGEST_LENGTH))
        self.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(self.count), &hash)
        }
        return Data(hash)
    }
    
    // https://stackoverflow.com/a/40089462
    func hexEncodedString() -> String {
        return self.map { String(format: "%02hhX", $0) }.joined()
    }
    
    // https://stackoverflow.com/a/59127761
    func object<T>() -> T { self.withUnsafeBytes { $0.load(as: T.self) } }
}
