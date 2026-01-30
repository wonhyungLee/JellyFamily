import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import {
  createAdminClient,
  error,
  getAuthUser,
  json,
  seoulYearMonth,
} from "../_shared/utils.ts"

const API_BASE = "https://date.nager.at/api/v3/PublicHolidays"

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return error(405, "Method not allowed")
  }

  const auth = await getAuthUser(req)
  if (auth.error) return auth.error

  let body: Record<string, unknown> = {}
  try {
    body = await req.json()
  } catch {
    body = {}
  }

  const year = typeof body.year === "number"
    ? body.year
    : Number(seoulYearMonth().slice(0, 4))

  if (!year || year < 1900 || year > 2100) {
    return error(400, "Invalid year")
  }

  const res = await fetch(`${API_BASE}/${year}/KR`)
  if (!res.ok) {
    return error(502, "Holiday API error", { status: res.status })
  }
  const data = await res.json()
  if (!Array.isArray(data)) {
    return error(502, "Holiday API invalid response")
  }

  const holidays = data
    .filter((h) => Array.isArray(h?.types) && h.types.includes("Public"))
    .map((h) => ({
      day_date: h.date,
      name: h.localName ?? h.name ?? "",
    }))

  if (holidays.length === 0) {
    return error(502, "No holidays returned")
  }

  const admin = createAdminClient()
  const { error: upsertError } = await admin
    .from("public_holidays")
    .upsert(holidays, { onConflict: "day_date" })

  if (upsertError) {
    return error(500, "Failed to upsert holidays", upsertError.message)
  }

  return json({ year, count: holidays.length })
})
