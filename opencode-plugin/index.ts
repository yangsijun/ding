import type { Plugin } from "@opencode-ai/plugin"
import { spawn } from "child_process"

const plugin: Plugin = async (input) => {
  let lastPrompt: string | null = null
  let lastSessionID: string | null = null

  function truncate(text: string, maxLength: number): string {
    const cleaned = text.replace(/\n/g, " ").trim()
    if (cleaned.length <= maxLength) return cleaned
    return cleaned.substring(0, maxLength) + "…"
  }

  function sendNotification(body: string, status: string) {
    const proc = spawn("ding", ["notify", body, "--title", "ding · OpenCode", "--status", status], {
      stdio: "ignore",
      detached: true,
    })
    proc.unref()
  }

  return {
    "chat.message": async (_input, output) => {
      const textParts = output.parts.filter((p) => p.type === "text")
      if (textParts.length > 0) {
        const text = textParts
          .map((p) => ("text" in p ? p.text : ""))
          .join(" ")
        if (text.trim()) {
          lastPrompt = text.trim()
          lastSessionID = _input.sessionID
        }
      }
    },

    event: async ({ event }) => {
      if (event.type === "session.idle") {
        const sessionID = event.properties.sessionID
        if (sessionID !== lastSessionID) return

        const cwd = input.project?.path || input.directory || process.cwd()
        const summary = lastPrompt ? `Done: ${truncate(lastPrompt, 80)}` : "Task completed"
        const body = `${cwd}\n${summary}`

        sendNotification(body, "success")

        lastPrompt = null
        lastSessionID = null
      }

      if (event.type === "session.error") {
        const cwd = input.project?.path || input.directory || process.cwd()
        const error = event.properties.error
        const msg =
          error && "data" in error && typeof (error as any).data?.message === "string"
            ? (error as any).data.message
            : "Unknown error"
        const body = `${cwd}\nFailed: ${truncate(msg, 80)}`

        sendNotification(body, "failure")

        lastPrompt = null
        lastSessionID = null
      }
    },
  }
}

export default plugin
