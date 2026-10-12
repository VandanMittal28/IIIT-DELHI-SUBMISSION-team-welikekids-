import { classifyApnsFailure } from "./apns.ts";

function assert(condition: boolean, message: string) {
  if (!condition) throw new Error(message);
}

Deno.test("invalid device tokens are terminal and deactivate the token", () => {
  const result = classifyApnsFailure(
    410,
    JSON.stringify({ reason: "Unregistered" }),
  );
  assert(result.terminal, "Unregistered should not be retried");
  assert(result.deactivateDevice, "Unregistered token should be deactivated");
});

Deno.test("provider throttling remains retryable", () => {
  const result = classifyApnsFailure(
    429,
    JSON.stringify({ reason: "TooManyRequests" }),
  );
  assert(!result.terminal, "TooManyRequests should be retried");
  assert(!result.deactivateDevice, "Throttling must not deactivate a device");
});

Deno.test("provider configuration errors do not invalidate a device", () => {
  const result = classifyApnsFailure(
    403,
    JSON.stringify({ reason: "Forbidden" }),
  );
  assert(result.terminal, "Forbidden should not be retried for the same job");
  assert(
    !result.deactivateDevice,
    "Provider configuration errors must not deactivate a device",
  );
});
