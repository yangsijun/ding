/**
 * Ding APNs Relay - Cloudflare Worker
 * Multi-device KV token management with rate limiting.
 */

interface Env {
  STORE: KVNamespace;
  APPLE_KEYID: string;
  APPLE_TEAMID: string;
  APPLE_AUTHKEY: string;  // Base64-encoded .p8 key content
  RELAY_SECRET: string;   // Shared secret for Bearer auth (legacy single-device)
  APNS_TOPIC: string;     // iOS app bundle ID (e.g. dev.sijun.ding)
  DEVICE_TOKEN?: string;  // Optional fallback for single-device mode
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

interface WebhookPayload {
  title: string;
  body: string;
  status?: string;
  source?: string;
}

interface DeviceRecord {
  devices: string[];
  registeredAt: string;
  lastSeenAt: string;
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
      return jsonResponse({ status: "ok", version: "2.0.0", timestamp: new Date().toISOString() });
    }

    if (url.pathname === "/register") {
      if (request.method !== "POST") {
        return new Response("Method Not Allowed", { status: 405, headers: CORS_HEADERS });
      }
      return handleRegister(request, env);
    }

    if (url.pathname === "/deregister") {
      if (request.method !== "POST") {
        return new Response("Method Not Allowed", { status: 405, headers: CORS_HEADERS });
      }
      return handleDeregister(request, env);
    }

    if (url.pathname === "/push") {
      if (request.method !== "POST") {
        return new Response("Method Not Allowed", { status: 405, headers: CORS_HEADERS });
      }
      return handlePush(request, env);
    }

    if (url.pathname === "/webhook") {
      if (request.method !== "POST") {
        return new Response("Method Not Allowed", { status: 405, headers: CORS_HEADERS });
      }
      return handleWebhook(request, env);
    }

    return new Response("Not Found", { status: 404, headers: CORS_HEADERS });
  },
};

// ─── /register ───────────────────────────────────────────────────────────────

async function handleRegister(request: Request, env: Env): Promise<Response> {
  // Validate Authorization
  const apiKey = extractApiKey(request);
  if (!apiKey) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  // Parse body
  let body: { device_token?: string; api_key?: string };
  try {
    body = await request.json() as { device_token?: string; api_key?: string };
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const deviceToken = body.device_token;
  if (!deviceToken || typeof deviceToken !== "string" || deviceToken.length < 32) {
    return jsonResponse({ error: "Missing or invalid device_token" }, 400);
  }

  // Load existing record for this API key
  const kvKey = `devices:${apiKey}`;
  const existing = await env.STORE.get<DeviceRecord>(kvKey, "json");
  const record: DeviceRecord = existing ?? {
    devices: [],
    registeredAt: new Date().toISOString(),
    lastSeenAt: new Date().toISOString(),
  };

  // Add device if not already registered
  if (!record.devices.includes(deviceToken)) {
    record.devices.push(deviceToken);
  }
  record.lastSeenAt = new Date().toISOString();

  await env.STORE.put(kvKey, JSON.stringify(record));

  return jsonResponse({
    ok: true,
    registered: record.devices.length,
    message: `Device registered. ${record.devices.length} device(s) for this API key.`,
  });
}

// ─── /deregister ─────────────────────────────────────────────────────────────

async function handleDeregister(request: Request, env: Env): Promise<Response> {
  const apiKey = extractApiKey(request);
  if (!apiKey) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  let body: { device_token?: string };
  try {
    body = await request.json() as { device_token?: string };
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const deviceToken = body.device_token;
  if (!deviceToken) {
    return jsonResponse({ error: "Missing device_token" }, 400);
  }

  const kvKey = `devices:${apiKey}`;
  const existing = await env.STORE.get<DeviceRecord>(kvKey, "json");
  if (!existing) {
    return jsonResponse({ ok: true, message: "No devices registered for this API key" });
  }

  existing.devices = existing.devices.filter((t) => t !== deviceToken);
  existing.lastSeenAt = new Date().toISOString();
  await env.STORE.put(kvKey, JSON.stringify(existing));

  return jsonResponse({
    ok: true,
    remaining: existing.devices.length,
    message: `Device deregistered. ${existing.devices.length} device(s) remaining.`,
  });
}

// ─── /push ───────────────────────────────────────────────────────────────────

async function handlePush(request: Request, env: Env): Promise<Response> {
  // 1. Validate Authorization
  const apiKey = extractApiKey(request);
  if (!apiKey) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  // 2. Rate limiting: 10 pushes per minute per API key
  const rateLimitKey = `ratelimit:${apiKey}:${Math.floor(Date.now() / 60000)}`;
  const currentCount = parseInt(await env.STORE.get(rateLimitKey) ?? "0", 10);
  if (currentCount >= 10) {
    return jsonResponse({ error: "Rate limit exceeded. Max 10 pushes per minute." }, 429);
  }
  await env.STORE.put(rateLimitKey, String(currentCount + 1), { expirationTtl: 120 });

  // 3. Parse and validate body
  let payload: PushPayload;
  try {
    payload = await request.json() as PushPayload;
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  if (!payload.title || !payload.body) {
    return jsonResponse({ error: "Missing required fields: title and body" }, 400);
  }

  // 4. Get device tokens for this API key
  const kvKey = `devices:${apiKey}`;
  const deviceRecord = await env.STORE.get<DeviceRecord>(kvKey, "json");

  let deviceTokens: string[] = [];
  if (deviceRecord && deviceRecord.devices.length > 0) {
    deviceTokens = deviceRecord.devices;
  } else if (env.DEVICE_TOKEN) {
    // Fallback to single-device mode (legacy)
    deviceTokens = [env.DEVICE_TOKEN];
  } else {
    return jsonResponse({ error: "No devices registered for this API key" }, 404);
  }

  // 5. Get or generate APNs JWT
  let jwt: string;
  try {
    jwt = await getOrCreateJWT(env);
  } catch (err) {
    return jsonResponse({ error: `JWT generation failed: ${String(err)}` }, 500);
  }

  // 6. Build APNs payload
  const apnsPayload = {
    aps: {
      alert: { title: payload.title, body: payload.body },
      sound: "default",
    },
    ding: payload,
  };

  // 7. Fan-out to all registered devices
  let sent = 0;
  let failed = 0;
  let tokensRemoved = 0;
  const tokensToRemove: string[] = [];

  for (const token of deviceTokens) {
    const result = await sendToAPNs(token, apnsPayload, jwt, env.APNS_TOPIC, false);

    if (result.status === 200) {
      sent++;
    } else if (result.reason === "BadDeviceToken") {
      // Try sandbox fallback
      const sandboxResult = await sendToAPNs(token, apnsPayload, jwt, env.APNS_TOPIC, true);
      if (sandboxResult.status === 200) {
        sent++;
      } else {
        // Token is truly bad — mark for removal
        tokensToRemove.push(token);
        failed++;
        tokensRemoved++;
      }
    } else {
      failed++;
    }
  }

  // 8. Remove bad tokens from KV
  if (tokensToRemove.length > 0 && deviceRecord) {
    deviceRecord.devices = deviceRecord.devices.filter((t) => !tokensToRemove.includes(t));
    deviceRecord.lastSeenAt = new Date().toISOString();
    await env.STORE.put(kvKey, JSON.stringify(deviceRecord));
  }

  return jsonResponse({ sent, failed, tokens_removed: tokensRemoved });
}

// ─── /webhook ────────────────────────────────────────────────────────────────

async function handleWebhook(request: Request, env: Env): Promise<Response> {
  // 1. Validate Authorization
  const apiKey = extractApiKey(request);
  if (!apiKey) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  // 2. Rate limiting: 10 webhooks per minute per API key
  const rateLimitKey = `ratelimit:${apiKey}:${Math.floor(Date.now() / 60000)}`;
  const currentCount = parseInt(await env.STORE.get(rateLimitKey) ?? "0", 10);
  if (currentCount >= 10) {
    return jsonResponse({ error: "Rate limit exceeded. Max 10 webhooks per minute." }, 429);
  }
  await env.STORE.put(rateLimitKey, String(currentCount + 1), { expirationTtl: 120 });

  // 3. Parse and validate body
  let payload: WebhookPayload;
  try {
    payload = await request.json() as WebhookPayload;
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  if (!payload.title || !payload.body) {
    return jsonResponse({ error: "Missing required fields: title and body" }, 400);
  }

  // 4. Get device tokens for this API key
  const kvKey = `devices:${apiKey}`;
  const deviceRecord = await env.STORE.get<DeviceRecord>(kvKey, "json");

  let deviceTokens: string[] = [];
  if (deviceRecord && deviceRecord.devices.length > 0) {
    deviceTokens = deviceRecord.devices;
  } else if (env.DEVICE_TOKEN) {
    // Fallback to single-device mode (legacy)
    deviceTokens = [env.DEVICE_TOKEN];
  } else {
    return jsonResponse({ error: "No devices registered for this API key" }, 404);
  }

  // 5. Get or generate APNs JWT
  let jwt: string;
  try {
    jwt = await getOrCreateJWT(env);
  } catch (err) {
    return jsonResponse({ error: `JWT generation failed: ${String(err)}` }, 500);
  }

  // 6. Build APNs payload with source as subtitle if present
  const alertPayload: { title: string; body: string; subtitle?: string } = {
    title: payload.title,
    body: payload.body,
  };
  if (payload.source) {
    alertPayload.subtitle = payload.source;
  }

  const apnsPayload = {
    aps: {
      alert: alertPayload,
      sound: "default",
    },
    ding: payload,
  };

  // 7. Fan-out to all registered devices
  let sent = 0;
  let failed = 0;
  let tokensRemoved = 0;
  const tokensToRemove: string[] = [];

  for (const token of deviceTokens) {
    const result = await sendToAPNs(token, apnsPayload, jwt, env.APNS_TOPIC, false);

    if (result.status === 200) {
      sent++;
    } else if (result.reason === "BadDeviceToken") {
      // Try sandbox fallback
      const sandboxResult = await sendToAPNs(token, apnsPayload, jwt, env.APNS_TOPIC, true);
      if (sandboxResult.status === 200) {
        sent++;
      } else {
        // Token is truly bad — mark for removal
        tokensToRemove.push(token);
        failed++;
        tokensRemoved++;
      }
    } else {
      failed++;
    }
  }

  // 8. Remove bad tokens from KV
  if (tokensToRemove.length > 0 && deviceRecord) {
    deviceRecord.devices = deviceRecord.devices.filter((t) => !tokensToRemove.includes(t));
    deviceRecord.lastSeenAt = new Date().toISOString();
    await env.STORE.put(kvKey, JSON.stringify(deviceRecord));
  }

  return jsonResponse({ sent, failed, tokens_removed: tokensRemoved });
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function extractApiKey(request: Request): string | null {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) return null;
  if (authHeader.startsWith("Bearer ")) {
    return authHeader.slice(7);
  }
  return null;
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
