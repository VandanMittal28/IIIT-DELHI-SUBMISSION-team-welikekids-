export type ApnsFailure = {
  error: string;
  terminal: boolean;
  deactivateDevice: boolean;
};

const terminalReasons = new Set([
  "BadDeviceToken",
  "DeviceTokenNotForTopic",
  "Forbidden",
  "ExpiredToken",
  "Unregistered",
  "PayloadTooLarge",
]);

const invalidDeviceReasons = new Set([
  "BadDeviceToken",
  "DeviceTokenNotForTopic",
  "Unregistered",
]);

export function classifyApnsFailure(
  status: number,
  responseBody: string,
): ApnsFailure {
  let reason: string | undefined;
  try {
    reason = (JSON.parse(responseBody) as { reason?: string }).reason;
  } catch { /* retain the raw APNs response */ }
  return {
    error: `${status} ${
      reason ?? (responseBody || "APNs rejected the request")
    }`,
    terminal: reason ? terminalReasons.has(reason) : false,
    deactivateDevice: reason ? invalidDeviceReasons.has(reason) : false,
  };
}
