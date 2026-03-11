/**
 * Ding APNs Relay - Cloudflare Worker
 *
 * Receives POST /push with a JSON payload and forwards it as a
 * silent push notification via APNs HTTP/2.
 */

interface Env {
  STORE: KVNamespace;
  APPLE_KEYID: string;
  APPLE_TEAMID: string;
  APPLE_AUTHKEY: string;  // Base64-encoded .p8 key
  RELAY_SECRET: string;   // Shared secret for Bearer auth
  APNS_TOPIC: string;     // iOS app bundle ID
  DEVICE_TOKEN: string;   // Hardcoded single token for Phase 1 MVP
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    // CORS headers
    const corsHeaders = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS, GET",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
    };

    if (request.method === "OPTIONS") {
      return new Response(null, { headers: corsHeaders });
    }

    const url = new URL(request.url);

    if (url.pathname === "/health" && request.method === "GET") {
      return new Response(JSON.stringify({ status: "ok", timestamp: new Date().toISOString() }), {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    if (url.pathname === "/push") {
      if (request.method !== "POST") {
        return new Response("Method Not Allowed", { status: 405, headers: corsHeaders });
      }
      return handlePush(request, env, corsHeaders);
    }

    return new Response("Not Found", { status: 404, headers: corsHeaders });
  },
};

async function handlePush(request: Request, env: Env, corsHeaders: Record<string, string>): Promise<Response> {
  try {
    // Check authorization header
    const authHeader = request.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({
        success: false,
        error: "Missing or invalid Authorization header",
      }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const payload = await request.json();

    // Stub: Full implementation in Task 5
    return new Response(JSON.stringify({
      success: true,
      message: "Push endpoint stub - full implementation in Task 5",
      timestamp: new Date().toISOString(),
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (error) {
    return new Response(JSON.stringify({
      success: false,
      error: String(error),
    }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
}
