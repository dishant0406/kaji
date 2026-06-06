export interface ToolResolverAlias {
	from: string;
	to: string;
}

export interface ToolResolutionEntry<T> {
	name: string;
	value: T;
}

export interface ToolResolutionResult<T> {
	entries: ToolResolutionEntry<T>[];
	unknown: string[];
}

export interface ToolResolutionOptions {
	aliases?: readonly ToolResolverAlias[];
}

export const DEFAULT_TOOL_ALIASES = [
	{ from: "Read", to: "read" },
	{ from: "Write", to: "write" },
	{ from: "Task", to: "task" },
	{ from: "fs_search", to: "search" },
	{ from: "sem_search", to: "search" },
] as const satisfies readonly ToolResolverAlias[];

export function resolveToolEntries<T>(
	available: Iterable<ToolResolutionEntry<T>>,
	patterns: readonly string[],
	options: ToolResolutionOptions = {},
): ToolResolutionResult<T> {
	const aliasMap = buildAliasMap(options.aliases ?? DEFAULT_TOOL_ALIASES);
	const ordered = [...available];
	const selected: ToolResolutionEntry<T>[] = [];
	const unknown: string[] = [];
	const seen = new Set<string>();

	for (const rawPattern of patterns) {
		const pattern = normalizeToolPattern(rawPattern, aliasMap);
		const matches = ordered.filter(entry => toolPatternMatches(pattern, entry.name));
		if (matches.length === 0) {
			unknown.push(rawPattern);
			continue;
		}
		for (const match of matches) {
			if (seen.has(match.name)) continue;
			seen.add(match.name);
			selected.push(match);
		}
	}

	return { entries: selected, unknown };
}

export function resolveToolNames(
	availableNames: Iterable<string>,
	patterns: readonly string[],
	options: ToolResolutionOptions = {},
): ToolResolutionResult<string> {
	return resolveToolEntries(
		[...availableNames].map(name => ({ name, value: name })),
		patterns,
		options,
	);
}

export function toolPatternMatches(pattern: string, name: string): boolean {
	if (pattern === name) return true;
	if (!pattern.includes("*")) return false;
	const escaped = pattern
		.split("*")
		.map(part => part.replace(/[|\\{}()[\]^$+?.]/g, "\\$&"))
		.join(".*");
	return new RegExp(`^${escaped}$`).test(name);
}

function normalizeToolPattern(pattern: string, aliases: Map<string, string>): string {
	return aliases.get(pattern) ?? aliases.get(pattern.toLowerCase()) ?? pattern.toLowerCase();
}

function buildAliasMap(aliases: readonly ToolResolverAlias[]): Map<string, string> {
	const map = new Map<string, string>();
	for (const alias of aliases) {
		map.set(alias.from, alias.to);
		map.set(alias.from.toLowerCase(), alias.to);
	}
	return map;
}
