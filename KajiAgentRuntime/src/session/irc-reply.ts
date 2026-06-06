const IRC_REPLY_MAX_BYTES = 4096;

export function dedupeIrcReply(text: string): string {
	if (!text) return text;
	const lines = text.split("\n");
	const out: string[] = [];
	let i = 0;
	while (i < lines.length) {
		let j = i + 1;
		while (j < lines.length && lines[j] === lines[i]) j++;
		const runLen = j - i;
		if (runLen > 3) out.push(lines[i], `[…${runLen}×]`);
		else for (let k = 0; k < runLen; k++) out.push(lines[i]);
		i = j;
	}
	let result = out.join("\n");
	if (Buffer.byteLength(result, "utf8") > IRC_REPLY_MAX_BYTES) {
		const suffix = "\n[…truncated]";
		const budget = IRC_REPLY_MAX_BYTES - Buffer.byteLength(suffix, "utf8");
		while (Buffer.byteLength(result, "utf8") > budget) result = result.slice(0, -1);
		result += suffix;
	}
	return result;
}
