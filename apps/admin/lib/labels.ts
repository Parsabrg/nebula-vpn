/** Words for the API's codes ("pending_activation" -> "Pending activation").
 * Most read fine with the underscores gone; the rest are spelled out here. */
const WORDS: Record<string, string> = {
  // Audit events
  admin_seeded: "First admin created",
  identity_state_changed: "Account state changed",
  account_request_changed: "Account request decided",
  profile_changed: "Protocol changed",
  permission_changed: "Protocol access changed",
  server_changed: "Server changed",
  capability_changed: "Server protocol changed",
  assignment_changed: "Server access changed",
  credential_changed: "VPN credential changed",
  peer_changed: "WireGuard peer changed",
  operation_changed: "Server operation changed",
  email_delivery_changed: "Email changed",
  user_authenticated: "User signed in",
  admin_authenticated: "Admin signed in",
  refresh_rotated: "Session refreshed",
  refresh_reuse_detected: "Stolen session token used",
  password_reset_requested: "Password reset asked for",
  password_reset_consumed: "Password reset used",
  admin_mfa_changed: "Admin authenticator changed",
  admin_mfa_challenged: "Admin asked for a code",
  admin_recovery_code_used: "Admin recovery code used",
  auth_lockout_changed: "Sign-in lockout changed",
  auth_rate_limited: "Too many sign-in attempts",
  csrf_validation: "Form check failed",
  expiry_set: "Expiry set",
  // Who and what
  auth_attempt: "Sign-in attempt",
  user_session: "User session",
  admin_session: "Admin session",
  refresh_token: "Session token",
  admin_totp_credential: "Admin authenticator",
  admin_recovery_code: "Admin recovery code",
  protocol_profile: "Protocol",
  permission: "Protocol access",
  vpn_server: "VPN server",
  server_capability: "Server protocol",
  assignment: "Server access",
  device_credential: "VPN credential",
  wireguard_peer: "WireGuard peer",
  xray_client: "Xray client",
  agent_operation: "Server operation",
  email_delivery: "Email",
  // Email templates
  account_request_review: "New account request (to admins)",
  user_activation: "Activation link",
  request_rejected: "Request not approved",
};

export function label(code: string): string {
  const known = WORDS[code];
  if (known) return known;
  const words = code.replaceAll("_", " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}

/** Select options for a list of codes. */
export function codeOptions(codes: readonly string[]) {
  return codes.map((value) => ({ value, label: label(value) }));
}
