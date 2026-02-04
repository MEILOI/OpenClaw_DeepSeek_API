#!/bin/bash
# OpenClaw 全能模型接入脚本 (DeepSeek / Kimi / Solar)
# 版本：3.4 (终极版：修复会话粘性 + Systemd环境变量 + 备份轮转)

set -e

echo "🚀 OpenClaw 全能接入脚本 (V3.4 终极版)"
echo "=========================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 步骤 0: 环境检查 ---
if ! command -v node &> /dev/null; then print_error "需要 Node.js >= 18"; exit 1; fi
NODE_BIN_DIR=$(dirname $(which node)) # 获取 Node 安装目录，用于 Systemd 修复

# --- 步骤 1: 交互式选择 ---
echo ""
echo "🤖 请选择主力模型："
echo "   1) DeepSeek V3/R1"
echo "   2) Kimi / Moonshot (200k)"
echo "   3) Solar Pro 3 (Free)"
echo ""
read -p "请选择 [1-3]: " MODEL_CHOICE

case $MODEL_CHOICE in
    1)
        TARGET="DeepSeek"; P_MODEL="deepseek/deepseek-chat"
        read -p "🔑 DeepSeek Key (sk-...): " API_KEY
        PROVIDER_BLOCK='"deepseek":{"baseUrl":"https://api.deepseek.com","apiKey":"'"$API_KEY"'","api":"openai-completions","models":[{"id":"deepseek-chat","name":"DeepSeek V3","contextWindow":64000},{"id":"deepseek-reasoner","name":"DeepSeek R1","reasoning":true,"contextWindow":64000}]}'
        ;;
    2)
        TARGET="Kimi"; P_MODEL="openrouter/moonshotai/kimi-k2.5"
        read -p "🔑 OpenRouter Key: " API_KEY
        PROVIDER_BLOCK='"openrouter":{"baseUrl":"https://openrouter.ai/api/v1","apiKey":"'"$API_KEY"'","api":"openai-completions","models":[{"id":"moonshotai/kimi-k2.5","name":"Kimi K2.5","contextWindow":200000}]}'
        ;;
    3)
        TARGET="Solar"; P_MODEL="openrouter/upstage/solar-pro-3:free"
        read -p "🔑 OpenRouter Key: " API_KEY
        PROVIDER_BLOCK='"openrouter":{"baseUrl":"https://openrouter.ai/api/v1","apiKey":"'"$API_KEY"'","api":"openai-completions","models":[{"id":"upstage/solar-pro-3:free","name":"Solar Pro 3","contextWindow":32768}]}'
        ;;
    *) print_error "无效选择"; exit 1 ;;
esac

echo ""
read -p "🤖 TG Bot Token: " TG_TOKEN
read -p "👤 TG User ID (可选): " TG_USER_ID

# --- 步骤 2: 定位路径 ---
print_info "定位 OpenClaw..."
POSSIBLE_PATHS=("/usr/local/lib/node_modules/openclaw" "/usr/lib/node_modules/openclaw" "/opt/homebrew/lib/node_modules/openclaw")
if [ -n "$NVM_DIR" ]; then POSSIBLE_PATHS=("$HOME/.nvm/versions/node/v$(node -v|cut -d'v' -f2)/lib/node_modules/openclaw" "${POSSIBLE_PATHS[@]}"); fi
if [ -d "$HOME/.nvm" ]; then LATEST=$(ls -1 "$HOME/.nvm/versions/node/"|sort -V|tail -1); POSSIBLE_PATHS=("$HOME/.nvm/versions/node/$LATEST/lib/node_modules/openclaw" "${POSSIBLE_PATHS[@]}"); fi

OPENCLAW_PATH=""
for p in "${POSSIBLE_PATHS[@]}"; do if [ -d "$p" ]; then OPENCLAW_PATH="$p"; break; fi; done
if [ -z "$OPENCLAW_PATH" ]; then read -p "未找到路径，请手动输入: " OPENCLAW_PATH; fi

# --- 步骤 3: 注入补丁 (优化版) ---
MODEL_JS="$OPENCLAW_PATH/dist/agents/pi-embedded-runner/model.js"
if ! grep -q "Universal Patch" "$MODEL_JS"; then
    print_info "注入全能补丁..."
    LINE=$(grep -n "modelRegistry.find(provider, modelId);" "$MODEL_JS" | head -1 | cut -d: -f1)
    if [ -z "$LINE" ]; then LINE=$(grep -n "const model =" "$MODEL_JS" | grep "find" | head -1 | cut -d: -f1); fi
    
    if [ -n "$LINE" ]; then
        # 修复：使用时间戳备份，防止覆盖
        cp "$MODEL_JS" "$MODEL_JS.bak.$(date +%Y%m%d%H%M%S)"
        TEMP=$(mktemp)
        awk -v l="$LINE" 'NR==l{print;print "// --- Universal Patch ---";print "if(!model&&modelId){var m=modelId.toLowerCase();if(m.includes(\"deepseek\")||m.includes(\"kimi\")||m.includes(\"moonshot\")||m.includes(\"solar\")||m.includes(\"upstage\")){var cfg={id:modelId,name:modelId,api:\"openai-completions\",provider:provider,baseUrl:m.includes(\"deepseek\")?\"https://api.deepseek.com\":\"https://openrouter.ai/api/v1\",reasoning:false,input:[\"text\"],contextWindow:m.includes(\"kimi\")?200000:64000,maxTokens:8192,cost:{input:0,output:0}};return{model:normalizeModelCompat(cfg),authStorage,modelRegistry};}}";next}1' "$MODEL_JS" > "$TEMP"
        mv "$TEMP" "$MODEL_JS"
        print_success "补丁注入成功"
    else
        print_error "无法定位注入点"
    fi
fi

# --- 步骤 4: 生成配置 ---
mkdir -p /root/.openclaw
cat > /root/.openclaw/openclaw.json <<EOF
{
  "models": { "providers": { $PROVIDER_BLOCK } },
  "agents": { "defaults": { "model": { "primary": "$P_MODEL" }, "workspace": "/root/.openclaw/workspace" } },
  "channels": { "telegram": { "enabled": true, "botToken": "$TG_TOKEN", "allowFrom": [$(if [ -n "$TG_USER_ID" ]; then echo "\"$TG_USER_ID\""; fi)] } },
  "gateway": { "port": 18789, "mode": "local", "auth": { "mode": "token", "token": "$(openssl rand -hex 24)" } }
}
EOF

# --- 步骤 5: 更新服务 (Systemd PATH 修复) ---
BIN=$(which openclaw)
if [ -z "$BIN" ]; then BIN="/usr/local/bin/openclaw"; fi
# 修复：获取 openclaw 所在的 bin 目录，加入 Systemd PATH
BIN_DIR=$(dirname "$BIN")

cat > /etc/systemd/system/openclaw.service <<EOF
[Unit]
Description=OpenClaw Gateway
After=network.target
[Service]
Type=simple
User=root
WorkingDirectory=/root
# 修复：强制指定 PATH，解决 nvm 环境下找不到 node 的问题
Environment="PATH=$BIN_DIR:$NODE_BIN_DIR:/usr/local/bin:/usr/bin:/bin"
Environment="OPENAI_API_KEY=$API_KEY"
ExecStart=$BIN gateway
Restart=always
[Install]
WantedBy=multi-user.target
EOF

# --- 步骤 6: 会话清理 (关键修复) ---
echo ""
print_warning "⚠️  重要提示：是否清除旧的对话记忆？"
echo "如果不清除，OpenClaw 可能会继续使用旧模型 (Session Stickiness)。"
echo "建议选择 YES 以确保新模型立即生效。"
read -p "是否清除？(y/N): " WIPE_SESSION

if [[ "$WIPE_SESSION" =~ ^[Yy]$ ]]; then
    print_info "正在清理旧会话..."
    systemctl stop openclaw
    rm -rf /root/.openclaw/sessions
    rm -rf /root/.openclaw/data/sessions
    print_success "旧记忆已清除！"
fi

# --- 步骤 7: 重启与扫描 ---
print_info "正在重启服务..."
systemctl daemon-reload
systemctl enable openclaw
systemctl restart openclaw

print_info "🔍 扫描配对码 (等待 45秒)..."
PAIRING_CODE=""
for i in {1..22}; do
    LOGS=$(journalctl -u openclaw --no-pager -n 50)
    PAIRING_CODE=$(echo "$LOGS" | grep -o "Pairing code: [a-zA-Z0-9]*" | tail -1 | cut -d' ' -f3)
    if [ -n "$PAIRING_CODE" ]; then echo -ne "\r[OK] 捕获成功! \n"; break; else echo -ne "\rWait [$i/22]..."; sleep 2; fi
done

echo ""
if [ -n "$PAIRING_CODE" ]; then
    echo "=========================================="
    echo "🎉 成功！当前模型: $TARGET"
    echo "📋 配对码: ${GREEN}$PAIRING_CODE${NC}"
    echo "👉 步骤: TG 发送 /start -> 执行: openclaw pairing approve telegram $PAIRING_CODE"
else
    print_error "超时。请手动检查日志: journalctl -u openclaw -n 20 -f"
fi
echo ""
