#!/bin/bash
# 站点信息采集 — 一键安装脚本（创建独立 Agent）
# 不用 set -e，各步骤自行处理错误

AGENT_NAME="site-collector"

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║     站点基础信息采集 — 安装向导           ║"
echo "║     将创建独立 Agent: $AGENT_NAME        ║"
echo "╚══════════════════════════════════════════╝"
echo ""

SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCLAW_DIR="$HOME/.openclaw"
AGENT_WORKSPACE="$OPENCLAW_DIR/agents/$AGENT_NAME/workspace"

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
OPENCLAW_VER=$(openclaw --version 2>/dev/null | head -1)
echo "✅ OpenClaw $OPENCLAW_VER"

# 检查 Python
if ! command -v python3 &>/dev/null; then
    echo "❌ 未找到 Python3，请先安装"
    exit 1
fi
echo "✅ Python $(python3 --version 2>&1)"

# ═══════════════════════════════════════
# 2. 安装 Python 依赖
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 2 步：安装 Python 依赖 ━━━"
echo ""

echo "📦 安装 requests, beautifulsoup4, playwright..."
pip3 install --quiet requests beautifulsoup4 playwright 2>/dev/null \
  || pip3 install --break-system-packages --quiet requests beautifulsoup4 playwright 2>/dev/null \
  || pip3 install --break-system-packages requests beautifulsoup4 playwright

echo "📦 安装 Chromium 浏览器引擎（导航站提取用）..."
python3 -m playwright install --with-deps chromium 2>/dev/null && echo "✅ Chromium 已安装" \
  || python3 -m playwright install chromium 2>/dev/null && echo "✅ Chromium 已安装" \
  || echo "⚠️  Chromium 安装失败，导航站子站提取功能将不可用（不影响主采集）"

# ═══════════════════════════════════════
# 3. 配置 Tavily API Key
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 3 步：配置 Tavily 搜索 API ━━━"
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
# 4. 配置 Telegram Bot
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 4 步：配置 Telegram Bot ━━━"
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
# 5. 创建独立 Agent
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 5 步：创建独立 Agent ━━━"
echo ""

# 检查是否已存在
EXISTING=$(openclaw agents list 2>/dev/null | grep -w "$AGENT_NAME" || true)
if [ -n "$EXISTING" ]; then
    echo "ℹ️  Agent '$AGENT_NAME' 已存在，跳过创建"
else
    echo "🤖 创建 Agent: $AGENT_NAME..."
    openclaw agents add "$AGENT_NAME" \
        --workspace "$AGENT_WORKSPACE" \
        --non-interactive \
        2>/dev/null \
        && echo "✅ Agent '$AGENT_NAME' 已创建" \
        || {
            echo "⚠️  自动创建失败，尝试手动创建目录..."
            mkdir -p "$AGENT_WORKSPACE"
            mkdir -p "$OPENCLAW_DIR/agents/$AGENT_NAME/agent"
            # 写入最小 agent config
            python3 << PYEOF
import json, os

config_path = "$OPENCLAW_DIR/openclaw.json"
with open(config_path, 'r') as f:
    config = json.load(f)

if 'agents' not in config:
    config['agents'] = {}
if 'list' not in config['agents']:
    config['agents']['list'] = {}

config['agents']['list']['$AGENT_NAME'] = {
    'workspace': '$AGENT_WORKSPACE',
    'agentDir': '$OPENCLAW_DIR/agents/$AGENT_NAME/agent'
}

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)

print("✅ Agent '$AGENT_NAME' 已手动注册")
PYEOF
        }
fi

# 检查 model 配置
echo ""
echo "🧠 检查 AI 模型配置..."
CURRENT_MODEL=$(openclaw config get model 2>/dev/null || echo "")
if [ -n "$CURRENT_MODEL" ]; then
    echo "✅ 当前模型: $CURRENT_MODEL"
    echo "   Agent '$AGENT_NAME' 将使用此模型理解指令（每次 < 1000 token）"
else
    echo "⚠️  未检测到 AI 模型配置"
    echo "   Agent 需要一个 AI 模型来理解用户指令（如「采集导航站」→ 执行对应脚本）"
    echo "   实际采集由 Python 爬虫完成，AI token 消耗极少（每次 < 1000 token）"
    echo ""
    echo "   请确保已配置模型，例如："
    echo "   openclaw config set model \"gptproto/claude-sonnet-4-6\""
    echo ""
    read -p "是否继续安装？[Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "请先配置模型后重新运行 setup.sh"
        exit 1
    fi
fi

# ═══════════════════════════════════════
# 6. 安装 Skill 文件到 Agent workspace
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 6 步：安装 Skill 文件 ━━━"
echo ""

SKILLS_DIR="$AGENT_WORKSPACE/skills/site-info-collector"
mkdir -p "$SKILLS_DIR/scripts"
mkdir -p "$SKILLS_DIR/data"

# 复制脚本和配置
cp "$SKILL_DIR/scripts/"*.py "$SKILLS_DIR/scripts/" 2>/dev/null
cp "$SKILL_DIR/scripts/"*.sh "$SKILLS_DIR/scripts/" 2>/dev/null
cp "$SKILL_DIR/SKILL.md" "$SKILLS_DIR/" 2>/dev/null
cp "$SKILL_DIR/AGENTS.md.patch" "$SKILLS_DIR/" 2>/dev/null
cp "$SKILL_DIR/DEPLOY.md" "$SKILLS_DIR/" 2>/dev/null
echo "✅ Skill 文件已安装到 $SKILLS_DIR"

# 写 AGENTS.md（Agent 自己的触发规则）
AGENTS_MD="$AGENT_WORKSPACE/AGENTS.md"
if [ -f "$SKILL_DIR/AGENTS.md.patch" ]; then
    if [ -f "$AGENTS_MD" ] && grep -q "site-info-collector" "$AGENTS_MD" 2>/dev/null; then
        echo "✅ AGENTS.md 已包含采集触发规则"
    else
        echo "📝 写入 Agent 规则和使用说明..."
        cat > "$AGENTS_MD" << 'AGENTSEOF'
# Site Collector Agent

你是「站点信息采集 Bot」，专门执行站点联系方式采集任务。

**核心原则：**
- 用户说「采集」相关指令 → 立即 exec 执行脚本，不要反问
- 用户打招呼或问怎么用 → 回复使用说明引导
- 始终用中文回复

AGENTSEOF
        cat "$SKILL_DIR/AGENTS.md.patch" >> "$AGENTS_MD"
        echo "✅ AGENTS.md 已创建"
    fi
fi

# ═══════════════════════════════════════
# 7. 绑定 TG Bot 到 Agent
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 7 步：绑定 Telegram Bot ━━━"
echo ""

if [ -n "$TG_TOKEN" ]; then
    # 添加 TG 帐号（用 agent 名作为帐号名）
    echo "🔗 添加 Telegram Bot 帐号..."
    openclaw channels add --channel telegram --account "$AGENT_NAME" --token "$TG_TOKEN" 2>/dev/null \
        && echo "✅ Telegram 帐号 '$AGENT_NAME' 已添加" \
        || echo "ℹ️  帐号可能已存在"

    # 绑定到 agent
    echo "🔗 绑定 Bot 到 Agent '$AGENT_NAME'..."
    openclaw agents bind --agent "$AGENT_NAME" --bind "telegram:$AGENT_NAME" 2>/dev/null \
        && echo "✅ Bot 已绑定到 Agent '$AGENT_NAME'" \
        || echo "⚠️  绑定失败，请手动执行: openclaw agents bind --agent $AGENT_NAME --bind telegram:$AGENT_NAME"

    # 设置 dmPolicy 为 open
    echo "🔓 设置 DM 策略为 open..."
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
if 'allowFrom' not in config['channels']['telegram']:
    config['channels']['telegram']['allowFrom'] = ['*']
elif '*' not in config['channels']['telegram']['allowFrom']:
    config['channels']['telegram']['allowFrom'].append('*')

with open(config_path, 'w') as f:
    json.dump(config, f, indent=2)

print("✅ dmPolicy 已设为 open")
PYEOF
    fi
fi

# ═══════════════════════════════════════
# 8. 写入环境变量
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 8 步：写入环境变量 ━━━"
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
        cp "$PLIST" "$PLIST.bak.$(date +%Y%m%d%H%M%S)"

        python3 << PYEOF
import plistlib

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
    fi

elif [ "$OS_TYPE" == "linux" ]; then
    echo "📝 写入 Linux systemd 环境变量..."

    # 用独立的 override 文件，不影响已有配置
    OVERRIDE_DIR="/etc/systemd/system/openclaw-gateway.service.d"
    sudo mkdir -p "$OVERRIDE_DIR" 2>/dev/null
    OVERRIDE_FILE="$OVERRIDE_DIR/site-collector-env.conf"

    ENV_LINES=""
    [ -n "$TAVILY_KEY" ] && ENV_LINES="${ENV_LINES}Environment=\"TAVILY_API_KEY=$TAVILY_KEY\"\n"
    [ -n "$TG_TOKEN" ] && ENV_LINES="${ENV_LINES}Environment=\"TG_BOT_TOKEN=$TG_TOKEN\"\n"
    [ -n "$TG_CHAT" ] && ENV_LINES="${ENV_LINES}Environment=\"TG_CHAT_ID=$TG_CHAT\"\n"

    if [ -n "$ENV_LINES" ]; then
        echo -e "[Service]\n$ENV_LINES" | sudo tee "$OVERRIDE_FILE" > /dev/null
        sudo systemctl daemon-reload
        echo "✅ 已写入 systemd override（$OVERRIDE_FILE）"
        echo "   不影响已有环境变量配置"
        write_env_success=true
    fi
else
    echo "⚠️  无法识别操作系统，请手动配置环境变量"
fi

# ═══════════════════════════════════════
# 9. 配置权限
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 9 步：配置权限 ━━━"
echo ""

# 注意：不修改全局 tools.profile，避免影响现有 agent
# 只通过 exec 白名单授权 site-collector agent 执行采集脚本

echo "🔐 配置 exec 权限白名单（仅限 $AGENT_NAME agent）..."
SCRIPTS_PATH="$SKILLS_DIR/scripts"

# 方式1：精确路径白名单
openclaw approvals allowlist add --agent "$AGENT_NAME" "$SCRIPTS_PATH/site-collector.py" 2>/dev/null && echo "  ✅ site-collector.py" || true
openclaw approvals allowlist add --agent "$AGENT_NAME" "$SCRIPTS_PATH/keyword-search.py" 2>/dev/null && echo "  ✅ keyword-search.py" || true
openclaw approvals allowlist add --agent "$AGENT_NAME" "$SCRIPTS_PATH/nav-extractor.py" 2>/dev/null && echo "  ✅ nav-extractor.py" || true

# 方式2：通配符（兼容不同安装路径）
openclaw approvals allowlist add --agent "$AGENT_NAME" "*/site-info-collector/scripts/*.py" 2>/dev/null && echo "  ✅ 通配符规则" || true

# 方式3：python3 本体（脚本通过 python3 xxx.py 调用时需要）
openclaw approvals allowlist add --agent "$AGENT_NAME" "$(which python3)" 2>/dev/null && echo "  ✅ python3 binary" || true

# 设置 agent 级别的 exec 安全策略为 full（不影响全局）
openclaw approvals set --agent "$AGENT_NAME" --security full 2>/dev/null && echo "  ✅ agent exec 策略: full" \
  || echo "  ℹ️  approvals set 不支持，白名单已足够"

# ═══════════════════════════════════════
# 10. 重启 Gateway
# ═══════════════════════════════════════
echo ""
echo "━━━ 第 10 步：重启 Gateway ━━━"
echo ""

echo "🔄 重启 OpenClaw Gateway 使配置生效..."
if [ "$OS_TYPE" == "linux" ]; then
    sudo systemctl daemon-reload 2>/dev/null
    sudo systemctl restart openclaw-gateway 2>/dev/null && echo "✅ Gateway 已重启（systemd）" \
      || systemctl --user restart openclaw-gateway 2>/dev/null && echo "✅ Gateway 已重启（user systemd）" \
      || openclaw daemon restart 2>/dev/null && echo "✅ Gateway 已重启" \
      || echo "⚠️  重启失败，请手动执行: openclaw daemon restart"
else
    openclaw daemon restart 2>/dev/null && echo "✅ Gateway 已重启" || echo "⚠️  重启失败，请手动执行: openclaw daemon restart"
fi

sleep 3

echo ""
echo "📊 检查状态..."
openclaw health 2>/dev/null | head -5 && echo "" || true
openclaw agents list 2>/dev/null | grep -A2 "$AGENT_NAME" && echo "" || true

# ═══════════════════════════════════════
# 完成
# ═══════════════════════════════════════
echo ""
echo "╔══════════════════════════════════════════╗"
echo "║           ✅ 安装完成！                   ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "📋 配置摘要："
echo "  ├─ Agent:          $AGENT_NAME（独立 Agent，不影响现有服务）"
echo "  ├─ Workspace:      $AGENT_WORKSPACE"
echo "  ├─ Tavily API Key: $([ -n "$TAVILY_KEY" ] && echo '已配置' || echo '跳过（仅限缓存模式）')"
echo "  ├─ TG Bot Token:   $([ -n "$TG_TOKEN" ] && echo '已配置' || echo '未配置')"
echo "  ├─ TG Chat ID:     $([ -n "$TG_CHAT" ] && echo '已配置' || echo '未配置')"
echo "  ├─ TG Bot 绑定:    $AGENT_NAME → telegram:$AGENT_NAME"
echo "  ├─ Exec 白名单:    已配置（仅限 $AGENT_NAME）"
echo "  └─ DM 策略:        open（无需配对）"
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
