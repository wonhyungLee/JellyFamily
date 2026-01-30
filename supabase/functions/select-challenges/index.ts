import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import {
  createAdminClient,
  daysInMonth,
  error,
  getAuthUser,
  json,
  parseYearMonth,
  prevYearMonth,
  seoulYearMonth,
} from "../_shared/utils.ts"

const ALLOWED_CHALLENGES = new Set([
  "BOOK_READING",
  "ARITHMETIC",
  "HANJA_WRITING",
])

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
    return error(403, "Only children can select challenges")
  }

  const yearMonth = typeof body.year_month === "string"
    ? body.year_month
    : seoulYearMonth()

  const parsed = parseYearMonth(yearMonth)
  if (!parsed) {
    return error(400, "Invalid year_month format", yearMonth)
  }

  const challengeA = body.challenge_a
  const challengeB = body.challenge_b
  if (typeof challengeA !== "string" || typeof challengeB !== "string") {
    return error(400, "challenge_a and challenge_b are required")
  }
  if (!ALLOWED_CHALLENGES.has(challengeA) || !ALLOWED_CHALLENGES.has(challengeB)) {
    return error(400, "Invalid challenge type")
  }
  if (challengeA === challengeB) {
    return error(400, "Challenges must be different")
  }

  const pairKey = [challengeA, challengeB].sort().join("|")

  const { data: existing, error: existingError } = await admin
    .from("challenge_months")
    .select("*")
    .eq("child_id", auth.user.id)
    .eq("year_month", yearMonth)
    .maybeSingle()

  if (existingError) {
    return error(500, "Failed to load existing month", existingError.message)
  }

  if (existing) {
    if (existing.pair_key !== pairKey) {
      return error(409, "Challenges already selected for this month")
    }
    const { data: days } = await admin
      .from("challenge_days")
      .select("day_date, status, memo")
      .eq("challenge_month_id", existing.id)
      .order("day_date")

    return json({ month: existing, days: days ?? [] })
  }

  const prevMonth = prevYearMonth(parsed.year, parsed.month)
  const { data: prev } = await admin
    .from("challenge_months")
    .select("pair_key")
    .eq("child_id", auth.user.id)
    .eq("year_month", prevMonth)
    .maybeSingle()

  if (prev?.pair_key === pairKey) {
    return error(409, "Same pair as previous month is not allowed", {
      previous_month: prevMonth,
    })
  }

  const { data: inserted, error: insertError } = await admin
    .from("challenge_months")
    .insert({
      child_id: auth.user.id,
      year_month: yearMonth,
      challenge_a: challengeA,
      challenge_b: challengeB,
      pair_key: pairKey,
    })
    .select("*")
    .single()

  if (insertError || !inserted) {
    return error(500, "Failed to create challenge month", insertError?.message)
  }

  const totalDays = daysInMonth(parsed.year, parsed.month)
  const dayRows = [] as Array<{ challenge_month_id: string; day_date: string }>
  for (let day = 1; day <= totalDays; day += 1) {
    const dayStr = `${yearMonth}-${String(day).padStart(2, "0")}`
    dayRows.push({ challenge_month_id: inserted.id, day_date: dayStr })
  }

  const { error: dayError } = await admin
    .from("challenge_days")
    .upsert(dayRows, { onConflict: "challenge_month_id,day_date" })

  if (dayError) {
    return error(500, "Failed to create challenge days", dayError.message)
  }

  const { data: days } = await admin
    .from("challenge_days")
    .select("day_date, status, memo")
    .eq("challenge_month_id", inserted.id)
    .order("day_date")

  return json({ month: inserted, days: days ?? [] })
})
