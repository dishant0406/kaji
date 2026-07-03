enum KajiAgentHostToolCatalog {
    static let definitions: [KajiAgentHostToolDefinition] = KajiAgentBasicHostToolDefinitions.definitions
        + KajiAgentWorkspaceHostToolDefinitions.definitions
        + KajiAgentFFFHostToolDefinitions.definitions

    static let uriSchemes: [KajiAgentHostURISchemeDefinition] = [
        KajiAgentHostURISchemeDefinition(
            scheme: "kaji-file",
            description: "Read files from the active Kaji workspace.",
            writable: false,
            immutable: false
        ),
    ]
}
