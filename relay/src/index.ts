/**
 * Ding APNs Relay - Cloudflare Worker
 * Receives POST /push with a JSON payload and forwards it as a
 * visible push notification via APNs HTTP/2.
 */

interface Env {
  STORE: KVNamespace;
  APPLE_KEYID: string;
  APPLE_TEAMID: string;
  APPLE_AUTHKEY: string;  // Base64-encoded .p8 key content
  RELAY_SECRET: string;   // Shared secret for Bearer auth
  APNS_TOPIC: string;     // iOS app bundle ID (e.g. dev.sijun.ding)
  DEVICE_TOKEN: string;   // Target device token (Phase 1 single device)
}

interface PushPayload {
  title: string;
  body: string;
  status?: string;
  command?: string;
  exitCode?: number;
  duration?: number;
  id?: string;
  timestamp?: string;
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS, GET",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return new Response(null, { headers: CORS_HEADERS });
    }

    const url = new URL(request.url);

    if (url.pathname === "/health" && request.method === "GET") {
      return jsonResponse({ status: "ok", version: "1.0.0", timestamp: new Date().toISOString() });
    }

    if (url.pathname === "/push") {
      if (request.method !== "POST") {
        return new Response("Method Not Allowed", { status: 405, headers: CORS_HEADERS });
      }
      return handlePush(request, env);
    }

    return new Response("Not Found", { status: 404, headers: CORS_HEADERS });
  },
};

async function handlePush(request: Request, env: Env): Promise<Response> {
  // 1. Validate Authorization
  const authHeader = request.headers.get("Authorization");
  if (!authHeader || authHeader !== `Bearer ${env.RELAY_SECRET}`) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  // 2. Parse and validate body
  let payload: PushPayload;
  try {
    payload = await request.json() as PushPayload;
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  if (!payload.title || !payload.body) {
    return jsonResponse({ error: "Missing required fields: title and body" }, 400);
  }

  // 3. Get or generate APNs JWT
  let jwt: string;
  try {
    jwt = await getOrCreateJWT(env);
  } catch (err) {
    return jsonResponse({ error: `JWT generation failed: ${String(err)}` }, 500);
  }

  // 4. Build APNs payload
  const apnsPayload = {
    aps: {
      alert: { title: payload.title, body: payload.body },
      sound: "default",
    },
    ding: payload,
  };

  // 5. Send to APNs (try production first, sandbox on BadDeviceToken)
  const result = await sendToAPNs(env.DEVICE_TOKEN, apnsPayload, jwt, env.APNS_TOPIC, false);

  if (result.status === 200) {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  // Try sandbox on BadDeviceToken
  if (result.reason === "BadDeviceToken") {
    const sandboxResult = await sendToAPNs(env.DEVICE_TOKEN, apnsPayload, jwt, env.APNS_TOPIC, true);
    if (sandboxResult.status === 200) {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }
    return jsonResponse({ error: "BadDeviceToken", reason: sandboxResult.reason }, 400);
  }

  if (result.status === 429) {
    return jsonResponse({ error: "APNs rate limit exceeded" }, 429);
  }

  return jsonResponse({ error: "APNs error", reason: result.reason, status: result.status }, 502);
}

async function sendToAPNs(
  deviceToken: string,
  payload: object,
  jwt: string,
  topic: string,
  sandbox: boolean
): Promise<{ status: number; reason?: string }> {
  const host = sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com";
  const url = `https://${host}/3/device/${deviceToken}`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "authorization": `bearer ${jwt}`,
      "apns-topic": topic,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "apns-expiration": "0",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  if (response.status === 200) {
    return { status: 200 };
  }

  let reason: string | undefined;
  try {
    const body = await response.json() as { reason?: string };
    reason = body.reason;
  } catch {
    reason = undefined;
  }

  return { status: response.status, reason };
}

async function getOrCreateJWT(env: Env): Promise<string> {
  const cached = await env.STORE.get("apns-jwt");
  if (cached) return cached;

  const jwt = await generateJWT(env.APPLE_KEYID, env.APPLE_TEAMID, env.APPLE_AUTHKEY);
  await env.STORE.put("apns-jwt", jwt, { expirationTtl: 2700 });
  return jwt;
}

async function generateJWT(keyId: string, teamId: string, authKeyBase64: string): Promise<string> {
  // Decode base64 .p8 key to PEM string
  const pemString = atob(authKeyBase64);

  // Strip PEM headers and whitespace, then decode to bytes
  const pemBody = pemString
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  // Import ECDSA P-256 key
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );

  // Round iat to 20-minute boundary (prevents TooManyProviderTokenUpdates)
  const iat = Math.floor(Date.now() / 1000 / 1200) * 1200;

  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat }));
  const signingInput = `${header}.${claims}`;

  const encoder = new TextEncoder();
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(signingInput)
  );

  return `${signingInput}.${base64url(signature)}`;
}

function base64url(input: string | ArrayBuffer): string {
  let bytes: Uint8Array;
  if (typeof input === "string") {
    bytes = new TextEncoder().encode(input);
  } else {
    bytes = new Uint8Array(input);
  }
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function jsonResponse(data: object, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}
