import * as crypto from "node:crypto";
import type { AuthStorage } from "./auth-storage";

export function buildSessionMetadata(
	sessionId: string,
	provider: string,
	authStorage: AuthStorage | undefined,
): Record<string, unknown> {
	const userId: Record<string, string> = { session_id: sessionId };
	if (provider === "anthropic") {
		const accountUuid = authStorage?.getOAuthAccountId("anthropic", sessionId);
		if (typeof accountUuid === "string" && accountUuid.length > 0) {
			userId.account_uuid = accountUuid;
			userId.device_id = crypto.createHash("sha256").update(`omp-device-id-v1:${accountUuid}`).digest("hex");
		}
	}
	return { user_id: JSON.stringify(userId) };
}
