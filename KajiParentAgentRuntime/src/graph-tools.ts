import { execFile } from "node:child_process";
import { mkdirSync, readdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join, resolve, sep } from "node:path";
import { promisify } from "node:util";
import type { AgentTool } from "@earendil-works/pi-agent-core";
import { Type } from "@earendil-works/pi-ai";
import { agentMode } from "./mode.js";
import { localTool } from "./tool-factory.js";

const execFileAsync = promisify(execFile);

export function graphTools(): AgentTool[] {
	return [
		localTool(
			"graph_list_files",
			"List files below an allowed read root. Use this to inspect project structure without printing huge trees.",
			Type.Object({
				path: Type.String(),
				limit: Type.Optional(Type.String()),
				maxDepth: Type.Optional(Type.String()),
			}),
			(params) => listFiles(params),
		),
		localTool(
			"graph_read_file",
			"Read a UTF-8 text file from an allowed read root.",
			Type.Object({
				path: Type.String(),
				maxBytes: Type.Optional(Type.String()),
			}),
			(params) => readFile(params),
		),
		localTool(
			"graph_write_file",
			"Write a UTF-8 text file inside an allowed write root.",
			Type.Object({
				path: Type.String(),
				content: Type.String(),
			}),
			(params) => writeFile(params),
		),
		localTool(
			"graph_shell",
			"Run a shell command in an allowed shell root. Use for Graphify Python/CLI and the finalizer.",
			Type.Object({
				command: Type.String(),
				cwd: Type.String(),
				timeoutSeconds: Type.Optional(Type.String()),
				maxBytes: Type.Optional(Type.String()),
			}),
			(params, signal) => runShell(params, signal),
		),
	];
}

function envRoots(name: string): string[] {
	const value = process.env[name];
	if (!value) return [];
	try {
		const parsed = JSON.parse(value);
		if (Array.isArray(parsed)) return parsed.map((item) => String(item)).filter(Boolean).map((item) => resolve(item));
	} catch {
		return value.split(":").map((item) => item.trim()).filter(Boolean).map((item) => resolve(item));
	}
	return [];
}

function readRoots() {
	return envRoots("KAJI_GRAPH_READ_ROOTS");
}

function writeRoots() {
	return envRoots("KAJI_GRAPH_WRITE_ROOTS");
}

function shellRoots() {
	return envRoots("KAJI_GRAPH_SHELL_ROOTS");
}

function normalizePath(path: unknown) {
	if (typeof path !== "string" || !path.trim()) throw new Error("path is required");
	return resolve(path);
}

function isWithin(path: string, roots: string[]) {
	const normalized = resolve(path);
	return roots.some((root) => normalized === root || normalized.startsWith(`${root}${sep}`));
}

function requireWithin(path: string, roots: string[], label: string) {
	if (roots.length === 0 || !isWithin(path, roots)) throw new Error(`${path} is outside allowed ${label} roots`);
	return path;
}

function existingPath(path: string) {
	try {
		return realpathSync(path);
	} catch {
		return path;
	}
}

function truncate(text: string, maxBytes: number) {
	if (Buffer.byteLength(text, "utf8") <= maxBytes) return { text, truncated: false };
	const buffer = Buffer.from(text, "utf8").subarray(0, maxBytes);
	return { text: buffer.toString("utf8"), truncated: true };
}

function listFiles(params: Record<string, unknown>) {
	const root = requireWithin(existingPath(normalizePath(params.path)), readRoots(), "read");
	const limit = Math.max(1, Math.min(Number(params.limit ?? 400), 2000));
	const maxDepth = Math.max(0, Math.min(Number(params.maxDepth ?? 4), 12));
	const files: string[] = [];
	const walk = (dir: string, depth: number) => {
		if (files.length >= limit || depth > maxDepth) return;
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			if (files.length >= limit) return;
			if (entry.name === ".git" || entry.name === "node_modules" || entry.name === ".kaji") continue;
			const full = join(dir, entry.name);
			const relative = full.slice(root.length + 1);
			files.push(entry.isDirectory() ? `${relative}/` : relative);
			if (entry.isDirectory()) walk(full, depth + 1);
		}
	};
	walk(root, 0);
	return { root, files, truncated: files.length >= limit };
}

function readFile(params: Record<string, unknown>) {
	const path = requireWithin(existingPath(normalizePath(params.path)), readRoots(), "read");
	const maxBytes = Math.max(1, Math.min(Number(params.maxBytes ?? 120000), 500000));
	const { text, truncated } = truncate(readFileSync(path, "utf8"), maxBytes);
	return { path, text, truncated };
}

function writeFile(params: Record<string, unknown>) {
	const path = requireWithin(normalizePath(params.path), writeRoots(), "write");
	const content = typeof params.content === "string" ? params.content : "";
	mkdirSync(dirname(path), { recursive: true });
	writeFileSync(path, content, "utf8");
	return { path, bytes: Buffer.byteLength(content, "utf8") };
}

function blockedGraphifyCommand(command: string) {
	if (agentMode() !== "kajicodegraph") return undefined;
	if (/\s--out(?:\s|=)/.test(` ${command} `)) return undefined;
	const invokesGraphify =
		/(^|[;&|]\s*)graphify(?=$|[\s;&|])/.test(command) ||
		/(^|[\s;&|])-m\s+graphify(?=$|[\s;&|])/.test(command);
	if (!invokesGraphify) return undefined;
	const work = process.env.KAJI_GRAPH_WORK_DIR ?? "the Kaji work directory";
	return [
		"KajiCodeGraph blocked Graphify's default output path.",
		`Run it with --out ${work} and GRAPHIFY_OUT=${work}/graphify-out.`,
	].join(" ");
}

async function runShell(params: Record<string, unknown>, signal?: AbortSignal) {
	const command = typeof params.command === "string" ? params.command : "";
	if (!command.trim()) throw new Error("command is required");
	const cwd = requireWithin(existingPath(normalizePath(params.cwd)), shellRoots(), "shell");
	const blocked = blockedGraphifyCommand(command);
	if (blocked) return { cwd, exitCode: 2, stdout: "", stderr: blocked, truncated: false };
	const timeout = Math.max(1000, Math.min(Number(params.timeoutSeconds ?? 600) * 1000, 3600000));
	const maxBytes = Math.max(1000, Math.min(Number(params.maxBytes ?? 24000), 200000));
	const result = await execFileAsync("/bin/zsh", ["-lc", command], {
		cwd,
		timeout,
		signal,
		maxBuffer: Math.max(maxBytes * 2, 1024 * 1024),
		env: process.env,
	}).then(
		(value) => ({ stdout: value.stdout, stderr: value.stderr, exitCode: 0 }),
		(error: { stdout?: string; stderr?: string; message?: string; code?: number }) => ({
			stdout: error.stdout ?? "",
			stderr: error.stderr ?? error.message ?? "",
			exitCode: error.code ?? 1,
		}),
	);
	const stdout = truncate(String(result.stdout), maxBytes);
	const stderr = truncate(String(result.stderr), maxBytes);
	return {
		cwd,
		exitCode: result.exitCode,
		stdout: stdout.text,
		stderr: stderr.text,
		truncated: stdout.truncated || stderr.truncated,
	};
}
