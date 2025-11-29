#!/bin/bash

# =================== UI Colors ===================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
PURPLE='\033[1;35m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
RESET='\033[0m'
BOLD='\033[1m'

clear
printf "\n${RED}${BOLD}🚀 ALPHA${YELLOW}0x1 ${BLUE}REPAIR EDITION ${PURPLE}(${CYAN}Fixed${PURPLE})${RESET}\n"
printf "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"

# =================== 1. Setup ===================
if [[ -f .env ]]; then source ./.env; fi

if [[ -z "${TELEGRAM_TOKEN:-}" ]]; then 
  read -p "💎 Bot Token: " TELEGRAM_TOKEN
fi

if [[ -z "${TELEGRAM_CHAT_IDS:-}" ]]; then 
  read -p "💎 Chat ID:   " TELEGRAM_CHAT_IDS
fi

# =================== 2. Config ===================
SERVER_NAME="Alpha0x1-$(date +%s | tail -c 4)"
GEN_UUID=$(cat /proc/sys/kernel/random/uuid)
SERVICE_NAME="alpha0x1"
REGION="us-central1"
IMAGE="a0x1/al0x1"
GRPC_SERVICE_NAME="Tg-@Alpha0x1"

# =================== 3. Cleanup & Deploy ===================
echo ""
echo -e "${YELLOW}➤ Cleaning & Preparing...${RESET}"

# Auto-Cleanup
EXISTING=$(gcloud run services list --platform managed --region $REGION --format="value(SERVICE)")
if [[ -n "$EXISTING" ]]; then
  for svc in $EXISTING; do
    gcloud run services delete "$svc" --platform managed --region $REGION --quiet >/dev/null 2>&1
  done
fi

echo -e "${YELLOW}➤ Deploying Stable Node...${RESET}"

# Deploy Command (FIXED STABILITY)
# 🔥 Removed risky env vars (KEEPALIVE/GODEBUG) causing crash
# 🔥 Kept High Specs (4 CPU / 4 GB)
gcloud run deploy "$SERVICE_NAME" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="4Gi" \
  --cpu="4" \
  --timeout="3600" \
  --no-allow-unauthenticated \
  --use-http2 \
  --no-cpu-throttling \
  --execution-environment=gen2 \
  --concurrency=1000 \
  --session-affinity \
  --set-env-vars UUID="${GEN_UUID}",GOMAXPROCS="4",GOMEMLIMIT="3600MiB",TZ="Asia/Yangon" \
  --port="8080" \
  --min-instances=1 \
  --max-instances=2 \
  --quiet

# Force Public Access (Bypass)
echo -e "${YELLOW}➤ Unlocking Access...${RESET}"
gcloud run services add-iam-policy-binding "$SERVICE_NAME" \
  --region="$REGION" \
  --member="allUsers" \
  --role="roles/run.invoker" \
  --quiet >/dev/null 2>&1

# Traffic Optimization
echo -e "${YELLOW}➤ Finalizing Network...${RESET}"
gcloud run services update-traffic "$SERVICE_NAME" --to-latest --region="$REGION" --quiet >/dev/null 2>&1

# Get URL
URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN=${URL#https://}

# Warm up (Wait 5s for propagation)
sleep 5
curl -s -o /dev/null "https://${DOMAIN}"

# =================== 4. Notification ===================
echo -e "${YELLOW}➤ Sending Best Key...${RESET}"

# 🔥 SINGLE BEST ROUTE: vpn.googleapis.com
URI="vless://${GEN_UUID}@vpn.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=${GRPC_SERVICE_NAME}&sni=${DOMAIN}#${SERVER_NAME}"

export TZ="Asia/Yangon"
START_LOCAL="$(date +'%d.%m.%Y %I:%M %p')"
END_LOCAL="$(date -d '+5 hours 10 minutes' +'%d.%m.%Y %I:%M %p')"

MSG="<blockquote>🚀 ${SERVER_NAME} V2RAY SERVICE</blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>📡Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
<pre><code>${URI}</code></pre>

<blockquote>✅ စတင်ချိန်: <code>${START_LOCAL}</code></blockquote>
<blockquote>⏳ပြီးဆုံးအချိန်: <code>${END_LOCAL}</code></blockquote>"

if [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_CHAT_IDS" ]]; then
  IFS=',' read -r -a CHAT_ID_ARR <<< "${TELEGRAM_CHAT_IDS}"
  for chat_id in "${CHAT_ID_ARR[@]}"; do
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d "chat_id=${chat_id}" \
      -d "parse_mode=HTML" \
      --data-urlencode "text=${MSG}" > /dev/null
    echo -e "${GREEN}✔ Sent to ID: ${chat_id}${RESET}"
  done
else
  echo "No Token found."
fi

# =================== Final Report ===================
echo ""
echo -e "${YELLOW}╔════════════════════════════════════════════╗${RESET}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Name" "${SERVER_NAME}"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Route" "vpn.googleapis.com"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${WHITE}%-20s${RESET} ${YELLOW}║${RESET}\n" "Specs" "4 vCPU / 4Gi RAM"
printf "${YELLOW}║${RESET} ${CYAN}%-18s${RESET} : ${GREEN}%-20s${RESET} ${YELLOW}║${RESET}\n" "Status" "Active ✅"
echo -e "${YELLOW}╚════════════════════════════════════════════╝${RESET}"
echo ""
