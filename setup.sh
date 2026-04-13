#!/bin/bash
# 站点信息采集 Skill — 一键安装脚本（交互式）
# 不用 set -e，各步骤自行处理错误

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     站点基础信息采集 Skill — 安装向导     ║"
echo "╚══════════════════════════════════════════╝"
echo ""

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCLAW_DIR="$HOME/.openclaw"
SKILLS_DIR="$OPENCLAW_DIR/workspace/skills/site-info-collector"
SCRIPTS_DIR="$SKILLS_DIR/scripts"

# ═══════════════════════════════════════
# 1. 环境检查
# ═══════════════════════════════════════
echo "━━━ 第 1 步：环境检查 ━━━"
echo ""

# 检查 OpenClaw
if ! command -v openclaw &>/dev/null; then
    echo "❌ 未找到 OpenClaw，请先安装：https://docs.openclaw.ai"
    exit 1
fi
echo "✅ OpenClaw $(openclaw --version 2>/dev/null | head -1)"

# 检查 Python
if ! command -v python3 &>/dev/null; then
    echo "❌ 未找到 Python3，请先安装"
    exit 1
fi
echo "✅ Python $(python3 --version 2>&1)"

# ═══════════════════════════════════════
# 2. 安装依赖
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 2 步：安装 Python 依赖 ━━━"
echo ""

echo "📦 安装 requests, beautifulsoup4, playwright..."
pip3 install --quiet requests beautifulsoup4 playwright 2>/dev/null \
  || pip3 install --break-system-packages --quiet requests beautifulsoup4 playwright 2>/dev/null \
  || pip3 install --break-system-packages requests beautifulsoup4 playwright

echo "📦 安装 Chromium 浏览器引擎（导航站提取用）..."
python3 -m playwright install --with-deps chromium 2>/dev/null && echo "✅ Chromium 已安装" || python3 -m playwright install chromium 2>/dev/null && echo "✅ Chromium 已安装" || echo "⚠️  Chromium 安装失败，导航站子站提取功能将不可用（不影响主采集）"

# ═══════════════════════════════════════
# 3. 复制到正确目录
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 3 步：安装 Skill 文件 ━━━"
echo ""

if [ "$SKILL_DIR" != "$SKILLS_DIR" ]; then
    echo "📁 复制 Skill 到 OpenClaw 目录..."
    mkdir -p "$SKILLS_DIR"
    cp -r "$SKILL_DIR"/* "$SKILLS_DIR/"
    echo "✅ 已安装到 $SKILLS_DIR"
else
    echo "✅ Skill 已在正确目录"
fi

# 确保 data 目录存在（URL 缓存用）
mkdir -p "$SKILLS_DIR/data"

# ═══════════════════════════════════════
# 4. 配置 Tavily API Key
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 4 步：配置 Tavily 搜索 API ━━━"
echo ""
echo "Tavily 用于搜索关键词发现新站点。"
echo "  申请地址：https://tavily.com"
echo "  免费额度：1000 次/月（够用约 4 次全量搜索）"
echo "  注册后在 Dashboard → API Keys 获取"
echo ""

TAVILY_KEY=""
if [ -n "$TAVILY_API_KEY" ]; then
    echo "✅ 环境变量中已有 TAVILY_API_KEY"
    read -p "是否更换？[y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "输入新的 TAVILY_API_KEY: " TAVILY_KEY
    fi
else
    while [ -z "$TAVILY_KEY" ]; do
        read -p "请输入 TAVILY_API_KEY（tvly-开头）: " TAVILY_KEY
        if [ -z "$TAVILY_KEY" ]; then
            echo "⚠️  Tavily API Key 是必须的，没有它无法搜索新站点。"
            read -p "确定跳过？日常采集仍可用缓存运行 [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                break
            fi
        fi
    done
fi

# ═══════════════════════════════════════
# 5. 配置 Telegram Bot
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 5 步：配置 Telegram Bot ━━━"
echo ""
echo "Telegram Bot 用于：接收采集指令 + 推送采集结果"
echo ""
echo "如果还没有 Bot，请先在 Telegram 找 @BotFather："
echo "  1. 发送 /newbot"
echo "  2. 输入 Bot 名称（随意取）"
echo "  3. 输入 Bot 用户名（需以 bot 结尾）"
echo "  4. 复制返回的 Token（格式：123456:ABC-xxx）"
echo ""

TG_TOKEN=""
while [ -z "$TG_TOKEN" ]; do
    read -p "请输入 TG Bot Token: " TG_TOKEN
    if [ -z "$TG_TOKEN" ]; then
        echo "⚠️  Bot Token 是必须的，没有它无法接收指令和推送结果。"
        echo ""
    fi
done

echo ""
echo "接下来需要你的 Telegram Chat ID（用于推送结果）。"
echo ""
echo "获取方式："
echo "  1. 在 Telegram 搜索 @userinfobot"
echo "  2. 给它发任意消息"
echo "  3. 它会回复你的 Chat ID（纯数字）"
echo ""

TG_CHAT=""
while [ -z "$TG_CHAT" ]; do
    read -p "请输入 TG Chat ID（纯数字）: " TG_CHAT
    if [ -z "$TG_CHAT" ]; then
        echo "⚠️  Chat ID 是必须的，没有它无法推送采集结果。"
        echo ""
    fi
done

# ═══════════════════════════════════════
# 6. 写入 Gateway 环境变量
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 6 步：写入配置 ━━━"
echo ""

# 检测操作系统
OS_TYPE="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_TYPE="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS_TYPE="linux"
fi

write_env_success=false

if [ "$OS_TYPE" == "macos" ]; then
    PLIST="$HOME/Library/LaunchAgents/ai.openclaw.gateway.plist"
    if [ -f "$PLIST" ]; then
        echo "📝 写入 macOS LaunchAgent 环境变量..."

        # 备份
        cp "$PLIST" "$PLIST.bak.$(date +%Y%m%d%H%M%S)"

        # 用 Python 修改 plist（比 PlistBuddy 更可靠）
        python3 << PYEOF
import plistlib, sys, os

plist_path = "$PLIST"
with open(plist_path, 'rb') as f:
    plist = plistlib.load(f)

env = plist.get('EnvironmentVariables', {})

tavily_key = "$TAVILY_KEY"
tg_token = "$TG_TOKEN"
tg_chat = "$TG_CHAT"

if tavily_key:
    env['TAVILY_API_KEY'] = tavily_key
if tg_token:
    env['TG_BOT_TOKEN'] = tg_token
if tg_chat:
    env['TG_CHAT_ID'] = tg_chat

plist['EnvironmentVariables'] = env

with open(plist_path, 'wb') as f:
    plistlib.dump(plist, f)

print("✅ 已写入 LaunchAgent plist")
PYEOF
        write_env_success=true
    else
        echo "⚠️  未找到 LaunchAgent plist: $PLIST"
        echo "   请手动配置环境变量（见下方说明）"
    fi

elif [ "$OS_TYPE" == "linux" ]; then
    echo "📝 写入 Linux systemd 环境变量..."

    # 创建 override 文件
    OVERRIDE_DIR="/etc/systemd/system/openclaw-gateway.service.d"
    sudo mkdir -p "$OVERRIDE_DIR" 2>/dev/null

    ENV_LINES=""
    [ -n "$TAVILY_KEY" ] && ENV_LINES="${ENV_LINES}Environment=\"TAVILY_API_KEY=$TAVILY_KEY\"\n"
    [ -n "$TG_TOKEN" ] && ENV_LINES="${ENV_LINES}Environment=\"TG_BOT_TOKEN=$TG_TOKEN\"\n"
    [ -n "$TG_CHAT" ] && ENV_LINES="${ENV_LINES}Environment=\"TG_CHAT_ID=$TG_CHAT\"\n"

    if [ -n "$ENV_LINES" ]; then
        echo -e "[Service]\n$ENV_LINES" | sudo tee "$OVERRIDE_DIR/env.conf" > /dev/null
        sudo systemctl daemon-reload
        echo "✅ 已写入 systemd override"
        write_env_success=true
    fi
else
    echo "⚠️  无法识别操作系统，请手动配置环境变量"
fi

# ═══════════════════════════════════════
# 7. 绑定 TG Channel
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 7 步：绑定 Telegram 频道 ━━━"
echo ""

if [ -n "$TG_TOKEN" ]; then
    echo "🔗 绑定 Telegram Bot 到 OpenClaw..."
    openclaw channels add --channel telegram --token "$TG_TOKEN" 2>/dev/null && echo "✅ Telegram 频道已绑定" || echo "⚠️  绑定失败，可能已绑定过。如需更换请先 openclaw channels remove telegram"

    # 设置 dmPolicy 为 open（无需配对）
    echo "🔓 设置 DM 策略为 open（无需配对审批）..."
    OPENCLAW_JSON="$OPENCLAW_DIR/openclaw.json"
    if [ -f "$OPENCLAW_JSON" ]; then
        python3 << PYEOF
import json

config_path = "$OPENCLAW_JSON"
with open(config_path, 'r') as f:
    config = json.load(f)

if 'channels' not in config:
    config['channels'] = {}
if 'telegram' not in config['channels']:
    config['channels']['telegram'] = {}
config['channels']['telegram']['dmPolicy'] = 'open'

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)

print("✅ dmPolicy 已设为 open")
PYEOF
    fi
fi

# ═══════════════════════════════════════
# 8. 配置工具权限
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 8 步：配置权限 ━━━"
echo ""

# 设置工具 profile
echo "🔧 设置工具 profile 为 full..."
openclaw config set tools.profile full 2>/dev/null && echo "✅ 工具 profile: full" || echo "⚠️  设置失败，请手动执行: openclaw config set tools.profile full"

# exec 白名单
echo "🔐 配置 exec 权限白名单..."
SCRIPTS_PATH="$SKILLS_DIR/scripts"
openclaw approvals allowlist add "$SCRIPTS_PATH/site-collector.py" 2>/dev/null && echo "  ✅ site-collector.py" || true
openclaw approvals allowlist add "$SCRIPTS_PATH/keyword-search.py" 2>/dev/null && echo "  ✅ keyword-search.py" || true
openclaw approvals allowlist add "$SCRIPTS_PATH/nav-extractor.py" 2>/dev/null && echo "  ✅ nav-extractor.py" || true
openclaw approvals allowlist add "*/site-info-collector/scripts/*.py" 2>/dev/null && echo "  ✅ 通配符规则" || true
openclaw approvals allowlist add "$(which python3)" 2>/dev/null && echo "  ✅ python3 binary" || true

# ═══════════════════════════════════════
# 9. 合并触发规则
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 9 步：配置触发规则 ━━━"
echo ""

AGENTS_MD="$OPENCLAW_DIR/workspace/AGENTS.md"
PATCH_FILE="$SKILLS_DIR/AGENTS.md.patch"

# 如果 patch 来源是当前目录（尚未复制），用当前目录的
if [ ! -f "$PATCH_FILE" ] && [ -f "$SKILL_DIR/AGENTS.md.patch" ]; then
    PATCH_FILE="$SKILL_DIR/AGENTS.md.patch"
fi

if [ -f "$PATCH_FILE" ]; then
    if [ -f "$AGENTS_MD" ]; then
        if grep -q "site-info-collector" "$AGENTS_MD" 2>/dev/null; then
            echo "✅ AGENTS.md 已包含采集触发规则"
        else
            echo "📝 合并采集触发规则到 AGENTS.md..."
            echo "" >> "$AGENTS_MD"
            cat "$PATCH_FILE" >> "$AGENTS_MD"
            echo "✅ 触发规则已合并"
        fi
    else
        echo "📝 创建 AGENTS.md..."
        cp "$PATCH_FILE" "$AGENTS_MD"
        echo "✅ AGENTS.md 已创建"
    fi
else
    echo "⚠️  未找到 AGENTS.md.patch，跳过触发规则配置"
fi

# ═══════════════════════════════════════
# 10. 重启 Gateway
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 10 步：重启 Gateway ━━━"
echo ""

echo "🔄 重启 OpenClaw Gateway 使配置生效..."
openclaw daemon restart 2>/dev/null && echo "✅ Gateway 已重启" || echo "⚠️  重启失败，请手动执行: openclaw daemon restart"

# 等一下让 gateway 启动
sleep 3

# 检查状态
echo ""
echo "📊 检查 Gateway 状态..."
openclaw daemon status 2>/dev/null || echo "⚠️  无法获取状态"

# ═══════════════════════════════════════
# 完成
# ═══════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║           ✅ 安装完成！                   ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "📋 配置摘要："
echo "  ├─ Tavily API Key: $([ -n "$TAVILY_KEY" ] && echo '已配置' || echo '跳过（仅限缓存模式）')"
echo "  ├─ TG Bot Token:   $([ -n "$TG_TOKEN" ] && echo '已配置' || echo '未配置')"
echo "  ├─ TG Chat ID:     $([ -n "$TG_CHAT" ] && echo '已配置' || echo '未配置')"
echo "  ├─ 工具 Profile:   full"
echo "  ├─ Exec 白名单:    已配置"
echo "  ├─ DM 策略:        open（无需配对）"
echo "  └─ 触发规则:       已合并"
echo ""

if [ -n "$TG_TOKEN" ]; then
    echo "🧪 验证步骤："
    echo "  1. 在 Telegram 找到你的 Bot"
    echo "  2. 发送「采集导航站」"
    echo "  3. Bot 应自动开始采集并在完成后推送结果"
    echo ""
    echo "💡 常用指令："
    echo "  「采集」      → 日常模式（用缓存，零 API 消耗）"
    echo "  「采集导航站」→ 搜索导航类新站点并采集"
    echo "  「采集小说站」→ 搜索小说类新站点并采集"
    echo "  「搜新的」    → 全量搜索（消耗 Tavily API）"
fi

echo ""
echo "📖 详细文档见: $SKILLS_DIR/DEPLOY.md"
echo ""

if [ "$write_env_success" != true ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  环境变量未自动写入，请手动配置："
    echo ""
    [ -n "$TAVILY_KEY" ] && echo "  TAVILY_API_KEY=$TAVILY_KEY"
    [ -n "$TG_TOKEN" ] && echo "  TG_BOT_TOKEN=$TG_TOKEN"
    [ -n "$TG_CHAT" ] && echo "  TG_CHAT_ID=$TG_CHAT"
    echo ""
    echo "  macOS: 编辑 ~/Library/LaunchAgents/ai.openclaw.gateway.plist"
    echo "  Linux: sudo systemctl edit openclaw-gateway"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi
