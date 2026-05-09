#!/usr/bin/env node
const endpoint = process.env.DROID_BROWSER_ENDPOINT
const sessionID = process.env.DROID_BROWSER_SESSION_ID
let buffer = Buffer.alloc(0)

const tools = [
  tool("droid_browser_current", "Return the current Droid browser URL and title", {}),
  tool("droid_browser_navigate", "Navigate the attached Droid browser", { url: { type: "string" } }, ["url"]),
  tool("droid_browser_read_page", "Read visible text from the attached Droid browser", {}),
  tool("droid_browser_click", "Click the first element matching a CSS selector", { selector: { type: "string" } }, ["selector"]),
  tool("droid_browser_type", "Type text into the first element matching a CSS selector", { selector: { type: "string" }, text: { type: "string" } }, ["selector", "text"]),
  tool("droid_browser_back", "Go back in the attached Droid browser", {}),
  tool("droid_browser_forward", "Go forward in the attached Droid browser", {}),
  tool("droid_browser_reload", "Reload the attached Droid browser", {}),
]

process.stdin.on("data", chunk => {
  buffer = Buffer.concat([buffer, chunk])
  readFrames()
})

function readFrames() {
  while (true) {
    const headerEnd = buffer.indexOf("\r\n\r\n")
    if (headerEnd < 0) return
    const header = buffer.subarray(0, headerEnd).toString("utf8")
    const match = header.match(/content-length:\s*(\d+)/i)
    if (!match) {
      buffer = Buffer.alloc(0)
      return
    }
    const length = Number(match[1])
    const start = headerEnd + 4
    if (buffer.length < start + length) return
    const body = buffer.subarray(start, start + length).toString("utf8")
    buffer = buffer.subarray(start + length)
    handle(JSON.parse(body)).catch(error => sendError(null, error))
  }
}

async function handle(message) {
  if (message.method === "initialize") {
    send(message.id, { protocolVersion: "2024-11-05", capabilities: { tools: {} }, serverInfo: { name: "droid-browser", version: "0.1.0" } })
    return
  }
  if (message.method === "notifications/initialized") return
  if (message.method === "tools/list") {
    send(message.id, { tools })
    return
  }
  if (message.method === "tools/call") {
    const result = await callTool(message.params?.name, message.params?.arguments || {})
    send(message.id, { content: [{ type: "text", text: result }] })
    return
  }
  send(message.id, {})
}

async function callTool(name, args) {
  const action = String(name || "").replace(/^droid_browser_/, "")
  const data = await request({ action, ...args })
  return JSON.stringify(data, null, 2)
}

async function request(payload) {
  if (!endpoint || !sessionID) throw new Error("Droid browser is not available in this agent session")
  const response = await fetch(endpoint + "/browser", {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ sessionID, ...payload }),
  })
  const data = await response.json()
  if (!response.ok || data.error) throw new Error(data.error || `Droid browser request failed: ${response.status}`)
  return data
}

function tool(name, description, properties, required = []) {
  return { name, description, inputSchema: { type: "object", properties, required, additionalProperties: false } }
}

function send(id, result) {
  write({ jsonrpc: "2.0", id, result })
}

function sendError(id, error) {
  write({ jsonrpc: "2.0", id, error: { code: -32000, message: String(error?.message || error) } })
}

function write(message) {
  const body = Buffer.from(JSON.stringify(message), "utf8")
  process.stdout.write(`Content-Length: ${body.length}\r\n\r\n`)
  process.stdout.write(body)
}
