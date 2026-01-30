import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import {
  createAdminClient,
  error,
  getAuthUser,
  json,
} from "../_shared/utils.ts"

const JELLY_RANGES: Record<string, { min: number; max: number }> = {
  NORMAL: { min: 5, max: 15 },
  BONUS: { min: 5, max: 15 },
  SPECIAL: { min: 90, max: 150 },
}

function randomInt(min: number, max: number) {
  return Math.floor(Math.random() * (max - min + 1)) + min
}

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
    return error(403, "Only children can exchange jelly")
  }

  const jelly = body.jelly
  const amount = body.amount
  if (typeof jelly !== "string" || !(jelly in JELLY_RANGES)) {
    return error(400, "Invalid jelly type")
  }
  if (typeof amount !== "number" || !Number.isInteger(amount) || amount <= 0) {
    return error(400, "amount must be a positive integer")
  }

  const { data: wallet, error: walletError } = await admin
    .from("wallets")
    .select("*")
    .eq("user_id", auth.user.id)
    .maybeSingle()

  if (walletError || !wallet) {
    return error(404, "Wallet not found", walletError?.message)
  }

  const balanceKey = jelly === "NORMAL"
    ? "jelly_normal"
    : jelly === "SPECIAL"
    ? "jelly_special"
    : "jelly_bonus"

  if (wallet[balanceKey] < amount) {
    return error(400, "Not enough jelly", { balance: wallet[balanceKey] })
  }

  const rate = randomInt(JELLY_RANGES[jelly].min, JELLY_RANGES[jelly].max)
  const exchangedCash = rate * amount

  const nextWallet = {
    jelly_normal: wallet.jelly_normal,
    jelly_special: wallet.jelly_special,
    jelly_bonus: wallet.jelly_bonus,
    cash_balance: wallet.cash_balance + exchangedCash,
    updated_at: new Date().toISOString(),
  }
  nextWallet[balanceKey] -= amount

  const { data: updatedWallet, error: updateError } = await admin
    .from("wallets")
    .update(nextWallet)
    .eq("user_id", auth.user.id)
    .select("*")
    .single()

  if (updateError || !updatedWallet) {
    return error(500, "Failed to update wallet", updateError?.message)
  }

  const { data: exchange, error: exchangeError } = await admin
    .from("jelly_exchanges")
    .insert({
      user_id: auth.user.id,
      jelly,
      amount,
      exchanged_cash: exchangedCash,
    })
    .select("*")
    .single()

  if (exchangeError || !exchange) {
    return error(500, "Failed to insert exchange", exchangeError?.message)
  }

  return json({
    exchange,
    wallet: updatedWallet,
    rate,
    exchanged_cash: exchangedCash,
  })
})
