import { createClient } from "npm:@supabase/supabase-js@2.117.3";
import { importPKCS8, SignJWT } from "npm:jose@6.1.0";
import { classifyApnsFailure } from "./apns.ts";

type Job = {
  job_id: string;
  device_token: string;
  device_environment: "sandbox" | "production";
  notification_title: string;
  notification_body: string;
  notification_payload: Record<string, unknown>;
  attempt_number: number;
};

let providerTokenCache:
  | { value: string; createdAt: number; keyId: string; teamId: string }
  | undefined;

async function providerToken(
  privateKey: string,
  keyId: string,
  teamId: string,
) {
  const now = Date.now();
  if (
    providerTokenCache &&
    providerTokenCache.keyId === keyId &&
    providerTokenCache.teamId === teamId &&
    now - providerTokenCache.createdAt < 50 * 60 * 1000
  ) return providerTokenCache.value;
  const key = await importPKCS8(privateKey.replace(/\\n/g, "\n"), "ES256");
  const value = await new SignJWT({}).setProtectedHeader({
    alg: "ES256",
    kid: keyId,
  })
    .setIssuer(teamId).setIssuedAt().sign(key);
  providerTokenCache = { value, createdAt: now, keyId, teamId };
  return value;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: { Allow: "POST" },
    });
  }
  const expected = Deno.env.get("DELIVERY_WEBHOOK_SECRET");
  if (
    !expected || request.headers.get("authorization") !== `Bearer ${expected}`
  ) return new Response("Unauthorized", { status: 401 });
  const required = [
    "SUPABASE_URL",
    "APNS_KEY_ID",
    "APNS_TEAM_ID",
    "APNS_BUNDLE_ID",
    "APNS_PRIVATE_KEY",
  ] as const;
  const missing: string[] = required.filter((key) => !Deno.env.get(key));
  let serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const configuredSecretKeys = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (configuredSecretKeys) {
    try {
      serviceKey =
        (JSON.parse(configuredSecretKeys) as Record<string, string>).default;
    } catch {
      return Response.json({ error: "INVALID_SECRET_KEY_CONFIGURATION" }, {
        status: 503,
      });
    }
  }
  if (!serviceKey) missing.push("SUPABASE_SECRET_KEYS");
  if (missing.length) {
    return Response.json({ error: "NOT_CONFIGURED", missing }, { status: 503 });
  }
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    serviceKey!,
    { auth: { persistSession: false } },
  );
  const complete = async (
    job: Job,
    result: {
      delivered: boolean;
      terminal: boolean;
      deactivateDevice: boolean;
      error: string | null;
    },
  ) => {
    const { error } = await supabase.rpc("complete_notification_job", {
      p_job_id: job.job_id,
      p_attempt_number: job.attempt_number,
      p_delivered: result.delivered,
      p_terminal: result.terminal,
      p_deactivate_device: result.deactivateDevice,
      p_error: result.error,
    });
    return error;
  };
  const { data: reminderResult, error: reminderError } = await supabase.rpc(
    "enqueue_due_event_reminders",
    {},
  );
  if (reminderError) {
    return Response.json({ error: reminderError.message }, { status: 500 });
  }
  const { data, error } = await supabase.rpc("claim_notification_jobs", {
    p_limit: 25,
  });
  if (error) return Response.json({ error: error.message }, { status: 500 });
  const token = await providerToken(
    Deno.env.get("APNS_PRIVATE_KEY")!,
    Deno.env.get("APNS_KEY_ID")!,
    Deno.env.get("APNS_TEAM_ID")!,
  );
  let delivered = 0;
  const completionErrors: string[] = [];
  const jobs = (data ?? []) as Job[];
  await Promise.all(jobs.map(async (job) => {
    const production = job.device_environment === "production";
    try {
      const response = await fetch(
        `https://${
          production ? "api" : "api.sandbox"
        }.push.apple.com/3/device/${job.device_token}`,
        {
          method: "POST",
          headers: {
            authorization: `bearer ${token}`,
            "apns-topic": Deno.env.get("APNS_BUNDLE_ID")!,
            "apns-push-type": "alert",
            "apns-expiration": "0",
            "apns-priority": "10",
            "content-type": "application/json",
          },
          body: JSON.stringify({
            aps: {
              alert: {
                title: job.notification_title,
                body: job.notification_body,
              },
              sound: "default",
            },
            sidequest: job.notification_payload,
          }),
          signal: AbortSignal.timeout(15000),
        },
      );
      let responseBody = "";
      if (!response.ok) {
        responseBody = await response.text();
      }
      const failure = response.ok
        ? undefined
        : classifyApnsFailure(response.status, responseBody);
      const completionError = await complete(job, {
        delivered: response.ok,
        terminal: failure?.terminal ?? false,
        deactivateDevice: failure?.deactivateDevice ?? false,
        error: failure?.error ?? null,
      });
      if (completionError) {
        completionErrors.push(`${job.job_id}: ${completionError.message}`);
      }
      if (response.ok && !completionError) delivered++;
    } catch (error) {
      const message = error instanceof Error
        ? error.message
        : "APNs request failed";
      const completionError = await complete(job, {
        delivered: false,
        terminal: false,
        deactivateDevice: false,
        error: message,
      });
      if (completionError) {
        completionErrors.push(`${job.job_id}: ${completionError.message}`);
      }
    }
  }));
  return Response.json({
    claimed: jobs.length,
    delivered,
    reminders_enqueued: (reminderResult as { enqueued?: number } | null)
      ?.enqueued ?? 0,
    completion_errors: completionErrors,
  }, { status: completionErrors.length ? 502 : 200 });
});
