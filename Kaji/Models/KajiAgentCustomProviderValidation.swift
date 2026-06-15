struct KajiAgentCustomProviderValidation: Hashable {
    var ok: Bool
    var severity: String
    var title: String
    var message: String
    var statusCode: Int?
    var modelID: String?
    var keySource: String
    var keyName: String?
    var keyResolved: Bool
    var keyMatchesAzureResource: Bool?

    init(json: KajiAgentJSONValue?) {
        let object = json?.objectValue ?? [:]
        ok = object["ok"]?.boolValue ?? false
        severity = object["severity"]?.stringValue ?? "error"
        title = object["title"]?.stringValue ?? "Connection validation failed"
        message = object["message"]?.stringValue ?? "Unable to validate provider connection."
        statusCode = object["statusCode"]?.numberAsInt
        modelID = object["modelId"]?.stringValue
        let keyStatus = object["keyStatus"]?.objectValue ?? [:]
        keySource = keyStatus["source"]?.stringValue ?? "none"
        keyName = keyStatus["name"]?.stringValue
        keyResolved = keyStatus["resolved"]?.boolValue ?? false
        keyMatchesAzureResource = object["keyMatchesAzureResource"]?.boolValue
    }

    var summary: String {
        var parts = [title, message]
        if let statusCode { parts.append("HTTP \(statusCode)") }
        if let modelID { parts.append("Model \(modelID)") }
        return parts.joined(separator: " - ")
    }
}
