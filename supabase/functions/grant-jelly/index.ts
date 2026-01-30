import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import {
  createAdminClient,
  error,
  getAuthUser,
  getSeoulParts,
  json,
  seoulDateString,
} from "../_shared/utils.ts"

const ALLOWED_CHALLENGES = new Set([
  "BOOK_READING",
  "ARITHMETIC",
  "HANJA_WRITING",
])
const ALLOWED_JELLY = new Set(["NORMAL", "SPECIAL", "BONUS"])

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
    return error(403, "Only parents can grant jelly")
  }

  // Time restriction removed per requirement.

  const childId = body.child_id
  const challenge = body.challenge
  const jelly = body.jelly
  const amount = 1
  const targetDate = typeof body.target_date === "string" ? body.target_date : seoulDateString()

  if (typeof childId !== "string" || typeof challenge !== "string" || typeof jelly !== "string") {
    return error(400, "child_id, challenge, jelly are required")
  }
  if (!ALLOWED_CHALLENGES.has(challenge)) {
    return error(400, "Invalid challenge")
  }
  if (!ALLOWED_JELLY.has(jelly)) {
    return error(400, "Invalid jelly type")
  }
  if (jelly !== "NORMAL") {
    return error(403, "SPECIAL/BONUS are self-claimed by children")
  }
  // amount is fixed to 1 per grant

  const today = seoulDateString(0)
  const yesterday = seoulDateString(-1)
  if (targetDate !== today && targetDate !== yesterday) {
    return error(400, "target_date must be today or yesterday (Asia/Seoul)", {
      today,
      yesterday,
    })
  }

  const { data: childProfile, error: childError } = await admin
    .from("profiles")
    .select("id, role")
    .eq("id", childId)
    .maybeSingle()

  if (childError || !childProfile) {
    return error(404, "Child profile not found", childError?.message)
  }
  if (childProfile.role !== "CHILD") {
    return error(400, "Target user is not a child")
  }

  const { data: wallet, error: walletError } = await admin
    .from("wallets")
    .select("*")
    .eq("user_id", childId)
    .maybeSingle()

  if (walletError || !wallet) {
    return error(404, "Wallet not found", walletError?.message)
  }

  const nextWallet = {
    jelly_normal: wallet.jelly_normal,
    jelly_special: wallet.jelly_special,
    jelly_bonus: wallet.jelly_bonus,
    cash_balance: wallet.cash_balance,
    updated_at: new Date().toISOString(),
  }

  if (jelly === "NORMAL") nextWallet.jelly_normal += amount
  if (jelly === "SPECIAL") nextWallet.jelly_special += amount
  if (jelly === "BONUS") nextWallet.jelly_bonus += amount

  const { data: updatedWallet, error: updateError } = await admin
    .from("wallets")
    .update(nextWallet)
    .eq("user_id", childId)
    .select("*")
    .single()

  if (updateError || !updatedWallet) {
    return error(500, "Failed to update wallet", updateError?.message)
  }

  const { data: grant, error: grantError } = await admin
    .from("jelly_grants")
    .insert({
      child_id: childId,
      parent_id: auth.user.id,
      challenge,
      jelly,
      amount,
      target_date: targetDate,
    })
    .select("*")
    .single()

  if (grantError || !grant) {
    return error(500, "Failed to insert grant", grantError?.message)
  }

  const yearMonth = targetDate.slice(0, 7)
  const { data: monthRow } = await admin
    .from("challenge_months")
    .select("id")
    .eq("child_id", childId)
    .eq("year_month", yearMonth)
    .maybeSingle()

  if (monthRow?.id) {
    await admin
      .from("challenge_days")
      .update({ status: "REWARDED" })
      .eq("challenge_month_id", monthRow.id)
      .eq("day_date", targetDate)
  }

  return json({ grant, wallet: updatedWallet })
})
