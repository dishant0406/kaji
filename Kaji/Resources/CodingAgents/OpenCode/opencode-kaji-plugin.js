export const KajiNotificationPlugin = async ({ client }) => {
  let activityState = ""
  let completedAt = 0
  let activeSessionID = ""
  let lastSessionSignature = ""

  return {
    event: async ({ event }) => {
      const hookClientPath = process.env.KAJI_HOOK_CLIENT_PATH
      const paneID = process.env.KAJI_PANE_ID
      const projectID = process.env.KAJI_PROJECT_ID
      const worktreeID = process.env.KAJI_WORKTREE_ID
      const worktreePath = process.env.KAJI_WORKTREE_PATH
      if (!hookClientPath || !paneID || !isActionableEvent(event)) return

      const context = (sessionID = "") => {
        const body = {}
        if (projectID) body.projectID = projectID
        if (worktreeID) body.worktreeID = worktreeID
        if (worktreePath) body.worktreePath = worktreePath
        if (sessionID) body.sessionID = sessionID
        return Object.keys(body).length ? JSON.stringify(body) : ""
      }

      const send = async (type, title, body) => {
        try {
          const { execFileSync } = await import("node:child_process")
          execFileSync(
            hookClientPath,
            ["send", type, paneID, title, body || ""],
            { stdio: "ignore", timeout: 1000 },
          )
        } catch {}
      }

      const sendSession = async () => {
        const sessionID = findSessionID(event)
        if (!sessionID) return
        const title = sanitize(event.properties?.title || event.properties?.name)
        const source = sanitize(event.type)
        const signature = `${sessionID}|${title}|${source}`
        if (lastSessionSignature === signature) return
        lastSessionSignature = signature
        await send("opencode_session", "session", JSON.stringify({
          sessionID: sanitize(sessionID),
          source,
          title,
          projectID,
          worktreeID,
          worktreePath,
        }))
      }

      const sendTranscript = async (kind, text) => {
        const cleaned = sanitize(text)
        if (!cleaned) return
        await send("opencode_transcript", kind, cleaned)
      }

      const sendAttention = async (kind) => {
        await sendSession()
        await send("opencode_attention", kind, attentionDetail(event) || kind)
      }

      const start = async () => {
        completedAt = 0
        const sessionID = findSessionID(event)
        if (sessionID) activeSessionID = sessionID
        await sendSession()
        if (activityState === "start") return
        activityState = "start"
        await send("opencode_activity", "start", context(sessionID))
      }

      const stop = async () => {
        const sessionID = findSessionID(event)
        if (activeSessionID && sessionID && activeSessionID !== sessionID) return
        await sendSession()
        if (activityState === "stop") return
        activityState = "stop"
        completedAt = Date.now()
        await send("opencode_activity", "stop", context(sessionID || activeSessionID))
        activeSessionID = ""
      }

      const observe = async () => {
        await sendSession()
        await send("opencode_activity", "observe", context(findSessionID(event)))
      }

      if (event.type === "tui.command.execute") {
        await start()
        await sendTranscript("user", event.properties?.text || event.properties?.command)
        return
      }

      if (event.type === "tool.execute.before") {
        await observe()
        await sendTranscript("tool", event.properties?.tool || event.properties?.name)
        return
      }

      if (event.type === "session.status") {
        const status = sessionStatus(event)
        if (["active", "busy", "running", "loading", "retry"].includes(status)) return await start()
        if (["idle", "error"].includes(status)) await stop()
        return
      }

      if (event.type === "permission.asked") return await sendAttention("permission")
      if (event.type === "question.asked") return await sendAttention("question")
      if (event.type === "session.error") return await sendAttention("error")

      await stop()
      await sendCompletion(client, event, send, sendTranscript)
    },
  }
}

const actionableEvents = new Set(["tui.command.execute", "tool.execute.before", "session.status", "permission.asked", "question.asked", "session.error", "session.idle"])

function isActionableEvent(event) {
  return actionableEvents.has(event?.type || "")
}

function sessionStatus(event) {
  const raw = event.properties?.status
  if (typeof raw === "string") return raw
  if (raw && typeof raw.type === "string") return raw.type
  if (raw && typeof raw.status === "string") return raw.status
  if (raw && typeof raw.state === "string") return raw.state
  if (typeof event.properties?.state === "string") return event.properties.state
  return ""
}

function attentionDetail(event) {
  const properties = event.properties || {}
  return sanitize(
    properties.question ||
      properties.message ||
      properties.permission ||
      properties.tool ||
      properties.command ||
      properties.description ||
      event.type,
  )
}

async function sendCompletion(client, event, send, sendTranscript) {
  const sessionID = event.properties.sessionID
  let body = "Session completed"
  try {
    const result = await client.session.messages({ path: { id: sessionID }, query: { limit: 3 } })
    const lastAssistant = [...(result.data || [])]
      .reverse()
      .find((message) => message.info.role === "assistant")
    const text = (lastAssistant?.parts || []).filter((part) => part.type === "text").map((part) => part.text || "").join("")
    if (text) {
      body = sanitize(text).slice(0, 200)
      await sendTranscript("assistant", text)
    }
  } catch {}
  await send("opencode", "OpenCode", body)
}

function sanitize(value) {
  return String(value || "").replace(/[

|]+/g, " ").trim().slice(0, 500)
}

function findSessionID(value) {
  const direct = value?.properties?.sessionID || value?.properties?.sessionId || value?.sessionID || value?.sessionId
  if (direct) return direct
  if (String(value?.type || "").startsWith("session.")) {
    const id = value?.properties?.id || value?.id
    if (id) return id
  }
  return findNestedSessionID(value, 0)
}

function findNestedSessionID(value, depth) {
  if (!value || depth > 4 || typeof value !== "object") return ""
  for (const [key, child] of Object.entries(value)) {
    const lower = key.toLowerCase()
    if (["sessionid", "session_id"].includes(lower) && child) return child
    if (lower === "session" && child && typeof child === "object") {
      const id = child.id || child.sessionID || child.sessionId
      if (id) return id
    }
  }
  for (const child of Object.values(value)) {
    const nested = findNestedSessionID(child, depth + 1)
    if (nested) return nested
  }
  return ""
}
