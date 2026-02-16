import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const ANTHROPIC_API_KEY = Deno.env.get("ANTHROPIC_API_KEY")

serve(async (req) => {
  const headers = { "Content-Type": "application/json" }

  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type",
      },
    })
  }

  try {
    if (!ANTHROPIC_API_KEY) {
      return new Response(
        JSON.stringify({ subtasks: null, error: "ANTHROPIC_API_KEY not configured as secret" }),
        { status: 200, headers }
      )
    }

    const { title, description, existingSubtasks } = await req.json()
    if (!title || typeof title !== "string" || title.trim().length === 0) {
      return new Response(
        JSON.stringify({ subtasks: null, error: "Task title is required" }),
        { status: 200, headers }
      )
    }

    const taskContext = description
      ? `Task: "${title}"\nDescription: "${description}"`
      : `Task: "${title}"`

    let userPrompt = `Break down the following task into 4-6 specific, actionable subtasks.\n\n${taskContext}`

    if (Array.isArray(existingSubtasks) && existingSubtasks.length > 0) {
      userPrompt += `\n\nThe following subtasks already exist for this task. Do NOT repeat or rephrase these. Generate ONLY new, different subtasks that complement the existing ones:\n${existingSubtasks.map((s: string) => `- ${s}`).join("\n")}`
    }

    userPrompt += `\n\nReturn ONLY a JSON array of strings. Example: ["Research options", "Draft outline", "Write first draft"]`

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-20250514",
        max_tokens: 1024,
        system: "You are a task planning assistant for a productivity app. Your job is to break tasks into specific, actionable subtasks. Each subtask must start with a verb, be concise (under 60 characters), and be logically ordered. Return ONLY a valid JSON array of strings — no markdown, no explanation.",
        messages: [
          {
            role: "user",
            content: userPrompt,
          },
        ],
      }),
    })

    if (!response.ok) {
      const errorBody = await response.text()
      return new Response(
        JSON.stringify({ subtasks: null, error: `Anthropic API ${response.status}: ${errorBody}` }),
        { status: 200, headers }
      )
    }

    const data = await response.json()
    const content = data.content[0].text

    const subtasks = JSON.parse(content)
    if (
      !Array.isArray(subtasks) ||
      !subtasks.every((s: unknown) => typeof s === "string")
    ) {
      return new Response(
        JSON.stringify({ subtasks: null, error: "Invalid AI response format" }),
        { status: 200, headers }
      )
    }

    return new Response(
      JSON.stringify({ subtasks, error: null }),
      { status: 200, headers }
    )
  } catch (error) {
    return new Response(
      JSON.stringify({ subtasks: null, error: `Server error: ${error.message}` }),
      { status: 200, headers }
    )
  }
})
