# 站点基础信息采集 — 部署指南

## 交付物清单

```
site-info-collector/
├── SKILL.md              # OpenClaw Skill 定义（必须）
├── DEPLOY.md             # 本部署指南
├── setup.sh              # 一键安装脚本
├── AGENTS.md.patch        # OpenClaw 触发规则（需合并到 workspace/AGENTS.md）
└── scripts/
    ├── site-collector.py  # 主采集脚本（Python 爬虫，核心）
    ├── keyword-search.py  # 关键词搜索（Tavily API）
    └── nav-extractor.py   # 导航站子站提取（Playwright）
```

---

## 一键安装

```bash
# 1. 解压到 OpenClaw skills 目录
cp -r site-info-collector/ ~/.openclaw/workspace/skills/site-info-collector/

# 2. 运行安装脚本
cd ~/.openclaw/workspace/skills/site-info-collector/
bash setup.sh
```

安装脚本会自动：
- 安装 Python 依赖（requests, beautifulsoup4, playwright）
- 安装 Chromium 浏览器引擎
- 检查 OpenClaw 工具配置
- 提示配置 API Key 和 TG Bot

---

## 手动安装（如果一键安装不行）

### 1. 环境要求

| 项目 | 要求 |
|------|------|
| OpenClaw | 2026.4.x 以上 |
| Python | 3.9+ |
| 操作系统 | Linux / macOS |

### 2. Python 依赖

```bash
pip3 install requests beautifulsoup4 playwright
python3 -m playwright install chromium
```

### 3. API Key 配置

#### Tavily Search API Key（必须）

关键词搜索用。普通搜索引擎会过滤部分关键词，Tavily 不会。

- 申请：https://tavily.com
- 免费：1000 次/月

配置到 OpenClaw 环境：

**Linux (systemd)：**
```bash
sudo systemctl edit openclaw-gateway
# 添加：
# [Service]
# Environment="TAVILY_API_KEY=tvly-xxxxxxxx"
sudo systemctl restart openclaw-gateway
```

**macOS (LaunchAgent)：**

编辑 `~/Library/LaunchAgents/ai.openclaw.gateway.plist`，在 `<dict>` 的 `EnvironmentVariables` 中添加：
```xml
<key>TAVILY_API_KEY</key>
<string>tvly-xxxxxxxx</string>
```
然后重启：`openclaw daemon restart`

#### AI 模型（必须）

OpenClaw 需要一个 AI 模型来理解用户指令（如「采集导航站」→ 调用 `--category 导航`）。
实际采集由 Python 脚本完成，AI token 消耗极少（每次指令 < 1000 token）。

**订阅制（GPT Plus/Pro、Claude Pro）或 API 按量付费均可。**

AI 模型仅负责理解触发指令（如「采集导航站」→ 执行 `--category 导航`），不参与实际采集。
搜索、爬取、提取联系方式、去重、脱敏、生成 JSON、推送 TG 全部由 Python 爬虫完成，零 token 消耗。

如果 OpenClaw 上已有可用的模型（Bot 能正常回话），则无需额外配置。

### 4. 绑定 Telegram Bot

```bash
# 创建 Bot：在 Telegram 找 @BotFather，发 /newbot
# 拿到 Token 后：
openclaw channels add --channel telegram --token "<你的 Bot Token>"
openclaw daemon restart
openclaw channels status --probe

# 首次使用需配对：
# 用户在 TG 给 Bot 发一条消息
openclaw pairing list        # 查看配对请求
openclaw pairing approve <CODE>  # 批准
```

配置 TG 推送环境变量（同 Tavily 方式，加到 gateway 环境中）：
```
TG_BOT_TOKEN=<你的 Bot Token>
TG_CHAT_ID=<用户的 Chat ID>
```

Chat ID 可从 `openclaw channels logs` 中获取，或在 gateway log 中搜索 `chatId`。

### 5. OpenClaw 工具配置

```bash
# 确保工具 profile 为 full
openclaw config set tools.profile full
```

### 6. 合并触发规则

将 `AGENTS.md.patch` 的内容追加到 `~/.openclaw/workspace/AGENTS.md` 的 `## Tools` 段前面。
这样 Bot 收到「采集」指令才会自动调用脚本。

---

## 验证部署

```bash
# 1. 测试关键词搜索
cd ~/.openclaw/workspace/skills/site-info-collector/scripts
python3 keyword-search.py --engine tavily --category 导航 --max-per-keyword 2 --output /tmp/test-urls.txt
cat /tmp/test-urls.txt    # 应该输出一批 URL

# 2. 测试采集（用 2 个站快速验证）
echo -e "https://www.ypojie.com\nhttps://www.ghxi.com" > /tmp/test2.txt
python3 site-collector.py --urls /tmp/test2.txt --output /tmp/test-result.json
cat /tmp/test-result.json  # 应该看到 JSON 结果

# 3. 测试 TG Bot
在 Telegram 对 Bot 发送「采集导航站」
```

---

## 使用方式

| 指令 | 说明 |
|------|------|
| `开始采集` | 搜索全部 4 类关键词并采集 |
| `采集导航站` | 只搜导航类（~32 关键词） |
| `采集小说站` | 只搜小说类 |
| `采集视频站` | 只搜视频类 |
| `采集漫画站` | 只搜漫画类 |

Bot 自动执行全流程（约 30-40 分钟/类），完成后推送：
1. 采集统计报告
2. 失败归因 + 复盘建议
3. JSON 结果文件

---

## 费用估算

采集由 Python 爬虫完成，AI 只负责理解指令，token 消耗极少。

| 项目 | 免费额度 | 超出后费用 | 每次全量采集消耗 |
|------|----------|------------|------------------|
| Tavily 搜索 | 1000次/月 | ~$5/1000次 | ~240 次 |
| AI Token | 无 | ~$3/百万 token | < 1000 token (~$0.003) |

**一次全量采集总成本：约 $1-2**（主要是 Tavily 搜索费用）

---

## 自定义关键词

如需修改搜索关键词，编辑 `scripts/keyword-search.py` 中的 `KEYWORDS` 字典即可。
格式为：`{"类别名": ["关键词1", "关键词2", ...]}`
