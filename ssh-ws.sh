#!/usr/bin/env bash
set -euo pipefail

if [[ ! -t 0 ]] && [[ -e /dev/tty ]]; then
  exec </dev/tty
fi

# ===== Logging & error handler =====
LOG_FILE="/tmp/fnet_ssh_$(date +%s).log"
touch "$LOG_FILE"
on_err() {
  local rc=$?
  echo "" | tee -a "$LOG_FILE"
  echo "❌ ERROR: Command failed (exit $rc) at line $LINENO" | tee -a "$LOG_FILE" >&2
  exit $rc
}
trap on_err ERR

# =================== FNET VPN Custom UI ===================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  RESET=$'\e[0m'; BOLD=$'\e[1m'
  C_FNET_RED=$'\e[38;5;196m'; C_FNET_BLUE=$'\e[38;5;39m'; C_FNET_GREEN=$'\e[38;5;46m'     
  C_FNET_YELLOW=$'\e[38;5;226m'; C_FNET_PURPLE=$'\e[38;5;93m'; C_FNET_GRAY=$'\e[38;5;214m'     
  C_FNET_CYAN=$'\e[38;5;51m'      
else
  RESET= BOLD= C_FNET_RED= C_FNET_BLUE= C_FNET_GREEN= C_FNET_YELLOW= C_FNET_PURPLE= C_FNET_GRAY= C_FNET_CYAN=
fi

show_fnet_banner() {
  clear
  printf "\n\n${C_FNET_RED}${BOLD}"
  printf "╔══════════════════════════════════════════════════════════════════╗\n"
  printf "║                                                                  ║\n"
  printf "║   ███████╗███╗   ██╗███████╗████████╗    ██╗   ██╗██████╗ ███╗   ██╗ ║\n"
  printf "║   ██╔════╝████╗  ██║██╔════╝╚══██╔══╝    ██║   ██║██╔══██╗████╗  ██║ ║\n"
  printf "║   █████╗  ██╔██╗ ██║█████╗     ██║       ██║   ██║██████╔╝██╔██╗ ██║ ║\n"
  printf "║   ██╔══╝  ██║╚██╗██║██╔══╝     ██║       ╚██╗ ██╔╝██╔═══╝ ██║╚██╗██║ ║\n"
  printf "║   ██║     ██║ ╚████║███████╗   ██║        ╚████╔╝ ██║     ██║ ╚████║ ║\n"
  printf "║   ╚═╝     ╚═╝  ╚═══╝╚══════╝   ╚═╝         ╚═══╝  ╚═╝     ╚═╝  ╚═══╝ ║\n"
  printf "║                                                                  ║\n"
  printf "║         ${C_FNET_YELLOW}🚀 SSH over WEBSOCKET SYSTEM => VERSION - 1.0          ${C_FNET_RED}║\n"
  printf "║         ${C_FNET_GREEN}⚡ Powered by FNET Developer                           ${C_FNET_RED}║\n"
  printf "╚══════════════════════════════════════════════════════════════════╝${RESET}\n\n"
}

show_step() { printf "\n${C_FNET_PURPLE}${BOLD}┌─── STEP $1 ──────────────────────────────────────────┐${RESET}\n${C_FNET_PURPLE}${BOLD}│${RESET} ${C_FNET_CYAN}$2${RESET}\n${C_FNET_PURPLE}${BOLD}└──────────────────────────────────────────────────────┘${RESET}\n"; }
show_success() { printf "${C_FNET_GREEN}${BOLD}✓${RESET} ${C_FNET_GREEN}%s${RESET}\n" "$1"; }
show_info() { printf "${C_FNET_BLUE}${BOLD}ℹ${RESET} ${C_FNET_BLUE}%s${RESET}\n" "$1"; }
show_warning() { printf "${C_FNET_YELLOW}${BOLD}⚠${RESET} ${C_FNET_YELLOW}%s${RESET}\n" "$1"; }
show_error() { printf "${C_FNET_RED}${BOLD}✗${RESET} ${C_FNET_RED}%s${RESET}\n" "$1"; }
show_divider() { printf "${C_FNET_GRAY}%s${RESET}\n" "──────────────────────────────────────────────────────────"; }
show_kv() { printf "   ${C_FNET_GRAY}%s${RESET}  ${C_FNET_CYAN}%s${RESET}\n" "$1" "$2"; }

run_with_progress() {
  local label="$1"; shift; local temp_file=$(mktemp)
  if [[ -t 1 ]]; then
    printf "\e[?25l"; ("$@" 2>&1 | tee "$temp_file") >>"$LOG_FILE" 2>&1 & local pid=$!; local pct=5
    while kill -0 "$pid" 2>/dev/null; do
      pct=$(( pct + $(( (RANDOM % 9) + 2 )) )); (( pct > 95 )) && pct=95
      printf "\r${C_FNET_PURPLE}⟳${RESET} ${C_FNET_CYAN}%s...${RESET} [${C_FNET_YELLOW}%s%%${RESET}]" "$label" "$pct"
      if grep -i "error\|failed\|denied" "$temp_file" 2>/dev/null | grep -v "grep" | head -1; then break; fi
      sleep 0.5
    done
    wait "$pid" 2>/dev/null || true; local rc=$?
    printf "\r\e[K"
    if (( rc==0 )); then printf "${C_FNET_GREEN}✓${RESET} ${C_FNET_GREEN}%s...${RESET} [${C_FNET_GREEN}100%%${RESET}]\n" "$label"
    else printf "${C_FNET_RED}✗${RESET} ${C_FNET_RED}%s failed!${RESET}\n" "$label"; rm -f "$temp_file"; printf "\e[?25h"; return $rc; fi
    rm -f "$temp_file"; printf "\e[?25h"
  else "$@" >>"$LOG_FILE" 2>&1; fi
}

show_fnet_banner

# =================== Step 1 & 2 & 3 & 4 : Initial Setup ===================
show_step "01" "GCP & Protocol Setup"
PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT" --format='value(projectNumber)')" || true
REGION="us-central1"
SERVICE="fnet-ssh-ws"
show_success "Protocol: ${C_FNET_CYAN}SSH over WebSocket${RESET}"
show_success "Region: ${C_FNET_CYAN}$REGION${RESET}"

# =================== Step 5: Timezone Setup ===================
show_step "02" "Deployment Schedule (Exact Match)"
printf "\n${C_FNET_GRAY}💡 Qwiklabs ပေါ်က ကျန်နေတဲ့ အချိန်ကို ကြည့်ပြီး အောက်မှာ ထည့်ပေးပါ။ (ဥပမာ - 01:21)${RESET}\n"
read -rp "${C_FNET_GREEN}⏳ စခရင်မ်ပေါ်မှာ ပြနေတဲ့ အချိန်ကို ရိုက်ထည့်ပါ (H:M):${RESET} " REMAINING_TIME || true
export TZ="Asia/Bangkok"
START_EPOCH="$(date +%s)"
if [[ -z "$REMAINING_TIME" || ! "$REMAINING_TIME" =~ ^[0-9]+:[0-9]+$ ]]; then
  ADD_SECS=$(( 3 * 3600 ))
else
  HRS=$(echo "$REMAINING_TIME" | cut -d: -f1 | sed 's/^0*//'); MINS=$(echo "$REMAINING_TIME" | cut -d: -f2 | sed 's/^0*//')
  [[ -z "$HRS" ]] && HRS=0; [[ -z "$MINS" ]] && MINS=0
  ADD_SECS=$(( HRS * 3600 + MINS * 60 ))
  show_success "အချိန်အတိအကျ တွက်ချက်ပြီးပါပြီ။ (${HRS} နာရီ ${MINS} မိနစ်)"
fi
END_EPOCH=$(( START_EPOCH + ADD_SECS ))
fmt_dt(){ date -d @"$1" "+%d.%m.%Y %I:%M %p"; }
START_LOCAL="$(fmt_dt "$START_EPOCH")"
END_LOCAL="$(fmt_dt "$END_EPOCH")"
show_kv "Start Time:" "$START_LOCAL (Thai Time)"
show_kv "End Time:" "$END_LOCAL (Thai Time)"

# =================== Step 6: Create SSH Proxy Server ===================
show_step "03" "Building Custom SSH WS Server"

BUILD_DIR=$(mktemp -d)
cd "$BUILD_DIR"

SSH_USER="fnet"
SSH_PASS="fnet"

# Create Python WebSocket to TCP Proxy
cat << 'EOF' > proxy.py
import asyncio
import websockets

async def forward(websocket, path):
    try:
        reader, writer = await asyncio.open_connection('127.0.0.1', 22)
    except Exception as e:
        return

    async def ws_to_tcp():
        try:
            async for message in websocket:
                writer.write(message)
                await writer.drain()
        except Exception: pass
        finally: writer.close()

    async def tcp_to_ws():
        try:
            while True:
                data = await reader.read(4096)
                if not data: break
                await websocket.send(data)
        except Exception: pass
        finally: await websocket.close()

    await asyncio.gather(ws_to_tcp(), tcp_to_ws())

start_server = websockets.serve(forward, "0.0.0.0", 8080)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
EOF

# Create Startup Script
cat << 'EOF' > entrypoint.sh
#!/bin/bash
/usr/sbin/sshd
python3 /app/proxy.py
EOF
chmod +x entrypoint.sh

# Create Dockerfile
cat << EOF > Dockerfile
FROM alpine:latest
WORKDIR /app
RUN apk add --no-cache openssh python3 py3-websockets bash
RUN ssh-keygen -A && \\
    echo "PermitRootLogin yes" >> /etc/ssh/sshd_config && \\
    echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config && \\
    adduser -D -s /bin/bash ${SSH_USER} && \\
    echo "${SSH_USER}:${SSH_PASS}" | chpasswd
COPY proxy.py /app/proxy.py
COPY entrypoint.sh /app/entrypoint.sh
EXPOSE 8080
CMD ["/app/entrypoint.sh"]
EOF

show_success "SSH Proxy Server files generated successfully."

# =================== Step 7: Enable APIs & Deploy ===================
show_step "04" "Cloud Run Deployment"
gcloud services list --enabled --filter="config.name:run.googleapis.com" | grep -q "run.googleapis.com" || gcloud services enable run.googleapis.com --quiet

show_info "Deploying FNET SSH WS Server..."
DEPLOY_CMD=(
  gcloud run deploy "$SERVICE"
  --source="."
  --platform=managed
  --region="$REGION"
  --memory="512Mi"
  --cpu="1"
  --concurrency=1000
  --allow-unauthenticated
  --port=8080
  --min-instances=1
  --quiet
)
run_with_progress "Deploying ${SERVICE} to Cloud Run" "${DEPLOY_CMD[@]}"
rm -rf "$BUILD_DIR"

# =================== Step 8: Result ===================
SERVICE_URL=$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)' 2>/dev/null || true)
if [[ -z "$SERVICE_URL" ]]; then SERVICE_URL="https://${SERVICE}-${PROJECT_NUMBER}.${REGION}.run.app"; fi
HOST_URL=$(basename ${SERVICE_URL#https://})

printf "\n${C_FNET_YELLOW}┌──────────────────────────────────────────────────────┐${RESET}\n"
printf "${C_FNET_YELLOW}│${RESET} ${C_FNET_CYAN}✅ SSH WS Deployment Successful${RESET}                        ${C_FNET_YELLOW}│${RESET}\n"
printf "${C_FNET_YELLOW}└──────────────────────────────────────────────────────┘${RESET}\n\n"

printf "${C_FNET_GREEN}${BOLD}🔑 SSH WS ACCOUNT DETAILS:${RESET}\n"
show_kv "IP / Host:" "vpn.googleapis.com"
show_kv "Port:" "443"
show_kv "Username:" "${SSH_USER}"
show_kv "Password:" "${SSH_PASS}"
show_kv "SNI/Bug Host:" "vpn.googleapis.com"
show_divider

printf "${C_FNET_GREEN}${BOLD}📋 HTTP CUSTOM / INJECTOR PAYLOAD:${RESET}\n"
printf "${C_FNET_CYAN}GET wss://vpn.googleapis.com/ HTTP/1.1[crlf]Host: ${HOST_URL}[crlf]Upgrade: websocket[crlf]Connection: Upgrade[crlf][crlf]${RESET}\n"
show_divider

printf "\n${C_FNET_RED}${BOLD}F N E T${RESET} ${C_FNET_GRAY}|${RESET} ${C_FNET_CYAN}SSH WebSocket Deployment System${RESET} ${C_FNET_GRAY}|${RESET} ${C_FNET_GREEN}v1.0${RESET}\n"
printf "${C_FNET_GRAY}──────────────────────────────────────────────────────────${RESET}\n\n"
