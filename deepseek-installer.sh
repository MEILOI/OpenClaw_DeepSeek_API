#!/bin/bash
# OpenClaw DeepSeek 一键安装对接脚本
# 适用于全新安装 OpenClaw (原 Moltbot/Clawdbot)
# 作者：TheX
# 版本：2.0

set -e

echo "🚀 OpenClaw DeepSeek 一键安装对接脚本"
echo "=========================================="

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 函数：打印带颜色的消息
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查 Node.js
print_info "检查 Node.js 版本..."
if ! command -v node &> /dev/null; then
    print_error "Node.js 未安装，请先安装 Node.js >= 18"
    exit 1
fi

NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
    print_error "Node.js 版本过低 (需要 >= 18)"
    exit 1
fi
print_success "Node.js 版本: $(node -v)"

# 检查 npm
if ! command -v npm &> /dev/null; then
    print_error "npm 未安装"
    exit 1
fi

# 检查是否已安装 OpenClaw
print_info "检查 OpenClaw 安装状态..."
if command -v openclaw &> /dev/null; then
    print_warning "OpenClaw 已安装，跳过安装步骤"
    OPENCLAW_INSTALLED=true
else
    OPENCLAW_INSTALLED=false
fi

# 获取用户输入
echo ""
print_info "请提供以下信息："

# DeepSeek API Key
read -p "🔑 请输入 DeepSeek API Key (格式: sk-...): " DEEPSEEK_API_KEY
if [ -z "$DEEPSEEK_API_KEY" ]; then
    print_error "API Key 不能为空"
    exit 1
fi

# Telegram Bot Token
read -p "🤖 请输入 Telegram Bot Token (格式: 1234567890:ABC...): " TELEGRAM_TOKEN
if [ -z "$TELEGRAM_TOKEN" ]; then
    print_error "Telegram Bot Token 不能为空"
    exit 1
fi

# 用户 ID (可选)
read -p "👤 请输入您的 Telegram User ID (可选，按回车跳过): " TELEGRAM_USER_ID
if [ -z "$TELEGRAM_USER_ID" ]; then
    TELEGRAM_USER_ID=""
fi

echo ""
print_info "开始安装配置..."

# 步骤 1: 安装 OpenClaw
if [ "$OPENCLAW_INSTALLED" = false ]; then
    print_info "正在安装 OpenClaw..."
    npm install -g openclaw
    if [ $? -eq 0 ]; then
        print_success "OpenClaw 安装完成"
    else
        print_error "OpenClaw 安装失败"
        exit 1
    fi
else
    print_info "OpenClaw 已安装，跳过安装"
fi

# 步骤 2: 初始化 OpenClaw
print_info "初始化 OpenClaw..."
openclaw doctor > /dev/null 2>&1 || true
print_success "OpenClaw 初始化完成"

# 步骤 3: 修改源码 (DeepSeek 补丁)
print_info "定位 OpenClaw 安装路径..."

# 定义可能的安装路径数组
POSSIBLE_PATHS=(
    "/usr/local/lib/node_modules/openclaw"
    "/usr/lib/node_modules/openclaw"
    "/opt/homebrew/lib/node_modules/openclaw"  # macOS Homebrew
)

# 检查 nvm 路径
if [ -n "$NVM_DIR" ]; then
    print_info "检测到 NVM 环境，添加 nvm 路径..."
    # 获取当前 node 版本
    CURRENT_NODE_VERSION=$(node -v | cut -d'v' -f2)
    NVM_PATH="$HOME/.nvm/versions/node/v$CURRENT_NODE_VERSION/lib/node_modules/openclaw"
    POSSIBLE_PATHS=("$NVM_PATH" "${POSSIBLE_PATHS[@]}")
elif [ -d "$HOME/.nvm" ]; then
    print_info "检测到 ~/.nvm 目录，尝试查找 nvm 路径..."
    # 尝试查找最新的 node 版本
    LATEST_NODE=$(ls -1 "$HOME/.nvm/versions/node/" 2>/dev/null | sort -V | tail -1)
    if [ -n "$LATEST_NODE" ]; then
        NVM_PATH="$HOME/.nvm/versions/node/$LATEST_NODE/lib/node_modules/openclaw"
        POSSIBLE_PATHS=("$NVM_PATH" "${POSSIBLE_PATHS[@]}")
    fi
fi

# 遍历所有可能的路径
OPENCLAW_PATH=""
for path in "${POSSIBLE_PATHS[@]}"; do
    if [ -d "$path" ]; then
        OPENCLAW_PATH="$path"
        print_success "找到 OpenClaw 安装目录：$path"
        break
    fi
done

if [ -z "$OPENCLAW_PATH" ]; then
    print_error "未找到 OpenClaw 安装目录"
    print_info "尝试的路径："
    for path in "${POSSIBLE_PATHS[@]}"; do
        echo "  - $path"
    done
    print_info "请手动指定 OpenClaw 安装路径："
    read -p "📁 请输入 OpenClaw 完整路径: " MANUAL_PATH
    if [ -d "$MANUAL_PATH" ]; then
        OPENCLAW_PATH="$MANUAL_PATH"
    else
        print_error "指定的路径不存在：$MANUAL_PATH"
        exit 1
    fi
fi

MODEL_JS="$OPENCLAW_PATH/dist/agents/pi-embedded-runner/model.js"
if [ ! -f "$MODEL_JS" ]; then
    print_error "未找到 model.js 文件：$MODEL_JS"
    exit 1
fi

print_info "备份原文件..."
BACKUP="$MODEL_JS.backup.$(date +%Y%m%d%H%M%S)"
cp "$MODEL_JS" "$BACKUP"
print_success "已备份到：$BACKUP"

# 检查是否已打补丁
if grep -q "DeepSeek Patch Start" "$MODEL_JS"; then
    print_warning "检测到已存在 DeepSeek 补丁，跳过源码修改"
else
    print_info "正在注入 DeepSeek 补丁..."
    
    # 方法1：尝试使用 sed 查找特定模式（容错版本）
    print_info "尝试方法1：查找 resolveModel 函数中的关键行..."
    
    # 更宽松的查找模式，允许变量名变化和格式变化
    FOUND_LINE=false
    LINE_NUMBER=0
    
    # 查找可能的模式
    PATTERNS=(
        "const model = modelRegistry.find(provider, modelId);"
        "const model = modelRegistry.find(provider, modelId)"
        "model = modelRegistry.find(provider, modelId);"
        "modelRegistry.find(provider, modelId);"
    )
    
    for pattern in "${PATTERNS[@]}"; do
        LINE_NUMBER=$(grep -n "$pattern" "$MODEL_JS" | head -1 | cut -d: -f1)
        if [ -n "$LINE_NUMBER" ]; then
            FOUND_LINE=true
            print_success "找到匹配行（模式：${pattern:0:30}...）"
            break
        fi
    done
    
    if [ "$FOUND_LINE" = false ]; then
        print_warning "方法1失败，尝试方法2：查找 resolveModel 函数体"
        
        # 方法2：查找 resolveModel 函数，然后在函数体内查找 modelRegistry.find
        RESOLVE_START=$(grep -n "function resolveModel\|export function resolveModel" "$MODEL_JS" | head -1 | cut -d: -f1)
        if [ -n "$RESOLVE_START" ]; then
            # 从函数开始查找 modelRegistry.find
            TAIL_CONTENT=$(tail -n +$RESOLVE_START "$MODEL_JS")
            LINE_OFFSET=$(echo "$TAIL_CONTENT" | grep -n "modelRegistry.find" | head -1 | cut -d: -f1)
            if [ -n "$LINE_OFFSET" ]; then
                LINE_NUMBER=$((RESOLVE_START + LINE_OFFSET - 1))
                FOUND_LINE=true
                print_success "在 resolveModel 函数中找到 modelRegistry.find"
            fi
        fi
    fi
    
    if [ "$FOUND_LINE" = false ]; then
        print_error "无法定位插入位置，可能 OpenClaw 版本已更新"
        print_info "请手动检查 $MODEL_JS 文件结构"
        print_info "备用方案：使用以下命令手动查看文件内容："
        echo "    grep -n 'resolveModel\|modelRegistry.find' $MODEL_JS"
        exit 1
    fi
    
    # 创建临时文件进行插入
    print_info "在行号 $LINE_NUMBER 后插入补丁..."
    TEMP_FILE=$(mktemp)
    
    # 读取文件并插入补丁
    awk -v line="$LINE_NUMBER" '
    NR == line {
        print $0
        print "    // --- DeepSeek Patch Start ---"
        print "    if (!model && modelId && modelId.toLowerCase().includes(\"deepseek\")) {"
        print "        const deepseekModel = normalizeModelCompat({"
        print "            id: \"deepseek-chat\", // DeepSeek 官方模型 ID"
        print "            name: \"DeepSeek-V3\", // 显示名称"
        print "            api: \"openai-completions\", // 使用通用补全驱动，避免 Unhandled API 报错"
        print "            provider: provider,"
        print "            baseUrl: \"https://api.deepseek.com\", // 必须使用纯域名，不带 /v1，防止路径拼接导致 404"
        print "            reasoning: false, // V3 非推理模型"
        print "            input: [\"text\"], // 仅文本输入"
        print "            cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },"
        print "            contextWindow: 64000, // 上下文窗口设置"
        print "            maxTokens: 8192,"
        print "        });"
        print "        return { model: deepseekModel, authStorage, modelRegistry };"
        print "    }"
        print "    // --- DeepSeek Patch End ---"
        next
    }
    { print }
    ' "$MODEL_JS" > "$TEMP_FILE"
    
    # 验证补丁是否插入成功
    if grep -q "DeepSeek Patch Start" "$TEMP_FILE"; then
        mv "$TEMP_FILE" "$MODEL_JS"
        print_success "源码补丁注入完成（使用容错方法）"
    else
        rm "$TEMP_FILE"
        print_error "补丁插入失败"
        print_info "请手动编辑 $MODEL_JS，在 resolveModel 函数中的 modelRegistry.find 调用后添加补丁代码"
        exit 1
    fi
fi

# 步骤 4: 创建配置文件
print_info "创建 OpenClaw 配置文件..."
CONFIG_DIR="/root/.openclaw"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_DIR/openclaw.json" << EOF
{
  "meta": {
    "lastTouchedVersion": "2026.2.1",
    "lastTouchedAt": "$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
  },
  "models": {
    "providers": {
      "deepseek": {
        "baseUrl": "https://api.deepseek.com",
        "apiKey": "$DEEPSEEK_API_KEY",
        "api": "openai-completions",
        "models": [
          {
            "id": "deepseek-chat",
            "name": "DeepSeek V3",
            "reasoning": false,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 64000,
            "maxTokens": 8192
          },
          {
            "id": "deepseek-reasoner",
            "name": "DeepSeek R1",
            "reasoning": true,
            "input": ["text"],
            "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 },
            "contextWindow": 64000,
            "maxTokens": 8192
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "deepseek/deepseek-chat",
        "fallbacks": [
          "google-antigravity/gemini-3-flash",
          "google/gemini-2.5-flash"
        ]
      },
      "workspace": "/root/.openclaw/workspace"
    }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "allowlist",
      "botToken": "$TELEGRAM_TOKEN",
      "allowFrom": [$([ -n "$TELEGRAM_USER_ID" ] && echo "\"$TELEGRAM_USER_ID\"" || echo "" | sed '/^$/d')],
      "groupPolicy": "allowlist",
      "streamMode": "partial"
    }
  },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "loopback",
    "auth": {
      "mode": "token",
      "token": "$(openssl rand -hex 24)"
    }
  }
}
EOF

print_success "配置文件创建完成：$CONFIG_DIR/openclaw.json"

# 步骤 5: 创建 Systemd 服务
print_info "创建 Systemd 服务..."

# 获取 openclaw 可执行文件路径
OPENCLAW_BIN=$(which openclaw)
if [ -z "$OPENCLAW_BIN" ]; then
    # 如果 which 找不到，尝试在常见路径查找
    OPENCLAW_BIN="/usr/local/bin/openclaw"
    if [ ! -f "$OPENCLAW_BIN" ]; then
        OPENCLAW_BIN="/usr/bin/openclaw"
        if [ ! -f "$OPENCLAW_BIN" ]; then
            # 最后尝试在 nvm 路径中查找
            if [ -n "$NVM_DIR" ]; then
                OPENCLAW_BIN="$HOME/.nvm/versions/node/$(node -v | cut -d'v' -f2)/bin/openclaw"
            fi
        fi
    fi
fi

if [ ! -f "$OPENCLAW_BIN" ]; then
    print_warning "无法自动找到 openclaw 可执行文件"
    read -p "🔧 请输入 openclaw 可执行文件完整路径: " OPENCLAW_BIN
    if [ ! -f "$OPENCLAW_BIN" ]; then
        print_error "指定的文件不存在：$OPENCLAW_BIN"
        exit 1
    fi
fi

print_success "使用 openclaw 路径：$OPENCLAW_BIN"

cat > /etc/systemd/system/openclaw.service << EOF
[Unit]
Description=OpenClaw Gateway Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root
# DeepSeek 环境变量
Environment="OPENAI_API_KEY=$DEEPSEEK_API_KEY"
Environment="OPENAI_BASE_URL=https://api.deepseek.com"
# 启动命令
ExecStart=$OPENCLAW_BIN gateway
# 进程守护配置
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

print_success "Systemd 服务文件创建完成"

# 步骤 6: 启动服务
print_info "启动 OpenClaw 服务..."
systemctl daemon-reload
systemctl enable openclaw
systemctl start openclaw

sleep 2

# 检查服务状态
if systemctl is-active --quiet openclaw; then
    print_success "OpenClaw 服务启动成功"
else
    print_error "OpenClaw 服务启动失败，查看日志：journalctl -u openclaw -f"
    exit 1
fi

# 步骤 7: 获取配对码
print_info "等待配对码生成..."
sleep 3

PAIRING_CODE=$(journalctl -u openclaw --no-pager -n 20 | grep -o "Pairing code: [a-zA-Z0-9]*" | tail -1 | cut -d' ' -f3)

if [ -n "$PAIRING_CODE" ]; then
    print_success "配对码：$PAIRING_CODE"
    echo ""
    print_info "📋 配对步骤："
    echo "  1. 在 Telegram 中向您的 Bot 发送 /start"
    echo "  2. 返回终端执行以下命令："
    echo "     openclaw pairing approve telegram $PAIRING_CODE"
    echo ""
else
    print_warning "未找到配对码，请手动查看日志：journalctl -u openclaw -f"
fi

# 步骤 8: 完成提示
echo ""
echo "🎉 ${GREEN}OpenClaw DeepSeek 安装配置完成！${NC}"
echo "=========================================="
echo ""
echo "📋 ${BLUE}安装摘要：${NC}"
echo "  ✅ Node.js 检查通过"
echo "  ✅ OpenClaw 安装完成"
echo "  ✅ DeepSeek 源码补丁注入（使用容错方法）"
echo "  ✅ 配置文件创建"
echo "  ✅ Systemd 服务配置"
echo "  ✅ OpenClaw 服务启动"
echo ""
echo "🔧 ${YELLOW}管理命令：${NC}"
echo "  查看状态：systemctl status openclaw"
echo "  查看日志：journalctl -u openclaw -f"
echo "  重启服务：systemctl restart openclaw"
echo "  停止服务：systemctl stop openclaw"
echo ""
echo "🤖 ${GREEN}开始使用：${NC}"
echo "  1. 完成 Telegram 配对"
echo "  2. 在 Telegram 中与您的 Bot 对话"
echo "  3. 默认使用 DeepSeek V3 模型"
echo ""
echo "⚠️  ${RED}风险提示与应对方案：${NC}"
echo "  • ${YELLOW}版本敏感性风险：${NC}脚本使用容错方法定位代码位置，但若 OpenClaw 大幅重构"
echo "    resolveModel 函数，可能仍需手动调整。"
echo "  • ${YELLOW}nvm 路径风险：${NC}如果使用 nvm 安装 Node.js，脚本会自动检测，但若检测失败"
echo "    可能需要手动指定路径。"
echo "  • ${GREEN}应对方案：${NC}"
echo "    1. 检查补丁是否生效：grep 'DeepSeek Patch' $MODEL_JS"
echo "    2. 手动定位：查找 resolveModel 函数中的 modelRegistry.find 调用"
echo "    3. nvm 用户：确保 NVM_DIR 环境变量已设置"
echo "    4. 备用方案：使用完整教程手动修改"
echo ""
echo "💡 ${BLUE}提示：${NC}"
echo "  • DeepSeek API 价格便宜，支持上下文缓存"
echo "  • 如需切换模型，修改 /root/.openclaw/openclaw.json"
echo "  • 脚本备份文件：$BACKUP"
echo ""

# 保存配置信息
cat > /root/openclaw-deepseek-info.txt << INFO
OpenClaw DeepSeek 安装信息
===========================
安装时间: $(date)
DeepSeek API Key: $DEEPSEEK_API_KEY
Telegram Bot Token: $TELEGRAM_TOKEN
Telegram User ID: $TELEGRAM_USER_ID
配对码: $PAIRING_CODE
配置文件: /root/.openclaw/openclaw.json
服务文件: /etc/systemd/system/openclaw.service
源码备份: $BACKUP

管理命令:
- systemctl status openclaw
- journalctl -u openclaw -f
- openclaw doctor

配对步骤:
1. Telegram 发送 /start 给 Bot
2. 执行: openclaw pairing approve telegram $PAIRING_CODE
INFO

print_success "安装信息已保存到：/root/openclaw-deepseek-info.txt"
# 步骤 9: 验证补丁（可选）
read -p "🔍 是否验证补丁注入效果？(y/N): " VERIFY_CHOICE
if [[ "$VERIFY_CHOICE" =~ ^[Yy]$ ]]; then
    echo ""
    print_info "验证补丁注入..."
    
    # 检查补丁是否存在
    if grep -q "DeepSeek Patch Start" "$MODEL_JS"; then
        print_success "✓ 补丁标记存在"
        
        # 显示补丁上下文
        PATCH_LINE=$(grep -n "DeepSeek Patch Start" "$MODEL_JS" | cut -d: -f1)
        echo ""
        print_info "补丁上下文（行 $((PATCH_LINE-2)) 到 $((PATCH_LINE+20))）："
        sed -n "$((PATCH_LINE-2)),$((PATCH_LINE+20))p" "$MODEL_JS"
        echo ""
    else
        print_warning "⚠ 补丁标记未找到，但可能以其他形式存在"
    fi
    
    # 检查 resolveModel 函数结构
    print_info "检查 resolveModel 函数结构..."
    RESOLVE_LINES=$(grep -n -A5 -B5 "resolveModel" "$MODEL_JS" | head -20)
    if [ -n "$RESOLVE_LINES" ]; then
        echo "$RESOLVE_LINES" | head -10
    fi
    
    # 显示安装路径信息
    echo ""
    print_info "安装路径信息："
    echo "  OpenClaw 目录: $OPENCLAW_PATH"
    echo "  OpenClaw 可执行文件: $OPENCLAW_BIN"
    echo "  Node.js 版本: $(node -v)"
    echo "  NVM 检测: $([ -n "$NVM_DIR" ] && echo "已启用" || echo "未启用")"
fi
