#!/usr/bin/env bash
set -euo pipefail

# ===== Ensure interactive reads even when run via curl/process substitution =====
if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging & error handler =====
LOG_FILE="/tmp/ksgcp_cloudrun_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  local rc=$?
  echo "" | tee -a "$LOG_FILE"
  echo "❌ ERROR: Command failed (exit $rc) at line $LINENO: ${BASH_COMMAND}" | tee -a "$LOG_FILE" >&2
  echo "—— LOG (last 80 lines) ——" >&2
  tail -n 80 "$LOG_FILE" >&2 || true
  echo "📄 Log File: $LOG_FILE" >&2
  exit $rc
}
trap on_err ERR

# =================== Color & UI (KSGCP Theme) ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'
  C_PURPLE=$'\e[38;5;99m'  # For banners
  C_GOLD=$'\e[38;5;214m'   # For title and highlights
  C_GREEN=$'\e[38;5;46m'  # OK
  C_ORG=$'\e[38;5;208m'   # Warn
  C_GREY=$'\e[38;5;245m'  # Dim
  C_RED=$'\e[38;5;196m'   # Error
else
  RESET= BOLD= DIM= C_PURPLE= C_GOLD= C_GREEN= C_ORG= C_GREY= C_RED=
fi

hr(){ printf "${C_GOLD}%s${RESET}\n" "══════════════════════════════════════════════════"; }
banner(){
  local title="$1"
  printf "\n${C_PURPLE}${BOLD}╔══════════════════════════════════════════════════╗${RESET}\n"
  printf   "${C_PURPLE}${BOLD}║${RESET}  %s${RESET}\n" "$(printf "%-46s" "$title")"
  printf   "${C_PURPLE}${BOLD}╚══════════════════════════════════════════════════╝${RESET}\n"
}
ok(){   printf "${C_GREEN}✔${RESET} %s\n" "$1"; }
warn(){ printf "${C_ORG}⚠${RESET} %s\n" "$1"; }
err(){  printf "${C_RED}✘${RESET} %s\n" "$1"; }
kv(){   printf "   ${C_GREY}%s${RESET}  %s\n" "$1" "$2"; }

printf "\n${C_GOLD}${BOLD}🚀 KSGCP Cloud Run — V2Ray Deploy (Hybrid Script)${RESET}\n"
hr

# =================== Spinner UI ===================
run_with_progress() {
  local label="$1"; shift
  ( "$@" ) >>"$LOG_FILE" 2>&1 &
  local pid=$!
  local spinner=('|' '/' '-' '\')
  local i=0
  if [[ -t 1 ]]; then
    printf "\e[?25l" # Hide cursor
    while kill -0 "$pid" 2>/dev/null; do
      printf "\r🌀 %s... %s" "$label" "${spinner[i]}"
      i=$(( (i+1) % 4 ))
      sleep 0.1 # Spinner speed
    done
    wait "$pid"; local rc=$?
    printf "\r" # Clear the spinner line
    if (( rc==0 )); then
      printf "✅ %s... Done\n" "$label"
    else
      printf "❌ %s failed (see %s)\n" "$label" "$LOG_FILE"
      return $rc
    fi
    printf "\e[?25h" # Show cursor
  else
    wait "$pid"
  fi
}

# =================== GLOBAL VARS (From Script 1) ===================
PROTOCOL=""
UUID=""
TROJAN_PASSWORD=""
VLESS_PATH="/ksgcp"
TROJAN_PATH="/ksgcp"
VLESS_GRPC_SERVICE_NAME="ksgcp"
HOST_DOMAIN="m.googleapis.com"

# =================== Step 1: Telegram Config (From Script 2) ===================
banner "🚀 Step 1 — Telegram Setup"
TELEGRAM_TOKEN="${TELEGRAM_TOKEN:-}"
TELEGRAM_CHAT_IDS="${TELEGRAM_CHAT_IDS:-${TELEGRAM_CHAT_ID:-}}"

if [[ ( -z "${TELEGRAM_TOKEN}" || -z "${TELEGRAM_CHAT_IDS}" ) && -f .env ]]; then
  warn "Reading .env file..."
  set -a; source ./.env; set +a
  ok ".env file loaded."
fi

if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then
  read -rp "🤖 Telegram Bot Token: " _tk || true
  TELEGRAM_TOKEN="${_tk:-}"
fi
if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then
  warn "Telegram token empty; deploy will continue without messages."
else
  ok "Telegram token captured."
fi

if [[ -z "${TELEGRAM_CHAT_IDS:-}" ]]; then
  read -rp "👤 Owner/Channel Chat ID(s) (comma separated): " _ids || true
  TELEGRAM_CHAT_IDS="${_ids// /}"
fi
if [[ -n "${TELEGRAM_CHAT_IDS:-}" ]]; then
  ok "Telegram Chat ID(s) captured."
fi

DEFAULT_LABEL="Join KSGCP Channel"
DEFAULT_URL="https://t.me/ksgcp_channel" # <-- Placeholder URL
BTN_LABELS=(); BTN_URLS=()

read -rp "➕ Add URL button(s)? [y/N]: " _addbtn || true
if [[ "${_addbtn:-}" =~ ^([yY]|yes)$ ]]; then
  i=0
  while true; do
    echo "—— Button $((i+1)) ——"
    read -rp "🔖 Label [default: ${DEFAULT_LABEL}]: " _lbl || true
    if [[ -z "${_lbl:-}" ]]; then
      BTN_LABELS+=("${DEFAULT_LABEL}")
      BTN_URLS+=("${DEFAULT_URL}")
      ok "Added: ${DEFAULT_LABEL} → ${DEFAULT_URL}"
    else
      read -rp "🔗 URL (http/https): " _url || true
      if [[ -n "${_url:-}" && "${_url}" =~ ^https?:// ]]; then
        BTN_LABELS+=("${_lbl}")
        BTN_URLS+=("${_url}")
        ok "Added: ${_lbl} → ${_url}"
      else
        warn "Skipped (invalid or empty URL)."
      fi
    fi
    i=$(( i + 1 ))
    (( i >= 3 )) && break
    read -rp "➕ Add another button? [y/N]: " _more || true
    [[ "${_more:-}" =~ ^([yY]|yes)$ ]] || break
  done
fi

CHAT_ID_ARR=()
IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS:-}" || true

json_escape(){ printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

tg_send(){
  local text="$1" RM=""
  if [[ -z "${TELEGRAM_TOKEN:-}" || ${#CHAT_ID_ARR[@]} -eq 0 ]]; then return 0; fi
  if (( ${#BTN_LABELS[@]} > 0 )); then
    local L1 U1 L2 U2 L3 U3
    [[ -n "${BTN_LABELS[0]:-}" ]] && L1="$(json_escape "${BTN_LABELS[0]}")" && U1="$(json_escape "${BTN_URLS[0]}")"
    [[ -n "${BTN_LABELS[1]:-}" ]] && L2="$(json_escape "${BTN_LABELS[1]}")" && U2="$(json_escape "${BTN_URLS[1]}")"
    [[ -n "${BTN_LABELS[2]:-}" ]] && L3="$(json_escape "${BTN_LABELS[2]}")" && U3="$(json_escape "${BTN_URLS[2]}")"
    if (( ${#BTN_LABELS[@]} == 1 )); then
      RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}]]}"
    elif (( ${#BTN_LABELS[@]} == 2 )); then
      RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}],[{\"text\":\"${L2}\",\"url\":\"${U2}\"}]]}"
    else
      RM="{\"inline_keyboard\":[[{\"text\":\"${L1}\",\"url\":\"${U1}\"}],[{\"text\":\"${L2}\",\"url\":\"${U2}\"},{\"text\":\"${L3}\",\"url\":\"${U3}\"}]]}"
    fi
  fi
  for _cid in "${CHAT_ID_ARR[@]}"; do
    if [[ -z "${_cid}" ]]; then continue; fi
    local response
    response=$(curl -s -S -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${_cid}" \
      --data-urlencode "text=${text}" \
      -d "parse_mode=HTML" \
      ${RM:+--data-urlencode "reply_markup=${RM}"} 2>&1)
    if echo "$response" | grep -q '"ok":true'; then
      ok "Telegram sent → ${_cid}"
    else
      warn "Telegram failed → ${_cid} (Response: ${response})"
    fi
    echo "TG_SEND: ${response}" >>"$LOG_FILE"
  done
}

# =================== Step 2: Project (From Script 2) ===================
banner "🧭 Step 2 — GCP Project"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [[ -z "$PROJECT" ]]; then
  err "No active project. Run: gcloud config set project <YOUR_PROJECT_ID>"
  exit 1
fi
ok "Project Loaded: ${PROJECT}"

# =================== Step 3: Protocol (Combined) ===================
banner "🧩 Step 3 — Select Protocol"
echo "  1️⃣ VLESS WS"
echo "  2️⃣ VLESS gRPC"
echo "  3️⃣ Trojan WS"
read -rp "Choose [1-3, default 1]: " _opt || true
case "${_opt:-1}" in
  2) PROTO="VLESS-gRPC" ;;
  3) PROTO="Trojan-WS"  ;;
  *) PROTO="VLESS-WS"   ;;
esac
ok "Protocol selected: ${PROTO^^}"

# =================== Step 4: Auto-Generate Credentials (From Script 1) ===================
banner "🔑 Step 4 — Auto-Generating Credentials"
if [[ "$PROTO" == "Trojan-WS" ]]; then
    if command -v openssl &> /dev/null; then
        TROJAN_PASSWORD=$(openssl rand -hex 8)
    else
        TROJAN_PASSWORD=$(cat /proc/sys/kernel/random/uuid | cut -c -16)
    fi
    ok "Generated Trojan Password"
else
    if command -v uuidgen &> /dev/null; then
        UUID=$(uuidgen)
    else
        UUID=$(cat /proc/sys/kernel/random/uuid)
    fi
    ok "Generated VLESS UUID"
fi

# =================== Step 5: Region & Resources (Hardcoded) ===================
banner "🧮 Step 5 — Resources (Auto-Set)"
REGION="us-central1"
CPU="2"
MEMORY="2Gi"
SERVICE="ksgcp"
PORT="8080"
TIMEOUT="3600"
ok "Region: ${REGION}"
ok "CPU/Mem: ${CPU} vCPU / ${MEMORY}"
ok "Service: ${SERVICE}"

# =================== Step 6: Timezone Setup (From Script 2) ===================
export TZ="Asia/Yangon"
START_EPOCH="$(date +%s)"
END_EPOCH="$(( START_EPOCH + 5*3600 ))"
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"
banner "🕒 Step 6 — Deployment Time"
kv "Start:" "${START_LOCAL}"
kv "End:"   "${END_LOCAL}"

# =========================================================================
# ===== SCRIPT FIX (Robust config modification function) =====
# =========================================================================
_modify_config() {
  # Step A: Inject Credentials (UUID/Password)
  if [[ "$PROTO" == "Trojan-WS" ]]; then
      # Change protocol to trojan
      sed -i 's/"protocol": "vless"/"protocol": "trojan"/' config.json
      # Replace VLESS clients block with Trojan users block
      # This robustly finds the multi-line block
      sed -i '/"clients": \[/,/]/c \
"users": [\
  { "password": "'"$TROJAN_PASSWORD"'" }\
]' config.json
  else
      # Just replace the placeholder UUID for VLESS
      sed -i "s/PLACEHOLDER_UUID/$UUID/g" config.json
  fi

  # Step B: Configure Stream Settings (Path/Network)
  if [[ "$PROTO" == "VLESS-WS" ]]; then
      # Update path
      sed -i "s|/vless|$VLESS_PATH|g" config.json
  
  elif [[ "$PROTO" == "Trojan-WS" ]]; then
      # Update path
      sed -i "s|/vless|$TROJAN_PATH|g" config.json
  
  elif [[ "$PROTO" == "VLESS-gRPC" ]]; then
      # 1. Change network type from ws to grpc
      sed -i 's/"network": "ws"/"network": "grpc"/' config.json
      
      # 2. Robustly replace the entire wsSettings block with the grpcSettings block
      # This multi-line sed command finds the block from "wsSettings" to "}" and replaces it
      sed -i '/"wsSettings": {/,/}/c \
"grpcSettings": {\
  "serviceName": "'"$VLESS_GRPC_SERVICE_NAME"'"\
}' config.json
  fi
}
# =========================================================================
# ===== END OF FIX =====
# =========================================================================

# =================== Step 7: Prepare Config (From Script 1) ===================
banner "✍️ Step 7 — Prepare Config Files"
if [[ ! -f "config.json" || ! -f "Dockerfile" ]]; then
  err "Missing 'config.json' or 'Dockerfile' in this directory."
  err "Please create them first before running this script."
  exit 1
fi
ok "Found config.json and Dockerfile."

# Call the robust modify function inside the progress spinner
run_with_progress "Modifying config.json" _modify_config

# =================== Step 8: Enable APIs (From Script 2) ===================
banner "⚙️ Step 8 — Enable APIs"
run_with_progress "Enabling CloudRun & Build APIs" \
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com --quiet

# =================== Step 9: Deploy (From Script 1) ===================
banner "🚀 Step 9 — Deploying to Cloud Run"
run_with_progress "Deploying ${SERVICE} (Building from source)" \
  gcloud run deploy "$SERVICE" \
    --source . \
    --platform=managed \
    --region="$REGION" \
    --memory="$MEMORY" \
    --cpu="$CPU" \
    --timeout="$TIMEOUT" \
    --allow-unauthenticated \
    --port="$PORT" \
    --min-instances=1 \
    --quiet

# =================== Step 10: Result (Combined) ===================
URL_CANONICAL_RAW="$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)')"
CANONICAL_HOST="${URL_CANONICAL_RAW#https://}"
banner "✅ Result"
ok "Service Ready"
kv "URL:" "${C_GOLD}${BOLD}${URL_CANONICAL_RAW}${RESET}"

# =================== Step 11: Protocol URLs (Combined) ===================
declare uuid_or_pass
if [[ "$PROTO" == "Trojan-WS" ]]; then
    uuid_or_pass="$TROJAN_PASSWORD"
else
    uuid_or_pass="$UUID"
fi

declare PATH_ENCODED
if [[ "$PROTO" == "VLESS-gRPC" ]]; then
    PATH_ENCODED=$(echo "$VLESS_GRPC_SERVICE_NAME" | sed 's/\//%2F/g')
else
    PATH_ENCODED=$(echo "${VLESS_PATH:-$TROJAN_PATH}" | sed 's/\//%2F/g')
fi

declare URI
case "$PROTO" in
  Trojan-WS)  URI="trojan://${uuid_or_pass}@${HOST_DOMAIN}:443?path=${PATH_ENCODED}&security=tls&host=${CANONICAL_HOST}&type=ws&sni=${CANONICAL_HOST}#KSGCP-Trojan" ;;
  VLESS-WS)   URI="vless://${uuid_or_pass}@${HOST_DOMAIN}:443?path=${PATH_ENCODED}&security=tls&encryption=none&host=${CANONICAL_HOST}&type=ws&sni=${CANONICAL_HOST}#KSGCP-Vless" ;;
  VLESS-gRPC) URI="vless://${uuid_or_pass}@${HOST_DOMAIN}:443?security=tls&encryption=none&host=${CANONICAL_HOST}&type=grpc&serviceName=${PATH_ENCODED}&sni=${CANONICAL_HOST}#KSGCP-gRPC" ;;
esac

# =================== Step 12: Telegram Notify (From Script 2) ===================
banner "📣 Step 12 — Telegram Notify"
MSG=$(cat <<EOF
<blockquote>🚀 KSGCP V2RAY KEY</blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>📡Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
<pre><code>${URI}</code></pre>

<blockquote>⏳ End: <code>${END_LOCAL}</code></blockquote>
EOF
)

tg_send "${MSG}"

printf "\n${C_GOLD}${BOLD}✨ Done — Min Instances = 1 (Cold Start Prevented) | KSGCP Hybrid UI${RESET}\n"
printf "${C_GREY}📄 Log file: ${LOG_FILE}${RESET}\n"
