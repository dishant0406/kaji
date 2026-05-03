import readline from "node:readline";

const rl = readline.createInterface({
	input: process.stdin,
	crlfDelay: Number.POSITIVE_INFINITY,
});

const pending = new Map();

function send(message) {
	process.stdout.write(`${JSON.stringify(message)}\n`);
}

function createID(prefix) {
	return `${prefix}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function handleUserPrompt(message) {
	const taskID = message.taskID;
	send({
		type: "task_event",
		taskID,
		event: "task.planning",
		message: "Reading Droid workspace context.",
	});

	const callID = createID("tool");
	pending.set(callID, { taskID, prompt: message.prompt });
	send({
		type: "tool_call",
		id: callID,
		taskID,
		name: "droid.list_projects",
		arguments: {},
	});
}

function handleToolResult(message) {
	const request = pending.get(message.id);
	if (!request) return;
	pending.delete(message.id);

	const count = Array.isArray(message.result?.projects) ? message.result.projects.length : 0;
	send({
		type: "task_event",
		taskID: request.taskID,
		event: "task.plan_ready",
		message: `Droid returned ${count} available project${count === 1 ? "" : "s"}.`,
	});
	send({
		type: "final_response",
		taskID: request.taskID,
		message: `V0 bridge is connected. Next step is routing "${request.prompt}" into Droid tools and provider agents.`,
	});
}

rl.on("line", (line) => {
	try {
		const message = JSON.parse(line);
		if (message.type === "user_prompt") {
			handleUserPrompt(message);
		} else if (message.type === "tool_result") {
			handleToolResult(message);
		}
	} catch (error) {
		send({
			type: "error",
			message: error instanceof Error ? error.message : String(error),
		});
	}
});

send({ type: "heartbeat", message: "droid-agent-v0-ready" });
