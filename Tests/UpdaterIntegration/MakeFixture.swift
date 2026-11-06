import CryptoKit
import Foundation

// Disposable signing material for the mock release, never imported into Keychain.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(
    to: directory.appendingPathComponent("private-key"), atomically: true, encoding: .utf8
)
let infoURL = directory.appendingPathComponent("UpdaterPreferencesCheck.app/Contents/Info.plist")
var info = try PropertyListSerialization.propertyList(from: Data(contentsOf: infoURL), format: nil) as! [String: Any]
info["CFBundleVersion"] = "9999.0.0"
info["CFBundleShortVersionString"] = "9999.0.0"
info["SUPublicEDKey"] = key.publicKey.rawRepresentation.base64EncodedString()
info["SURequireSignedFeed"] = true
info["SUVerifyUpdateBeforeExtraction"] = true
try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL)
