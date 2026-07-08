import Foundation

enum AIGatewayClaudeCodeRouterPluginWriter {
    static func plugins() -> [[String: Any]] {
        let path = AIGatewayClaudeCodeRouterPaths.openAIResponsesPluginURL().path
        return [["enabled": true, "key": "kaji-openai-responses", "modulePath": path]]
    }

    static func writeOpenAIResponsesPlugin(fileManager: FileManager = .default) throws {
        let directory = AIGatewayClaudeCodeRouterPaths.pluginsDirectory()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let url = AIGatewayClaudeCodeRouterPaths.openAIResponsesPluginURL()
        try source.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static let source = #"""
    const ok = value => ({ ok: true, value });
    const err = error => ({ ok: false, error });
    const isObject = value => value && typeof value === "object" && !Array.isArray(value);
    const textValue = value => typeof value === "string" ? value.trim() : "";
    const adapter = {
      key: "kaji_openai_responses",
      provider: "openai",
      providerTypes: ["openai_responses"],
      buildRequestFromStandard(input) {
        const key = input.targetProviderConfig?.apikey || input.config?.openaiApiKey || process.env.OPENAI_API_KEY;
        if (!key) return err("OPENAI_API_KEY is missing.");
        const base = String(input.targetProviderConfig?.baseurl || input.config?.openaiBaseUrl || "").replace(/\/+$/, "");
        if (!base) return err("OpenAI Responses base URL is missing.");
        const body = compact({
          model: input.standardRequest.model,
          instructions: input.standardRequest.instructions,
          input: toResponsesInput(input.standardRequest.input),
          temperature: input.standardRequest.temperature,
          top_p: input.standardRequest.top_p,
          max_output_tokens: input.standardRequest.max_output_tokens,
          stop: input.standardRequest.stop,
          tools: mapTools(input.standardRequest.tools),
          tool_choice: mapToolChoice(input.standardRequest.tool_choice),
          reasoning: input.standardRequest.reasoning,
          thinking: input.standardRequest.thinking,
          output_config: input.standardRequest.output_config,
          stream: input.standardRequest.stream === true ? true : undefined
        });
        return ok({
          url: `${base.replace(/\/responses$/i, "")}/responses`,
          headers: {
            "content-type": "application/json",
            authorization: `Bearer ${key}`
          },
          body
        });
      },
      toStandardResponse(payload) {
        if (!isObject(payload)) return err("Invalid OpenAI response payload.");
        const outputText = textValue(payload.output_text) || extractOutputText(payload.output) || extractChatText(payload.choices);
        const calls = extractFunctionCalls(payload.output, payload.choices);
        const reasoning = extractReasoning(payload.output);
        if (!outputText && calls.length === 0 && reasoning.length === 0) {
          return err("OpenAI response does not contain text output, reasoning output, or tool calls.");
        }
        return ok({
          id: textValue(payload.id) || `resp_${Date.now()}`,
          object: "response",
          status: "completed",
          model: textValue(payload.model) || "unknown",
          output_text: outputText,
          output: responseOutput(outputText, calls, reasoning),
          usage: isObject(payload.usage) ? payload.usage : {},
          finish_reason: extractFinishReason(payload.choices)
        });
      }
    };
    function toResponsesInput(input) { return typeof input === "string" ? input : Array.isArray(input) ? input.flatMap(messageItems) : []; }
    function messageItems(message) {
      if (!isObject(message)) return [];
      const role = message.role === "assistant" ? "assistant" : "user";
      const content = Array.isArray(message.content) ? message.content : [];
      const items = [];
      const text = content.map(partText).filter(Boolean).join("\n").trim();
      if (text) {
        items.push({ type: "message", role, content: [{ type: textPartType(role), text }] });
      }
      if (role === "assistant") {
        items.push(...content.filter(part => part?.type === "reasoning").map(reasoningInputItem));
        items.push(...content.filter(part => part?.type === "tool_use").map(toolUseInputItem).filter(Boolean));
      } else {
        items.push(...content.filter(part => part?.type === "tool_result").map(toolResultInputItem).filter(Boolean));
      }
      return items;
    }
    const textTypes = ["text", "input_text", "output_text"];
    function partText(part) { return typeof part === "string" ? part : textTypes.includes(part?.type) ? textValue(part.text) : ""; }
    function textPartType(role) { return role === "assistant" ? "output_text" : "input_text"; }
    function reasoningInputItem(part) {
      return compact({
        type: "reasoning",
        id: part.id || `rs_${Date.now()}`,
        status: "completed",
        summary: part.summary ? [{ type: "summary_text", text: part.summary }] : undefined,
        content: part.text ? [{ type: "reasoning_text", text: part.text }] : undefined,
        encrypted_content: part.encrypted_content
      });
    }
    function toolUseInputItem(part) {
      const name = textValue(part.name);
      const callId = textValue(part.id);
      if (!name || !callId) return null;
      return { type: "function_call", call_id: callId, name, arguments: stringifyArguments(part.input) };
    }
    function toolResultInputItem(part) {
      const callId = textValue(part.tool_use_id || part.tool_call_id || part.call_id);
      if (!callId) return null;
      return { type: "function_call_output", call_id: callId, output: resultContent(part.content) };
    }
    function mapTools(tools) {
      const mapped = Array.isArray(tools) ? tools.map(mapTool).filter(Boolean) : [];
      return mapped.length ? mapped : undefined;
    }
    function mapTool(tool) {
      if (!isObject(tool)) return null;
      if (tool.type === "web_search" || tool.type === "web_search_preview") return compact({ type: tool.type, filters: tool.filters });
      if (tool.type === "web_search_20250305") return { type: "web_search" };
      if (tool.type === "namespace" && Array.isArray(tool.tools)) {
        const nested = tool.tools.map(mapTool).filter(Boolean);
        return nested.length ? compact({ type: "namespace", name: tool.name, description: tool.description, tools: nested }) : null;
      }
      const fn = isObject(tool.function) ? tool.function : {};
      const name = textValue(tool.name || fn.name);
      if (!name) return null;
      return compact({
        type: "function",
        name,
        description: textValue(tool.description || fn.description) || undefined,
        parameters: tool.parameters || tool.input_schema || fn.parameters || { type: "object", properties: {} },
        strict: typeof tool.strict === "boolean" ? tool.strict : fn.strict
      });
    }
    function mapToolChoice(choice) {
      if (choice === undefined || typeof choice === "string") return choice;
      if (!isObject(choice)) return undefined;
      if (["auto", "none"].includes(choice.type)) return choice.type;
      if (choice.type === "any" || choice.type === "required") return "required";
      const fn = isObject(choice.function) ? choice.function : {};
      const name = textValue(choice.name || fn.name);
      return name ? { type: "function", name } : choice;
    }
    function extractOutputText(output) {
      return Array.isArray(output) ? textFromParts(output.flatMap(item => Array.isArray(item?.content) ? item.content : [item])) : "";
    }
    function extractChatText(c) { return Array.isArray(c) ? textFromParts(c.map(x => x?.message?.content)) : ""; }
    function extractFunctionCalls(output, choices) {
      const responseCalls = Array.isArray(output) ? output.filter(item => item?.type === "function_call") : [];
      const chatCalls = Array.isArray(choices) ? choices.flatMap(choice => choice?.message?.tool_calls || []) : [];
      return [...responseCalls.map(responseCall), ...chatCalls.map(chatCall)].filter(Boolean);
    }
    function responseCall(item) {
      const callId = textValue(item.call_id || item.id);
      const name = textValue(item.name);
      return callItem(callId, name, item.arguments);
    }
    function chatCall(item) {
      const fn = isObject(item.function) ? item.function : {};
      const callId = textValue(item.id);
      const name = textValue(fn.name);
      return callItem(callId, name, fn.arguments);
    }
    function extractReasoning(output) { return Array.isArray(output) ? output.filter(item => item?.type === "reasoning") : []; }
    function responseOutput(text, calls, reasoning) {
      const output = [...reasoning, ...calls];
      if (text) output.unshift(messageItem(text));
      return output;
    }
    function resultContent(c) {
      if (typeof c === "string") return c;
      if (Array.isArray(c)) return textFromParts(c) || JSON.stringify(c);
      return c === undefined ? "" : JSON.stringify(c);
    }
    function stringifyArguments(value) { return typeof value === "string" ? value : JSON.stringify(value ?? {}); }
    function extractFinishReason(choices) { return Array.isArray(choices) ? textValue(choices[0]?.finish_reason) : undefined; }
    function textFromParts(parts) { return parts.map(partText).filter(Boolean).join("\n").trim(); }
    function callItem(callId, name, args) {
      return callId && name ? { type: "function_call", call_id: callId, id: callId, name, arguments: stringifyArguments(args) } : null;
    }
    function messageItem(text) {
      return { type: "message", role: "assistant", content: [{ type: "output_text", text, annotations: [] }] };
    }
    const valid = ([, value]) => value !== undefined && value !== "";
    function compact(object) { return Object.fromEntries(Object.entries(object).filter(valid)); }
    exports.createGatewayPlugin = () => ({ targetAdapters: [adapter] });
    """#
}
