import { describe, it, expect } from "vitest";

// Test the pure helper functions and validation logic
// We test the logic, not the Cloudflare Workers runtime

describe("Token validation", () => {
  function isValidDeviceToken(token: string): boolean {
    return typeof token === "string" && token.length >= 32;
  }

  it("accepts valid 64-char token", () => {
    expect(isValidDeviceToken("a".repeat(64))).toBe(true);
  });

  it("accepts 32-char minimum token", () => {
    expect(isValidDeviceToken("a".repeat(32))).toBe(true);
  });

  it("rejects short token", () => {
    expect(isValidDeviceToken("a".repeat(31))).toBe(false);
  });

  it("rejects empty string", () => {
    expect(isValidDeviceToken("")).toBe(false);
  });
});

describe("API key extraction", () => {
  function extractApiKey(authHeader: string | null): string | null {
    if (!authHeader) return null;
    if (authHeader.startsWith("Bearer ")) {
      return authHeader.slice(7);
    }
    return null;
  }

  it("extracts key from Bearer token", () => {
    expect(extractApiKey("Bearer mykey123")).toBe("mykey123");
  });

  it("returns null for missing header", () => {
    expect(extractApiKey(null)).toBeNull();
  });

  it("returns null for non-Bearer auth", () => {
    expect(extractApiKey("Basic abc123")).toBeNull();
  });

  it("returns null for empty string", () => {
    expect(extractApiKey("")).toBeNull();
  });
});

describe("Rate limit key generation", () => {
  it("generates consistent key for same minute", () => {
    const now = Date.now();
    const key1 = `ratelimit:apikey:${Math.floor(now / 60000)}`;
    const key2 = `ratelimit:apikey:${Math.floor(now / 60000)}`;
    expect(key1).toBe(key2);
  });

  it("generates different keys for different minutes", () => {
    const minute1 = `ratelimit:apikey:${Math.floor(1000000 / 60000)}`;
    const minute2 = `ratelimit:apikey:${Math.floor(1060001 / 60000)}`;
    expect(minute1).not.toBe(minute2);
  });
});

describe("Sound name generation", () => {
  function getSoundName(status?: string): string {
    return status ? `ding_${status}.caf` : "default";
  }

  it("returns correct sound for success", () => {
    expect(getSoundName("success")).toBe("ding_success.caf");
  });

  it("returns correct sound for failure", () => {
    expect(getSoundName("failure")).toBe("ding_failure.caf");
  });

  it("returns default when no status", () => {
    expect(getSoundName()).toBe("default");
  });

  it("returns default for undefined", () => {
    expect(getSoundName(undefined)).toBe("default");
  });
});

describe("Webhook payload validation", () => {
  function isValidWebhookPayload(payload: { title?: string; body?: string }): boolean {
    return !!(payload.title && payload.body);
  }

  it("accepts valid payload", () => {
    expect(isValidWebhookPayload({ title: "CI", body: "Build passed" })).toBe(true);
  });

  it("rejects missing title", () => {
    expect(isValidWebhookPayload({ body: "Build passed" })).toBe(false);
  });

  it("rejects missing body", () => {
    expect(isValidWebhookPayload({ title: "CI" })).toBe(false);
  });

  it("rejects empty payload", () => {
    expect(isValidWebhookPayload({})).toBe(false);
  });
});
