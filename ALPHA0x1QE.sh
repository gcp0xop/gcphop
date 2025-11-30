#!/bin/bash

# =================== Colors ===================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
RESET='\033[0m'
BOLD='\033[1m'

clear
printf "\n${RED}${BOLD}🚀 ALPHA${YELLOW}0x1 ${GREEN}ABSOLUTE FINAL (Qwiklabs Optimized)${RESET}\n"
echo "----------------------------------------"

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

# =================== 3. Step 1: Stealth Deploy ===================
echo ""
echo -e "${YELLOW}➤ Step 1: Deploying Base Node (Stealth Mode)...${RESET}"

# Deploy Small First (To bypass Quota Check)
gcloud run deploy "$SERVICE_NAME" \
  --image="$IMAGE" \
  --platform=managed \
  --region="$REGION" \
  --memory="2Gi" \
  --cpu="2" \
  --timeout="3600" \
  --no-allow-unauthenticated \
  --use-http2 \
  --execution-environment=gen2 \
  --set-env-vars UUID="${GEN_UUID}",TZ="Asia/Yangon" \
  --port="8080" \
  --min-instances=1 \
  --max-instances=2 \
  --quiet

# =================== 4. Step 2: Force Upgrade ===================
echo -e "${YELLOW}➤ Step 2: Forcing Max Performance & Stability...${RESET}"

# Optimized for Qwiklabs (No CPU Boost)
# Added: GODEBUG (DNS), GOGC (RAM), XRAY_BUFFER (Streaming), XRAY_JSON (Log)
gcloud run services update "$SERVICE_NAME" \
  --memory="4Gi" \
  --cpu="4" \
  --no-cpu-throttling \
  --concurrency=300 \
  --startup-probe-tcp=8080 \
  --startup-probe-period=1s \
  --startup-probe-failure-threshold=30 \
  --update-env-vars GOMAXPROCS="4",GOMEMLIMIT="3600MiB",XRAY_TRANSPORT_GRPC_KEEPALIVE="15",GODEBUG="netdns=go",GOGC="50",XRAY_JSON="{\"log\":{\"loglevel\":\"error\"}}",XRAY_BUFFER_SIZE="4" \
  --region="$REGION" \
  --quiet

# =================== 5. Unlock & Optimize ===================
echo -e "${YELLOW}➤ Step 3: Unlocking Access...${RESET}"

# Public Access
gcloud run services add-iam-policy-binding "$SERVICE_NAME" \
  --region="$REGION" \
  --member="allUsers" \
  --role="roles/run.invoker" \
  --quiet >/dev/null 2>&1

# Traffic Force
gcloud run services update-traffic "$SERVICE_NAME" --to-latest --region="$REGION" --quiet >/dev/null 2>&1

# Get URL
URL=$(gcloud run services describe "$SERVICE_NAME" --platform managed --region "$REGION" --format 'value(status.url)')
DOMAIN=${URL#https://}

# Warm up
curl -s -o /dev/null "https://${DOMAIN}"

# =================== 6. Notification ===================
echo -e "${YELLOW}➤ Sending Final Key...${RESET}"

# Optimized URI: alpn=h2 (Fast Handshake), fp=chrome (Anti-Throttle), packetEncoding=xudp (Gaming)
URI="vless://${GEN_UUID}@m.googleapis.com:443?mode=gun&security=tls&encryption=none&type=grpc&serviceName=Tg-@Alpha0x1&sni=${DOMAIN}&alpn=h2&fp=chrome&allowInsecure=1&packetEncoding=xudp#${SERVER_NAME}"

export TZ="Asia/Yangon"
START_LOCAL="$(date +'%d.%m.%Y %I:%M %p')"
END_LOCAL="$(date -d '+5 hours 10 minutes' +'%d.%m.%Y %I:%M %p')"

MSG="<blockquote>🚀 ${SERVER_NAME} V2RAY SERVICE</blockquote>
<blockquote>⏰ 5-Hour Free Service</blockquote>
<blockquote>📡 Mytel 4G လိုင်းဖြတ် ဘယ်နေရာမဆိုသုံးလို့ရပါတယ်</blockquote>
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

echo ""
echo -e "${GREEN}✅ SUCCESS!${RESET}"
