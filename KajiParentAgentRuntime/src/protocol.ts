export type ProtocolMessage = {
	type: string;
	taskID?: string;
	prompt?: string;
	attachments?: ProtocolAttachment[];
	id?: string;
	ok?: boolean;
	result?: unknown;
};

export type ProtocolAttachment = {
	name: string;
	path: string;
	kind: string;
	mimeType: string;
	data?: string;
};

export type PendingTool = {
	resolve: (value: unknown) => void;
	reject: (error: Error) => void;
};

export type RuntimeContext = {
	taskID?: string;
	sessionID: string;
};

export function send(message: Record<string, unknown>) {
	process.stdout.write(`${JSON.stringify(message)}\n`);
}

export function createID(prefix: string) {
	return `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

export function stringifyResult(result: unknown) {
	if (typeof result === "string") return result;
	return JSON.stringify(result, null, 2);
}
