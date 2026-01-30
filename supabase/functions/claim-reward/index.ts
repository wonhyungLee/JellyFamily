import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import {
  createAdminClient,
  dateRange,
  dateToUtc,
  error,
  formatDate,
  getAuthUser,
  json,
  monthRange,
  parseDateString,
  parseYearMonth,
  seoulDateString,
  weekRange,
} from "../_shared/utils.ts"

const ALLOWED = new Set(["SPECIAL", "BONUS"])

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
    return error(403, "Only children can claim rewards")
  }

  const jelly = body.jelly
  if (typeof jelly !== "string" || !ALLOWED.has(jelly)) {
    return error(400, "jelly must be SPECIAL or BONUS")
  }

  const targetDate = typeof body.target_date === "string"
    ? body.target_date
    : seoulDateString()

  if (!parseDateString(targetDate)) {
    return error(400, "Invalid target_date")
  }

  const today = seoulDateString()
  if (targetDate > today) {
    return error(400, "target_date cannot be in the future", { today })
  }

  let periodKey = ""
  let startDate: Date
  let endDate: Date

  if (jelly === "SPECIAL") {
    const yearMonth = targetDate.slice(0, 7)
    const parsed = parseYearMonth(yearMonth)
    if (!parsed) return error(400, "Invalid year_month")
    const range = monthRange(parsed.year, parsed.month)
    startDate = range.start
    endDate = range.end
    periodKey = yearMonth
  } else {
    const range = weekRange(targetDate)
    if (!range) return error(400, "Invalid target_date")
    startDate = range.start
    endDate = range.end
    periodKey = formatDate(startDate)
  }

  const targetUtc = dateToUtc(targetDate)
  if (!targetUtc) return error(400, "Invalid target_date")

  const { data: existing } = await admin
    .from("reward_claims")
    .select("id")
    .eq("child_id", auth.user.id)
    .eq("reward_type", jelly)
    .eq("period_key", periodKey)
    .maybeSingle()

  if (existing) {
    return error(409, "Reward already claimed")
  }

  const { data: holidayRows, error: holidayError } = await admin
    .from("public_holidays")
    .select("day_date")
    .gte("day_date", formatDate(startDate))
    .lte("day_date", formatDate(endDate))

  if (holidayError) {
    return error(500, "Failed to load holidays", holidayError.message)
  }

  const holidaySet = new Set((holidayRows ?? []).map((h) => h.day_date))
  const allDates = dateRange(startDate, endDate)
  const requiredDates = allDates.filter((d) => !holidaySet.has(d))

  if (requiredDates.length === 0) {
    return error(400, "No required days in this period")
  }

  const lastRequiredDate = requiredDates[requiredDates.length - 1]
  if (targetDate < lastRequiredDate) {
    return error(403, "Period not complete yet", { last_required_date: lastRequiredDate })
  }

  const { data: grants, error: grantError } = await admin
    .from("jelly_grants")
    .select("target_date")
    .eq("child_id", auth.user.id)
    .eq("jelly", "NORMAL")
    .gte("target_date", formatDate(startDate))
    .lte("target_date", formatDate(endDate))

  if (grantError) {
    return error(500, "Failed to load grants", grantError.message)
  }

  const grantSet = new Set((grants ?? []).map((g) => g.target_date))
  const missing = requiredDates.filter((d) => !grantSet.has(d))
  if (missing.length > 0) {
    return error(403, "Not all NORMAL jellies granted", { missing })
  }

  const { data: wallet, error: walletError } = await admin
    .from("wallets")
    .select("*")
    .eq("user_id", auth.user.id)
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

  if (jelly === "SPECIAL") nextWallet.jelly_special += 1
  if (jelly === "BONUS") nextWallet.jelly_bonus += 1

  const { data: updatedWallet, error: updateError } = await admin
    .from("wallets")
    .update(nextWallet)
    .eq("user_id", auth.user.id)
    .select("*")
    .single()

  if (updateError || !updatedWallet) {
    return error(500, "Failed to update wallet", updateError?.message)
  }

  const { error: claimError } = await admin
    .from("reward_claims")
    .insert({
      child_id: auth.user.id,
      reward_type: jelly,
      period_key: periodKey,
    })

  if (claimError) {
    return error(500, "Failed to record claim", claimError.message)
  }

  return json({
    wallet: updatedWallet,
    reward_type: jelly,
    period_key: periodKey,
  })
})
