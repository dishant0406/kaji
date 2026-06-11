import { existsSync } from "node:fs";
import { $which } from "@oh-my-pi/pi-utils";

const AZURE_CLI_CANDIDATES = ["/opt/homebrew/bin/az", "/usr/local/bin/az", "/usr/bin/az"];

export interface AzureCliRunner {
	run(args: string[]): Promise<unknown>;
}

export class DefaultAzureCliRunner implements AzureCliRunner {
	async run(args: string[]): Promise<unknown> {
		const az = resolveAzureCliPath();
		const child = Bun.spawn([az, ...args, "--output", "json"], {
			stdout: "pipe",
			stderr: "pipe",
			signal: AbortSignal.timeout(20_000),
			windowsHide: true,
		});
		const [stdout, stderr, exitCode] = await Promise.all([
			new Response(child.stdout).text(),
			new Response(child.stderr).text(),
			child.exited,
		]);
		if (exitCode !== 0) throw new Error(normalizeAzureCliError(stderr));
		return JSON.parse(stdout || "null");
	}
}

function resolveAzureCliPath(): string {
	const configured = Bun.env.KAJI_AZURE_CLI_PATH || Bun.env.AZURE_CLI_PATH;
	if (configured) return configured;
	const found = $which("az");
	if (found) return found;
	return AZURE_CLI_CANDIDATES.find(path => existsSync(path)) ?? "az";
}

function normalizeAzureCliError(stderr: string): string {
	const text = stderr.trim();
	if (!text) return "Azure CLI command failed.";
	if (/az login|login/i.test(text)) return "Azure CLI is not authenticated. Run az login, then try Auto Match Models again.";
	return text;
}
