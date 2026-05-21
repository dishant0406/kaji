import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { getEnvApiKey } from "@earendil-works/pi-ai";
import { getOAuthApiKey, type OAuthCredentials } from "@earendil-works/pi-ai/oauth";

type PiCredential = { type?: string; key?: string } & OAuthCredentials;

export function authPath() {
	return join(homedir(), ".pi", "agent", "auth.json");
}

export function readAuthFile(): Record<string, PiCredential> {
	const path = authPath();
	if (!existsSync(path)) return {};
	return JSON.parse(readFileSync(path, "utf8")) as Record<string, PiCredential>;
}

export function writeAuthFile(auth: Record<string, unknown>) {
	const path = authPath();
	mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
	writeFileSync(path, `${JSON.stringify(auth, null, 2)}\n`, "utf8");
}

export async function resolveApiKey(provider: string) {
	const envKey = getEnvApiKey(provider);
	if (envKey) return envKey;

	const auth = readAuthFile();
	const credential = auth[provider];
	if (credential?.type === "api_key" && credential.key) {
		return process.env[credential.key] ?? credential.key;
	}
	if (credential?.type === "oauth") {
		const result = await getOAuthApiKey(provider, auth);
		if (!result) return undefined;
		auth[provider] = { ...result.newCredentials, type: "oauth" };
		writeAuthFile(auth);
		return result.apiKey;
	}
	return undefined;
}
