export interface RuntimeTelemetrySnapshot {
	totalEvents: number;
	toolStarts: number;
	toolEnds: number;
	toolFailures: number;
	toolFailuresByName: Record<string, number>;
	toolCallsByName: Record<string, number>;
	codeGraphToolCalls: number;
	autoRetryStarts: number;
	autoRetryEnds: number;
	autoCompactionStarts: number;
	autoCompactionEnds: number;
	promptRebuilds: number;
	lastPromptCharacterCount: number;
	lastPromptBlockCount: number;
	activatedMcpTools: number;
	activatedDiscoveredTools: number;
	lastActivatedTools: string[];
}

type RuntimeEvent = {
	type?: string;
	toolName?: string;
	isError?: boolean;
};

export class RuntimeTelemetry {
	#totalEvents = 0;
	#toolStarts = 0;
	#toolEnds = 0;
	#toolFailures = 0;
	#toolFailuresByName = new Map<string, number>();
	#toolCallsByName = new Map<string, number>();
	#codeGraphToolCalls = 0;
	#autoRetryStarts = 0;
	#autoRetryEnds = 0;
	#autoCompactionStarts = 0;
	#autoCompactionEnds = 0;
	#promptRebuilds = 0;
	#lastPromptCharacterCount = 0;
	#lastPromptBlockCount = 0;
	#activatedMcpTools = 0;
	#activatedDiscoveredTools = 0;
	#lastActivatedTools: string[] = [];

	recordEvent(event: RuntimeEvent): void {
		this.#totalEvents++;
		if (event.type === "tool_execution_start") {
			this.#toolStarts++;
			return;
		}
		if (event.type === "tool_execution_end") {
			this.#recordToolEnd(event.toolName ?? "unknown", event.isError === true);
			return;
		}
		if (event.type === "auto_retry_start") this.#autoRetryStarts++;
		if (event.type === "auto_retry_end") this.#autoRetryEnds++;
		if (event.type === "auto_compaction_start") this.#autoCompactionStarts++;
		if (event.type === "auto_compaction_end") this.#autoCompactionEnds++;
	}

	recordPromptRebuild(systemPrompt: string[]): void {
		this.#promptRebuilds++;
		this.#lastPromptBlockCount = systemPrompt.length;
		this.#lastPromptCharacterCount = systemPrompt.join("\n\n").length;
	}

	recordActivatedTools(toolNames: string[]): void {
		const uniqueNames = [...new Set(toolNames)];
		if (uniqueNames.length === 0) return;
		this.#activatedDiscoveredTools += uniqueNames.length;
		this.#activatedMcpTools += uniqueNames.filter(name => name.startsWith("mcp__")).length;
		this.#lastActivatedTools = uniqueNames;
	}

	snapshot(): RuntimeTelemetrySnapshot {
		return {
			totalEvents: this.#totalEvents,
			toolStarts: this.#toolStarts,
			toolEnds: this.#toolEnds,
			toolFailures: this.#toolFailures,
			toolFailuresByName: Object.fromEntries(this.#toolFailuresByName),
			toolCallsByName: Object.fromEntries(this.#toolCallsByName),
			codeGraphToolCalls: this.#codeGraphToolCalls,
			autoRetryStarts: this.#autoRetryStarts,
			autoRetryEnds: this.#autoRetryEnds,
			autoCompactionStarts: this.#autoCompactionStarts,
			autoCompactionEnds: this.#autoCompactionEnds,
			promptRebuilds: this.#promptRebuilds,
			lastPromptCharacterCount: this.#lastPromptCharacterCount,
			lastPromptBlockCount: this.#lastPromptBlockCount,
			activatedMcpTools: this.#activatedMcpTools,
			activatedDiscoveredTools: this.#activatedDiscoveredTools,
			lastActivatedTools: [...this.#lastActivatedTools],
		};
	}

	#recordToolEnd(toolName: string, isError: boolean): void {
		this.#toolEnds++;
		this.#toolCallsByName.set(toolName, (this.#toolCallsByName.get(toolName) ?? 0) + 1);
		if (toolName.startsWith("kaji_code_graph_")) this.#codeGraphToolCalls++;
		if (!isError) return;
		this.#toolFailures++;
		this.#toolFailuresByName.set(toolName, (this.#toolFailuresByName.get(toolName) ?? 0) + 1);
	}
}
