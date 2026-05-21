import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import readline from "node:readline";
import { getOAuthProvider, type OAuthCredentials } from "@earendil-works/pi-ai/oauth";
import { authPath } from "./auth.js";
import { createID, send } from "./protocol.js";

type AuthRecord = Record<string, ({ type: "oauth" } & OAuthCredentials) | Record<string, unknown>>;

const providerID = process.argv[2];
const rl = readline.createInterface({ input: process.stdin, crlfDelay: Number.POSITIVE_INFINITY });
const pendingPrompts = new Map<string, (value: string) => void>();

function requestInput(message: string, placeholder?: string, allowEmpty?: boolean) {
	const id = createID("prompt");
	const promise = new Promise<string>((resolve) => pendingPrompts.set(id, resolve));
	send({ type: "oauth_prompt", id, message, placeholder, allowEmpty: allowEmpty === true });
	return promise;
}

function readAuth(): AuthRecord {
	const path = authPath();
	if (!existsSync(path)) return {};
	return JSON.parse(readFileSync(path, "utf8")) as AuthRecord;
}

function writeAuth(auth: AuthRecord) {
	const path = authPath();
	mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
	writeFileSync(path, `${JSON.stringify(auth, null, 2)}\n`, "utf8");
	chmodSync(path, 0o600);
}

async function login(provider: string) {
	const oauth = getOAuthProvider(provider);
	if (!oauth) throw new Error(`OAuth is not supported for ${provider}`);
	send({ type: "oauth_status", message: `Starting ${oauth.name} login.` });
	const credentials = await oauth.login({
		onAuth: (info) => {
			send({ type: "oauth_auth", url: info.url, message: info.instructions ?? "Complete login in your browser." });
		},
		onPrompt: async (prompt) => {
			if (prompt.allowEmpty) return "";
			return requestInput(prompt.message, prompt.placeholder, prompt.allowEmpty);
		},
		onManualCodeInput: async () => requestInput("Paste the authorization code or redirect URL:"),
		onProgress: (message) => {
			send({ type: "oauth_status", message });
		},
	});
	const auth = readAuth();
	auth[provider] = { type: "oauth", ...credentials };
	writeAuth(auth);
	send({ type: "oauth_complete", message: `${oauth.name} connected.` });
}

rl.on("line", (line) => {
	try {
		const message = JSON.parse(line) as { type?: string; id?: string; value?: string };
		if (message.type !== "oauth_prompt_response" || !message.id) return;
		const resolve = pendingPrompts.get(message.id);
		if (!resolve) return;
		pendingPrompts.delete(message.id);
		resolve(message.value ?? "");
	} catch (error) {
		send({ type: "oauth_error", message: error instanceof Error ? error.message : String(error) });
	}
});

if (!providerID) {
	send({ type: "oauth_error", message: "Missing OAuth provider." });
	process.exit(1);
}

login(providerID).catch((error) => {
	send({ type: "oauth_error", message: error instanceof Error ? error.message : String(error) });
	process.exit(1);
});
