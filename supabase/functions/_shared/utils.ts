import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? ""
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? ""
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""

if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SUPABASE_SERVICE_ROLE_KEY) {
  console.error("Missing Supabase env vars")
}

export function createUserClient(token: string) {
  return createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { persistSession: false },
    global: {
      headers: { Authorization: `Bearer ${token}` },
    },
  })
}

export function createAdminClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false },
  })
}

export function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  })
}

export function error(status: number, message: string, details?: unknown) {
  return json({ error: message, details }, status)
}

export async function getAuthUser(req: Request) {
  const authHeader = req.headers.get("Authorization") || ""
  if (!authHeader.startsWith("Bearer ")) {
    return { error: error(401, "Missing bearer token") }
  }
  const token = authHeader.replace("Bearer ", "").trim()
  if (!token) {
    return { error: error(401, "Missing bearer token") }
  }
  const userClient = createUserClient(token)
  const { data, error: authError } = await userClient.auth.getUser()
  if (authError || !data?.user) {
    return { error: error(401, "Invalid token", authError?.message) }
  }
  return { user: data.user, token, userClient }
}

export function getSeoulParts(date = new Date()) {
  const formatter = new Intl.DateTimeFormat("en-CA", {
    timeZone: "Asia/Seoul",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  })
  const parts = formatter.formatToParts(date)
  const lookup: Record<string, string> = {}
  for (const part of parts) {
    if (part.type !== "literal") lookup[part.type] = part.value
  }
  const year = Number(lookup.year)
  const month = Number(lookup.month)
  const day = Number(lookup.day)
  const hour = Number(lookup.hour)
  const minute = Number(lookup.minute)
  const second = Number(lookup.second)
  const dateStr = `${lookup.year}-${lookup.month}-${lookup.day}`
  return { year, month, day, hour, minute, second, dateStr }
}

export function seoulDateString(offsetDays = 0) {
  const { year, month, day } = getSeoulParts()
  const baseUtc = new Date(Date.UTC(year, month - 1, day))
  baseUtc.setUTCDate(baseUtc.getUTCDate() + offsetDays)
  const y = baseUtc.getUTCFullYear()
  const m = String(baseUtc.getUTCMonth() + 1).padStart(2, "0")
  const d = String(baseUtc.getUTCDate()).padStart(2, "0")
  return `${y}-${m}-${d}`
}

export function seoulYearMonth(date = new Date()) {
  const { year, month } = getSeoulParts(date)
  return `${year}-${String(month).padStart(2, "0")}`
}

export function parseYearMonth(value: string) {
  const match = /^\d{4}-\d{2}$/.exec(value)
  if (!match) return null
  const [yearStr, monthStr] = value.split("-")
  const year = Number(yearStr)
  const month = Number(monthStr)
  if (!year || month < 1 || month > 12) return null
  return { year, month }
}

export function daysInMonth(year: number, month: number) {
  return new Date(Date.UTC(year, month, 0)).getUTCDate()
}

export function parseDateString(dateStr: string) {
  const match = /^\d{4}-\d{2}-\d{2}$/.exec(dateStr)
  if (!match) return null
  const [yearStr, monthStr, dayStr] = dateStr.split("-")
  const year = Number(yearStr)
  const month = Number(monthStr)
  const day = Number(dayStr)
  if (!year || month < 1 || month > 12 || day < 1 || day > 31) return null
  return { year, month, day }
}

export function dateToUtc(dateStr: string) {
  const parsed = parseDateString(dateStr)
  if (!parsed) return null
  return new Date(Date.UTC(parsed.year, parsed.month - 1, parsed.day))
}

export function formatDate(date: Date) {
  const y = date.getUTCFullYear()
  const m = String(date.getUTCMonth() + 1).padStart(2, "0")
  const d = String(date.getUTCDate()).padStart(2, "0")
  return `${y}-${m}-${d}`
}

export function monthRange(year: number, month: number) {
  const start = new Date(Date.UTC(year, month - 1, 1))
  const end = new Date(Date.UTC(year, month - 1, daysInMonth(year, month)))
  return { start, end }
}

export function weekRange(dateStr: string) {
  const date = dateToUtc(dateStr)
  if (!date) return null
  const day = date.getUTCDay() // 0 (Sun) - 6 (Sat)
  const diffToMonday = day === 0 ? -6 : 1 - day
  const start = new Date(date)
  start.setUTCDate(start.getUTCDate() + diffToMonday)
  const end = new Date(start)
  end.setUTCDate(start.getUTCDate() + 6)
  return { start, end }
}

export function dateRange(start: Date, end: Date) {
  const dates: string[] = []
  const cursor = new Date(start)
  while (cursor <= end) {
    dates.push(formatDate(cursor))
    cursor.setUTCDate(cursor.getUTCDate() + 1)
  }
  return dates
}

export function prevYearMonth(year: number, month: number) {
  const date = new Date(Date.UTC(year, month - 1, 1))
  date.setUTCMonth(date.getUTCMonth() - 1)
  const y = date.getUTCFullYear()
  const m = String(date.getUTCMonth() + 1).padStart(2, "0")
  return `${y}-${m}`
}

export function requireFields(body: Record<string, unknown>, fields: string[]) {
  const missing = fields.filter((field) => body[field] === undefined || body[field] === null)
  if (missing.length > 0) {
    return `Missing fields: ${missing.join(", ")}`
  }
  return null
}
