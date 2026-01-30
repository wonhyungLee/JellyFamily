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

  const admin = createAdminClient()
  const { data: profile, error: profileError } = await admin
    .from("profiles")
    .select("id, role")
    .eq("id", auth.user.id)
    .maybeSingle()

  if (profileError || !profile) {
    return error(403, "Profile not found", profileError?.message)
  }
  if (profile.role !== "PARENT") {
    return error(403, "Only parents can upload proof")
  }

  const requestId = body.request_id
  const objectPath = body.object_path
  if (typeof requestId !== "string" || typeof objectPath !== "string") {
    return error(400, "request_id and object_path are required")
  }

  const { data: requestRow, error: requestError } = await admin
    .from("allowance_requests")
    .select("*")
    .eq("id", requestId)
    .maybeSingle()

  if (requestError || !requestRow) {
    return error(404, "Allowance request not found", requestError?.message)
  }

  if (requestRow.status === "SETTLED") {
    const { data: existingProof } = await admin
      .from("allowance_proofs")
      .select("*")
      .eq("request_id", requestId)
      .maybeSingle()

    return json({ request: requestRow, proof: existingProof })
  }

  const { data: proofRow, error: proofError } = await admin
    .from("allowance_proofs")
    .upsert({
      request_id: requestId,
      uploader_parent_id: auth.user.id,
      object_path: objectPath,
    }, { onConflict: "request_id" })
    .select("*")
    .single()

  if (proofError || !proofRow) {
    return error(500, "Failed to store proof", proofError?.message)
  }

  const { data: updatedRequest, error: updateError } = await admin
    .from("allowance_requests")
    .update({
      status: "SETTLED",
      settled_at: new Date().toISOString(),
    })
    .eq("id", requestId)
    .select("*")
    .single()

  if (updateError || !updatedRequest) {
    return error(500, "Failed to settle request", updateError?.message)
  }

  const { error: walletError } = await admin
    .from("wallets")
    .update({
      cash_balance: 0,
      updated_at: new Date().toISOString(),
    })
    .eq("user_id", requestRow.child_id)

  if (walletError) {
    return error(500, "Failed to reset child wallet", walletError.message)
  }

  return json({ request: updatedRequest, proof: proofRow })
})
