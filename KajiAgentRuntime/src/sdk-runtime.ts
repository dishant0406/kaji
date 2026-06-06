import { logger, postmortem } from "@oh-my-pi/pi-utils";
import { disposeAllKernelSessions } from "./eval/py/executor";
import { closeAllConnections } from "./ssh/connection-manager";
import { unmountAll } from "./ssh/sshfs-mount";

let sshCleanupRegistered = false;
let pythonCleanupRegistered = false;

export function registerSshCleanup(): void {
	if (sshCleanupRegistered) return;
	sshCleanupRegistered = true;
	postmortem.register("ssh-cleanup", cleanupSshResources);
}

export function registerPythonCleanup(): void {
	if (pythonCleanupRegistered) return;
	pythonCleanupRegistered = true;
	postmortem.register("python-cleanup", disposeAllKernelSessions);
}

export function resolveAppendOnlyMode(setting: "auto" | "on" | "off" | undefined, provider: string): boolean {
	switch (setting ?? "auto") {
		case "on":
			return true;
		case "off":
			return false;
		default:
			return provider === "deepseek";
	}
}

async function cleanupSshResources(): Promise<void> {
	const results = await Promise.allSettled([closeAllConnections(), unmountAll()]);
	for (const result of results) {
		if (result.status === "rejected") logger.warn("SSH cleanup failed", { error: String(result.reason) });
	}
}
