import { spawn } from "node:child_process";
import { access, stat } from "node:fs/promises";
import * as path from "node:path";

export enum FileType {
	File = 1,
	Dir = 2,
}

export interface GlobMatch {
	path: string;
	fileType?: FileType;
	mtime?: number;
	size?: number;
}

export interface GlobOptions {
	pattern: string;
	path: string;
	hidden?: boolean;
	gitignore?: boolean;
	maxResults?: number;
	sortByMtime?: boolean;
	fileType?: FileType;
	recursive?: boolean;
	signal?: AbortSignal;
}

export type GlobCallback = (error: Error | null, match: GlobMatch | null) => void;

export async function glob(options: GlobOptions, onMatch?: GlobCallback): Promise<{ matches: GlobMatch[] }> {
	const executable = await resolveZlobExecutable();
	if (!executable) {
		throw new Error("zlob executable not found. Kaji should bundle it at Kaji/Resources/Zlob/zlob or set KAJI_ZLOB_BIN.");
	}
	const cwd = path.resolve(String(options.path || process.cwd()));
	const pattern = normalizePatternForCwd(String(options.pattern || "**/*"), cwd);
	const maxResults = Number(options.maxResults ?? 200);
	const patterns = expandBraces(pattern);
	const outputs: string[] = [];
	for (const expandedPattern of patterns) {
		const args = buildArgs(expandedPattern, cwd, options, maxResults);
		outputs.push(await runZlob(executable, args, options.signal));
	}
	const output = outputs.join("\n");
	let matches = await Promise.all(
		output
			.split(/\r?\n/g)
			.map(line => line.trim())
			.filter(isZlobResultLine)
			.map(line => toGlobMatch(cwd, line)),
	);
	matches = matches.filter((match): match is GlobMatch => Boolean(match));
	matches = dedupeMatches(matches);
	if (options.fileType !== undefined) {
		matches = matches.filter(match => match.fileType === options.fileType);
	}
	if (options.sortByMtime) {
		matches.sort((a, b) => (b.mtime ?? 0) - (a.mtime ?? 0));
	}
	matches = matches.slice(0, maxResults);
	for (const match of matches) onMatch?.(null, match);
	return { matches };
}

function isZlobResultLine(line: string): boolean {
	if (!line) return false;
	if (line.startsWith("... and ")) return false;
	if (line.startsWith("No matches found for pattern:")) return false;
	return true;
}

function dedupeMatches(matches: GlobMatch[]): GlobMatch[] {
	const seen = new Set<string>();
	const deduped: GlobMatch[] = [];
	for (const match of matches) {
		if (seen.has(match.path)) continue;
		seen.add(match.path);
		deduped.push(match);
	}
	return deduped;
}

function expandBraces(pattern: string): string[] {
	const open = pattern.indexOf("{");
	if (open === -1) return [pattern];
	let depth = 0;
	for (let i = open; i < pattern.length; i++) {
		const char = pattern[i];
		if (char === "{") depth++;
		else if (char === "}") {
			depth--;
			if (depth === 0) {
				const before = pattern.slice(0, open);
				const after = pattern.slice(i + 1);
				const alternatives = splitBraceAlternatives(pattern.slice(open + 1, i));
				return alternatives.flatMap(alternative => expandBraces(`${before}${alternative.trim()}${after}`));
			}
		}
	}
	return [pattern];
}

function splitBraceAlternatives(value: string): string[] {
	const alternatives: string[] = [];
	let depth = 0;
	let start = 0;
	for (let i = 0; i < value.length; i++) {
		const char = value[i];
		if (char === "{") depth++;
		else if (char === "}") depth--;
		else if (char === "," && depth === 0) {
			alternatives.push(value.slice(start, i));
			start = i + 1;
		}
	}
	alternatives.push(value.slice(start));
	return alternatives;
}

function buildArgs(pattern: string, cwd: string, options: GlobOptions, maxResults: number): string[] {
	const args = ["--mark", "--limit", String(maxResults)];
	if (options.hidden) args.push("--hidden");
	if (options.gitignore === false) args.push("--no-gitignore");
	if (options.fileType === FileType.Dir) args.push("--dirs-only");
	if (!options.sortByMtime) args.push("--sorted");
	args.push(pattern, cwd);
	return args;
}

function normalizePatternForCwd(pattern: string, cwd: string): string {
	const normalized = pattern.replace(/\\/g, "/");
	const normalizedCwd = cwd.replace(/\\/g, "/").replace(/\/$/, "");
	if (normalized === normalizedCwd) return ".";
	if (normalized.startsWith(`${normalizedCwd}/`)) {
		return normalized.slice(normalizedCwd.length + 1) || ".";
	}
	return normalized;
}

async function toGlobMatch(cwd: string, rawPath: string): Promise<GlobMatch | null> {
	const hadTrailingSlash = rawPath.endsWith("/");
	const cleanPath = rawPath.replace(/\/$/, "");
	const absolutePath = path.isAbsolute(cleanPath) ? cleanPath : path.resolve(cwd, cleanPath);
	try {
		const info = await stat(absolutePath);
		const relative = path.relative(cwd, absolutePath).replace(/\\/g, "/");
		return {
			path: relative || path.basename(absolutePath),
			fileType: info.isDirectory() || hadTrailingSlash ? FileType.Dir : FileType.File,
			mtime: info.mtimeMs,
			size: info.size,
		};
	} catch {
		return null;
	}
}

function runZlob(executable: string, args: string[], signal?: AbortSignal): Promise<string> {
	return new Promise((resolve, reject) => {
		const child = spawn(executable, args, { stdio: ["ignore", "pipe", "pipe"] });
		let stdout = "";
		let stderr = "";
		const abort = () => {
			child.kill("SIGTERM");
			reject(abortError());
		};
		if (signal?.aborted) return abort();
		signal?.addEventListener("abort", abort, { once: true });
		child.stdout.setEncoding("utf8");
		child.stderr.setEncoding("utf8");
		child.stdout.on("data", chunk => {
			stdout += chunk;
		});
		child.stderr.on("data", chunk => {
			stderr += chunk;
		});
		child.on("error", reject);
		child.on("close", code => {
			signal?.removeEventListener("abort", abort);
			if (code === 0) resolve(stdout);
			else if (code === 3) resolve("");
			else reject(new Error(stderr.trim() || `zlob exited with code ${code}`));
		});
	});
}

async function resolveZlobExecutable(): Promise<string | null> {
	const executable = process.env.KAJI_ZLOB_BIN?.trim();
	if (!executable) return null;
	return canExecute(executable).then(ok => (ok ? executable : null));
}

async function canExecute(candidate: string): Promise<boolean> {
	try {
		await access(candidate);
		return true;
	} catch {
		return false;
	}
}

function abortError(): Error {
	const error = new Error("Operation aborted");
	error.name = "AbortError";
	return error;
}
