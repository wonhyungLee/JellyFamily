import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import {
  createAdminClient,
  error,
  getAuthUser,
  json,
} from "../_shared/utils.ts"

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return error(405, "Method not allowed")
  }

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return error(400, "Invalid JSON body")
  }

  const auth = await getAuthUser(req)
  if (auth.error) return auth.error

  const requestId = body.request_id
  if (typeof requestId !== "string") {
    return error(400, "request_id is required")
  }

  const admin = createAdminClient()
  const { data: proofRow, error: proofError } = await admin
    .from("allowance_proofs")
    .select("id, object_path, request_id")
    .eq("request_id", requestId)
    .maybeSingle()

  if (proofError || !proofRow) {
    return error(404, "Proof not found", proofError?.message)
  }

  const { data: requestRow, error: requestError } = await admin
    .from("allowance_requests")
    .select("child_id")
    .eq("id", requestId)
    .maybeSingle()

  if (requestError || !requestRow) {
    return error(404, "Request not found", requestError?.message)
  }

  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("id, role")
    .eq("id", auth.user.id)
    .maybeSingle()

  if (profileError || !profile) {
    return error(403, "Profile not found", profileError?.message)
  }

  const isParent = profile.role === "PARENT"
  const isChildOwner = requestRow.child_id === auth.user.id
  if (!isParent && !isChildOwner) {
    return error(403, "Not authorized")
  }

  const { data: signed, error: signedError } = await admin
    .storage
    .from("allowance-proofs")
    .createSignedUrl(proofRow.object_path, 60 * 10)

  if (signedError || !signed) {
    return error(500, "Failed to create signed URL", signedError?.message)
  }

  return json({
    signed_url: signed.signedUrl,
    expires_in: 600,
  })
})
