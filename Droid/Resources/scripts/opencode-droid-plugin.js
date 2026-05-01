export const DroidNotificationPlugin = async ({ client }) => {
  let activityState = ""

  return {
    event: async ({ event }) => {
      const socketPath = process.env.DROID_SOCKET_PATH
      const paneID = process.env.DROID_PANE_ID
      const projectID = process.env.DROID_PROJECT_ID
      const worktreeID = process.env.DROID_WORKTREE_ID
      if (!socketPath || !paneID) return
      const context = projectID && worktreeID ? `${projectID},${worktreeID}` : ""

      const send = async (payload) => {
        try {
          const { execFileSync } = await import("node:child_process")
          execFileSync(
            "/usr/bin/python3",
            [
              "-c",
              "import socket,sys;s=socket.socket(socket.AF_UNIX);s.connect(sys.argv[1]);s.sendall(sys.argv[2].encode());s.close()",
              socketPath,
              payload,
            ],
            { stdio: "ignore", timeout: 3000 },
          )
        } catch {}
      }

      const sanitize = (value) => String(value || "").replace(/[\n\r|]+/g, " ").trim().slice(0, 500)

      const sendTranscript = async (kind, text) => {
        const cleaned = sanitize(text)
        if (!cleaned) return
        await send(`opencode_transcript|${paneID}|${kind}|${cleaned}`)
      }

      const sessionStatus = () => {
        const raw = event.properties?.status
        if (typeof raw === "string") return raw
        if (raw && typeof raw.type === "string") return raw.type
        return ""
      }

      const start = async () => {
        if (activityState === "start") return
        activityState = "start"
        await send(`opencode_activity|${paneID}|start|${context}`)
      }

      const stop = async () => {
        if (activityState === "stop") return
        activityState = "stop"
        await send(`opencode_activity|${paneID}|stop|${context}`)
      }

      if (event.type === "tui.command.execute") {
        await start()
        await sendTranscript("user", event.properties?.text || event.properties?.command)
        return
      }

      if (event.type === "tool.execute.before") {
        await start()
        await sendTranscript("tool", event.properties?.tool || event.properties?.name)
        return
      }

      if (event.type === "session.status") {
        const status = sessionStatus()
        if (status === "active" || status === "busy" || status === "retry") {
          await start()
          return
        }
        if (status === "idle" || status === "error") {
          await stop()
          return
        }
      }

      if (
        event.type === "question.asked" ||
        event.type === "permission.asked" ||
        event.type === "session.error"
      ) {
        await stop()
        await sendTranscript("attention", event.properties?.question || event.properties?.message || event.type)
        return
      }

      if (event.type !== "session.idle") return

      await stop()

      const sessionID = event.properties.sessionID
      let body = "Session completed"

      try {
        const result = await client.session.messages({
          path: { id: sessionID },
          query: { limit: 3 },
        })
        const messages = result.data || []
        const lastAssistant = [...messages]
          .reverse()
          .find((m) => m.info.role === "assistant")
        if (lastAssistant) {
          const textParts = (lastAssistant.parts || []).filter(
            (p) => p.type === "text",
          )
          const text = textParts.map((p) => p.text || "").join("")
          if (text) {
            body = sanitize(text).slice(0, 200)
            await sendTranscript("assistant", text)
          }
        }
      } catch {}

      const payload = `opencode|${paneID}|OpenCode|${body}`
      await send(payload)
    },
  }
}
