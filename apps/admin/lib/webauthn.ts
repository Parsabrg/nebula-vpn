/**
 * The browser side of passkeys, with the browser's own JSON helpers
 * (PublicKeyCredential.parse*OptionsFromJSON and toJSON): no library.
 */

interface JsonCredential {
  toJSON(): Record<string, unknown>;
}

interface PublicKeyCredentialJson {
  parseCreationOptionsFromJSON?(
    options: unknown,
  ): PublicKeyCredentialCreationOptions;
  parseRequestOptionsFromJSON?(
    options: unknown,
  ): PublicKeyCredentialRequestOptions;
}

export const PASSKEYS_UNSUPPORTED =
  "This browser cannot use passkeys. Use a current Chrome, Edge, Firefox or Safari.";
export const PASSKEY_CANCELLED = "The passkey prompt was closed. Try again.";

function helpers(): PublicKeyCredentialJson | null {
  if (typeof window === "undefined" || !("PublicKeyCredential" in window)) {
    return null;
  }
  return window.PublicKeyCredential as unknown as PublicKeyCredentialJson;
}

async function run(
  ask: () => Promise<Credential | null>,
): Promise<Record<string, unknown>> {
  let credential: Credential | null;
  try {
    credential = await ask();
  } catch (error) {
    // NotAllowedError: closed, timed out, or no matching passkey.
    throw new Error(
      error instanceof DOMException && error.name === "NotAllowedError"
        ? PASSKEY_CANCELLED
        : PASSKEYS_UNSUPPORTED,
    );
  }
  if (!credential) throw new Error(PASSKEY_CANCELLED);
  return (credential as unknown as JsonCredential).toJSON();
}

export async function createPasskey(
  options: unknown,
): Promise<Record<string, unknown>> {
  const parse = helpers()?.parseCreationOptionsFromJSON;
  if (!parse) throw new Error(PASSKEYS_UNSUPPORTED);
  const publicKey = parse(options);
  return run(() => navigator.credentials.create({ publicKey }));
}

export async function getPasskey(
  options: unknown,
): Promise<Record<string, unknown>> {
  const parse = helpers()?.parseRequestOptionsFromJSON;
  if (!parse) throw new Error(PASSKEYS_UNSUPPORTED);
  const publicKey = parse(options);
  return run(() => navigator.credentials.get({ publicKey }));
}
