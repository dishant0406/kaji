import type { SystemPromptToolMetadata } from "../system-prompt";
import type { WorkspaceTree } from "../workspace-tree";

export interface KajiPromptContext {
	environment: {
		cwd: string;
		date: string;
		entries: Array<{ label: string; value: string }>;
	};
	tools: Array<{
		name: string;
		wireName: string;
		label: string;
		description: string;
	}>;
	workspace: {
		rootPath: string;
		truncated: boolean;
		totalLines: number;
		agentsMdFiles: string[];
	};
	mcp: {
		discoveryMode: boolean;
		servers: string[];
	};
	host: {
		hasNativeTools: boolean;
		hasWorkspaceTools: boolean;
		nativeTools: string[];
		workspaceTools: string[];
	};
	debug: {
		hasDebugTools: boolean;
		tools: string[];
	};
}

export interface BuildKajiPromptContextOptions {
	cwd: string;
	date: string;
	environment: Array<{ label: string; value: string }>;
	toolNames: string[];
	toolMetadata?: Map<string, SystemPromptToolMetadata>;
	toolWireNames: Map<string, string>;
	workspaceTree: WorkspaceTree;
	mcpDiscoveryMode: boolean;
	mcpDiscoveryServerSummaries: string[];
}

export function buildKajiPromptContext(options: BuildKajiPromptContextOptions): KajiPromptContext {
	const nativeTools = options.toolNames.filter(name => name.startsWith("kaji_"));
	const workspaceTools = nativeTools.filter(name => name.startsWith("kaji_get_"));
	const debugTools = options.toolNames.filter(name =>
		[
			"runtime_profile_dump",
			"runtime_telemetry_dump",
			"tool_catalog_dump",
			"prompt_preview",
			"permission_rules_dump",
			"subagent_tree_dump",
		].includes(name),
	);

	return {
		environment: {
			cwd: options.cwd,
			date: options.date,
			entries: options.environment,
		},
		tools: options.toolNames.map(name => ({
			name,
			wireName: options.toolWireNames.get(name) ?? name,
			label: options.toolMetadata?.get(name)?.label ?? "",
			description: options.toolMetadata?.get(name)?.description ?? "",
		})),
		workspace: {
			rootPath: options.workspaceTree.rootPath,
			truncated: options.workspaceTree.truncated,
			totalLines: options.workspaceTree.totalLines,
			agentsMdFiles: options.workspaceTree.agentsMdFiles,
		},
		mcp: {
			discoveryMode: options.mcpDiscoveryMode,
			servers: options.mcpDiscoveryServerSummaries,
		},
		host: {
			hasNativeTools: nativeTools.length > 0,
			hasWorkspaceTools: workspaceTools.length > 0,
			nativeTools,
			workspaceTools,
		},
		debug: {
			hasDebugTools: debugTools.length > 0,
			tools: debugTools,
		},
	};
}
