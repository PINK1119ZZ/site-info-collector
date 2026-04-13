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
- 创建独立 Agent `site-collector`（不影响现有 Agent 和 Bot）
- 安装 Python 依赖 + Chromium 浏览器引擎
- 绑定 TG Bot 到专属 Agent
- 写入环境变量（systemd / LaunchAgent）
- 配置 exec 白名单（仅限采集脚本）
- 写入触发规则到 Agent 专属 AGENTS.md
- 重启 Gateway

## 使用方式

安装完成后，在 Telegram 对 Bot 发消息：

| 指令 | 说明 | API 消耗 |
|------|------|----------|
| `采集` | 全量采集所有类别（首次自动搜索，之后用缓存） | 有缓存：零；无缓存：~240 次 Tavily |
| `搜新的` | 强制重新搜索发现新站点 | ~240 次 Tavily |
| `帮助` | 查看使用说明和当前状态 | 零 |

每次采集自动跑全部 4 类（导航+小说+视频+漫画，共 239 个关键词），只输出**新增**的联系方式（通过 history.json 去重）。

Bot 自动执行全流程，完成后推送：采集报告（含失败归因+复盘建议）+ JSON 结果文件。

## 费用估算

| 项目 | 免费额度 | 每次全量采集 |
|------|----------|-------------|
| Tavily 搜索 | 1000 次/月 | ~240 次 |
| AI Token | — | < 1000 token（~$0.003） |

日常采集（`采集`）使用缓存，零 API 消耗。说「搜新的」才消耗 Tavily 额度。

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

- **完全隔离**：创建独立 Agent `site-collector`，有自己的 workspace、TG Bot 绑定、exec 白名单
- 不影响现有 Agent、Bot、触发规则
- 环境变量写入独立 systemd override 文件
- 卸载只需 `openclaw agents delete site-collector`
