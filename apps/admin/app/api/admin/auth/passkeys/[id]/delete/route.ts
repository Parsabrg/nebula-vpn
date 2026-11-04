import { type NextRequest, NextResponse } from "next/server";
import { proxyAdminAuthRequest } from "@/lib/api/auth-proxy";

const ID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const { id } = await params;
  // Only an id reaches the API path, never anything that could change it.
  if (!ID.test(id)) {
    return NextResponse.json({ detail: "Not found" }, { status: 404 });
  }
  return proxyAdminAuthRequest(request, `/v1/admin/auth/passkeys/${id}/delete`);
}
