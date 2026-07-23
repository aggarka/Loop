#!/usr/bin/env bash
#
# verify-production.sh
#
# Confirms the Supabase backend the app points at is live and correctly set up,
# before an App Store submission. Reads the URL + publishable key from
# Loop/Supabase-Info.plist (git-ignored), so no secrets live in this script.
#
# Usage:  ./scripts/verify-production.sh
#
set -u

PLIST="Loop/Supabase-Info.plist"
if [ ! -f "$PLIST" ]; then
  echo "ERROR: $PLIST not found. Run this from the repo root."
  exit 1
fi

URL=$(/usr/libexec/PlistBuddy -c "Print :SUPABASE_URL" "$PLIST" 2>/dev/null)
KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPABASE_ANON_KEY" "$PLIST" 2>/dev/null)

if [ -z "$URL" ] || [ -z "$KEY" ]; then
  echo "ERROR: could not read SUPABASE_URL / SUPABASE_ANON_KEY from $PLIST"
  exit 1
fi

echo "App is configured to use:"
echo "  URL: $URL"
case "$URL" in
  *127.0.0.1*|*localhost*)
    echo "  NOTE: this points at a LOCAL stack, not a hosted/production project."
    ;;
esac
echo ""

fail=0
check() { # label  url  [extra curl args...]
  local label="$1"; shift
  local url="$1"; shift
  local code
  code=$(curl -s -o /dev/null -w "%{http_code}" "$url" -H "apikey: $KEY" "$@")
  # Human-readable line to stderr so stdout carries only the status code.
  printf "  %-16s HTTP %s\n" "$label" "$code" >&2
  echo "$code"
}

echo "Backend health:"
auth_code=$(check "auth settings" "$URL/auth/v1/settings")
persons_code=$(check "persons table" "$URL/rest/v1/persons?select=id&limit=1" -H "Authorization: Bearer $KEY")
ai_code=$(check "ai-proxy func" "$URL/functions/v1/ai-proxy" -X POST -H "Content-Type: application/json" -d '{}')

# Interpret results.
[ "$auth_code" = "200" ] || { echo "  -> auth service not reachable (expected 200)"; fail=1; }
case "$persons_code" in
  200|401|403) ;;  # table exists; RLS may reject without a user token
  404) echo "  -> persons table missing (run: supabase db push)"; fail=1 ;;
  *) echo "  -> unexpected persons status"; fail=1 ;;
esac
case "$ai_code" in
  401|400) ;;  # deployed + auth-guarded
  404) echo "  -> ai-proxy not deployed (run: supabase functions deploy ai-proxy)"; fail=1 ;;
  *) echo "  -> unexpected ai-proxy status" ;;
esac

echo ""
echo "Auth providers:"
curl -s "$URL/auth/v1/settings" -H "apikey: $KEY" \
  | python3 -c "import sys,json
try:
    e=json.load(sys.stdin).get('external',{})
    for p in ['apple','google','email']:
        print('  %-8s %s' % (p+':', 'enabled' if e.get(p) else 'DISABLED'))
except Exception:
    print('  (could not parse providers)')"

echo ""
if [ "$fail" = "0" ]; then
  echo "RESULT: backend looks healthy and ready."
else
  echo "RESULT: issues found above — resolve before submitting."
  exit 1
fi
