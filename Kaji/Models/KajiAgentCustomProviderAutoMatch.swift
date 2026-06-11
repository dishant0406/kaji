struct KajiAgentCustomProviderAutoMatch: Hashable {
    var models: [KajiAgentCustomProviderModel]
    var accountName: String?
    var resourceGroup: String?
    var endpoint: String?

    init(json: KajiAgentJSONValue?) {
        let object = json?.objectValue ?? [:]
        models = object["models"]?.arrayValue?.map(KajiAgentCustomProviderModel.init(json:)) ?? []
        let account = object["account"]?.objectValue ?? [:]
        accountName = account["name"]?.stringValue
        resourceGroup = account["resourceGroup"]?.stringValue
        endpoint = account["endpoint"]?.stringValue
    }
}
