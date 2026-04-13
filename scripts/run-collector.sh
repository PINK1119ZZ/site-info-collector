#!/bin/bash
# 站点信息采集主控脚本
# 用法：
#   ./run-collector.sh                          # 全量：关键词搜索 → 导航站提取 → 采集 → 推送
#   ./run-collector.sh --urls urls.txt          # 直接从 URL 文件采集
#   ./run-collector.sh --skip-search            # 跳过搜索，只跑导航提取+采集
#   ./run-collector.sh --chat-id 908696841      # 指定推送目标

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK_DIR="/tmp/site-collector-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$WORK_DIR"

# 默认参数
CHAT_ID="${CHAT_ID:-908696841}"
SKIP_SEARCH=false
URL_FILE=""
BATCH_SIZE=10
ENGINE="tavily"
CATEGORY=""
MAX_PER_KEYWORD=5

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --chat-id) CHAT_ID="$2"; shift 2;;
        --skip-search) SKIP_SEARCH=true; shift;;
        --urls) URL_FILE="$2"; shift 2;;
        --batch-size) BATCH_SIZE="$2"; shift 2;;
        --engine) ENGINE="$2"; shift 2;;
        --category) CATEGORY="$2"; shift 2;;
        --max-per-keyword) MAX_PER_KEYWORD="$2"; shift 2;;
        *) echo "未知参数: $1"; exit 1;;
    esac
done

echo "=== 站点信息采集 ==="
echo "工作目录: $WORK_DIR"
echo "推送目标: Telegram chat $CHAT_ID"
echo ""

# ── 第一步：获取 URL 列表 ──
if [[ -n "$URL_FILE" ]]; then
    echo "[1/4] 使用已有 URL 文件: $URL_FILE"
    cp "$URL_FILE" "$WORK_DIR/search-urls.txt"
else
    if [[ "$SKIP_SEARCH" == "true" ]]; then
        echo "[1/4] 跳过搜索"
        touch "$WORK_DIR/search-urls.txt"
    else
        echo "[1/4] 关键词搜索..."
        SEARCH_ARGS="--engine $ENGINE --max-per-keyword $MAX_PER_KEYWORD --output $WORK_DIR/search-urls.txt"
        if [[ -n "$CATEGORY" ]]; then
            SEARCH_ARGS="$SEARCH_ARGS --category $CATEGORY"
        fi
        python3 "$SCRIPT_DIR/keyword-search.py" $SEARCH_ARGS
    fi
fi

SEARCH_COUNT=$(wc -l < "$WORK_DIR/search-urls.txt" | tr -d ' ')
echo "  搜索得到 $SEARCH_COUNT 个站点"

# ── 第二步：导航站子站提取 ──
echo ""
echo "[2/4] 导航站子站提取..."
NAV_URLS=$(grep -iE '导航|nav|daohang|dh\.|hao123|fuliba|114' "$WORK_DIR/search-urls.txt" 2>/dev/null || true)
if [[ -n "$NAV_URLS" ]]; then
    echo "$NAV_URLS" > "$WORK_DIR/nav-candidates.txt"
    NAV_COUNT=$(wc -l < "$WORK_DIR/nav-candidates.txt" | tr -d ' ')
    echo "  发现 $NAV_COUNT 个疑似导航站，提取子站链接..."
    python3 "$SCRIPT_DIR/nav-extractor.py" "$WORK_DIR/nav-candidates.txt" --output "$WORK_DIR/nav-urls.txt" 2>&1
else
    echo "  未发现导航站"
    touch "$WORK_DIR/nav-urls.txt"
fi

# 合并去重
cat "$WORK_DIR/search-urls.txt" "$WORK_DIR/nav-urls.txt" | grep -E '^https?://' | sort -u > "$WORK_DIR/all-urls.txt"
TOTAL_COUNT=$(wc -l < "$WORK_DIR/all-urls.txt" | tr -d ' ')
echo "  合并去重后共 $TOTAL_COUNT 个站点"

if [[ "$TOTAL_COUNT" -eq 0 ]]; then
    echo "没有要采集的站点，退出"
    exit 0
fi

# ── 第三步：分批采集 ──
echo ""
echo "[3/4] 分批采集（每批 $BATCH_SIZE 个）..."

RESULT_FILE="$WORK_DIR/results.json"
echo "[" > "$RESULT_FILE"
FIRST=true
BATCH_NUM=0
SUCCESS=0
FAILED=0

while IFS= read -r url_line; do
    BATCH_URLS="$url_line"
    BATCH_COUNT=1

    # 读取一批 URL
    while [[ $BATCH_COUNT -lt $BATCH_SIZE ]] && IFS= read -r next_url; do
        BATCH_URLS="$BATCH_URLS
$next_url"
        ((BATCH_COUNT++))
    done

    ((BATCH_NUM++))
    echo "  批次 $BATCH_NUM: $BATCH_COUNT 个站点..."

    # 构造消息
    MSG="使用 site-info-collector skill，采集以下站点信息，严格按 JSON 数组格式输出（只输出 JSON，不要其他文字）：
$BATCH_URLS"

    # 调用 OpenClaw agent
    RESPONSE=$(openclaw agent --agent main --message "$MSG" --json --timeout 300 2>&1 || true)

    # 提取 JSON 结果
    BATCH_RESULT=$(echo "$RESPONSE" | python3 -c "
import sys, json, re
data = json.load(sys.stdin)
text = data.get('finalAssistantVisibleText', '')
# 提取 JSON 数组或对象
match = re.search(r'(\[[\s\S]*\]|\{[\s\S]*\})', text)
if match:
    print(match.group(1))
else:
    print('[]')
" 2>/dev/null || echo "[]")

    # 追加到结果文件
    if [[ "$BATCH_RESULT" != "[]" ]]; then
        # 如果是数组，展开元素；如果是对象，直接加入
        echo "$BATCH_RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if isinstance(data, list):
    for item in data:
        print(json.dumps(item, ensure_ascii=False))
elif isinstance(data, dict):
    print(json.dumps(data, ensure_ascii=False))
" 2>/dev/null | while IFS= read -r item; do
            if [[ "$FIRST" == "true" ]]; then
                FIRST=false
            else
                echo "," >> "$RESULT_FILE"
            fi
            echo "$item" >> "$RESULT_FILE"
            ((SUCCESS++))
        done
        FIRST=false
    fi

done < "$WORK_DIR/all-urls.txt"

echo "]" >> "$RESULT_FILE"

# 格式化 JSON
python3 -c "
import json
with open('$RESULT_FILE') as f:
    data = json.load(f)
with open('$RESULT_FILE', 'w') as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
print(f'采集完成: {len(data)} 个站点')
" 2>/dev/null || echo "JSON 格式化失败，使用原始输出"

# ── 第四步：推送结果 ──
echo ""
echo "[4/4] 推送结果到 Telegram..."

# 统计
STATS=$(python3 -c "
import json
with open('$RESULT_FILE') as f:
    data = json.load(f)
success = sum(1 for d in data if d.get('status') == 'success')
partial = sum(1 for d in data if d.get('status') == 'partial')
failed = sum(1 for d in data if d.get('status') == 'failed')
contacts = sum(len(d.get('contacts', [])) for d in data)
print(f'共采集 {len(data)} 个站点: {success} 成功, {partial} 部分, {failed} 失败, 共 {contacts} 条联系方式')
" 2>/dev/null)

echo "$STATS"

# 用 Telegram Bot API 直接发送文件
TG_TOKEN="8327615966:AAH4GofqNodAzhuG1WFV2aow0MVqkTkWR1A"

# 先发统计摘要
curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="📊 采集完成

$STATS

JSON 文件随后发送 ⬇️" \
    -d parse_mode="Markdown" > /dev/null

# 复制结果文件到带时间戳的文件名
DATED_FILE="$WORK_DIR/site-info-$(date +%Y%m%d-%H%M%S).json"
cp "$RESULT_FILE" "$DATED_FILE"

# 发送 JSON 文件
curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendDocument" \
    -F chat_id="$CHAT_ID" \
    -F document=@"$DATED_FILE" \
    -F caption="站点基础信息采集结果" > /dev/null

echo ""
echo "=== 完成 ==="
echo "结果文件: $DATED_FILE"
echo "已推送到 Telegram chat $CHAT_ID"
