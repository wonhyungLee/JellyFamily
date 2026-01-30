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
  if (profile.role !== "CHILD") {
    return error(403, "Only children can request allowance")
  }

  const { data: wallet, error: walletError } = await admin
    .from("wallets")
    .select("cash_balance")
    .eq("user_id", auth.user.id)
    .maybeSingle()

  if (walletError || !wallet) {
    return error(404, "Wallet not found", walletError?.message)
  }

  const requestedCash = body.requested_cash === undefined
    ? wallet.cash_balance
    : body.requested_cash

  if (typeof requestedCash !== "number" || !Number.isInteger(requestedCash) || requestedCash < 0) {
    return error(400, "requested_cash must be a non-negative integer")
  }

  const { data: requestRow, error: insertError } = await admin
    .from("allowance_requests")
    .insert({
      child_id: auth.user.id,
      requested_cash: requestedCash,
    })
    .select("*")
    .single()

  if (insertError || !requestRow) {
    return error(500, "Failed to create request", insertError?.message)
  }

  return json({ request: requestRow })
})
