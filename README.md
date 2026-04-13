# 站点基础信息采集 Skill

OpenClaw Skill — 自动采集网站联系方式（email、Telegram、QQ、微信、Twitter 等），输出标准化 JSON，结果推送到 Telegram。

## 工作原理

```
用户在 TG 发「采集」→ OpenClaw 理解指令 → exec 调用 Python 爬虫 → 结果推送回 TG
```

- 采集由 Python 爬虫完成，不走 AI 模型，零 token 消耗
- AI 仅负责理解用户指令（每次 < 1000 token，约 $0.003）
- 支持 4 类关键词：导航站、小说站、视频站、漫画站（共 ~240 个关键词）

## 一键安装

SSH 到你的 OpenClaw 所在 VPS，执行：

```bash
git clone https://github.com/PINK1119ZZ/site-info-collector.git
cd site-info-collector
bash setup.sh
```

安装向导会引导你输入 3 个配置：

| 配置项 | 说明 | 获取方式 |
|--------|------|----------|
| Tavily API Key | 搜索新站点用 | [tavily.com](https://tavily.com) 注册，Dashboard → API Keys |
| TG Bot Token | 接收指令+推送结果 | Telegram 找 @BotFather，发 /newbot |
| TG Chat ID | 推送结果给谁 | Telegram 找 @userinfobot，发任意消息 |

安装脚本会自动完成：
- 安装 Python 依赖 + Chromium 浏览器引擎
- 写入环境变量（systemd / LaunchAgent）
- 绑定 TG Bot（独立帐号 `collector`，不影响现有 Bot）
- 配置 exec 白名单（免审批执行脚本）
- 合并触发规则到 AGENTS.md
- 重启 Gateway

## 使用方式

安装完成后，在 Telegram 对 Bot 发消息：

| 指令 | 说明 | API 消耗 |
|------|------|----------|
| `采集` | 日常模式，用缓存 URL | 零（不调 Tavily） |
| `采集导航站` | 搜索导航类新站点 | ~32 次 Tavily |
| `采集小说站` | 搜索小说类新站点 | ~80 次 Tavily |
| `采集视频站` | 搜索视频类新站点 | ~60 次 Tavily |
| `采集漫画站` | 搜索漫画类新站点 | ~60 次 Tavily |
| `搜新的` | 全量搜索所有类别 | ~240 次 Tavily |

Bot 自动执行全流程，完成后推送：采集统计报告 + JSON 结果文件。

## 费用估算

| 项目 | 免费额度 | 每次全量采集 |
|------|----------|-------------|
| Tavily 搜索 | 1000 次/月 | ~240 次 |
| AI Token | — | < 1000 token（~$0.003） |

日常采集（`采集`）使用缓存，零 API 消耗。全量搜索建议每周一次。

## 采集内容

### 联系方式类型

email · telegram · whatsapp · twitter · facebook · instagram · qq · wechat · phone · skype · form

### 输出格式

```json
[
  {
    "site_name": "示例网站",
    "site_url": "https://example.com",
    "contacts": [
      {
        "type": "email",
        "value": "admin@example.com",
        "value_safe": "a***n@example.com",
        "source_page": "https://example.com/contact"
      }
    ],
    "status": "success"
  }
]
```

### 脱敏规则

| 类型 | 示例 |
|------|------|
| email | `admin@qq.com` → `a***n@qq.com` |
| phone | `13812345678` → `138****5678` |
| qq | `123456789` → `12***89` |
| wechat | `wxid_abc123` → `wx***23` |
| 其他 | 不脱敏（公开信息） |

## 文件结构

```
site-info-collector/
├── README.md              # 本文件
├── SKILL.md               # OpenClaw Skill 定义
├── DEPLOY.md              # 详细部署指南
├── setup.sh               # 一键安装脚本
├── AGENTS.md.patch        # 触发规则（自动合并）
└── scripts/
    ├── site-collector.py   # 主采集脚本（Python 爬虫）
    ├── keyword-search.py   # 关键词搜索（Tavily API）
    └── nav-extractor.py    # 导航站子站提取（Playwright）
```

## 环境要求

- OpenClaw 2026.3.x+
- Python 3.9+
- Linux / macOS

## 兼容性

- 支持已有多个 Agent / Bot 的环境，不会影响现有服务
- TG Bot 使用独立帐号名 `collector`
- 环境变量写入独立 systemd override 文件
- exec 白名单仅添加采集脚本条目
