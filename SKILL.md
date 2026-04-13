---
name: site-info-collector
description: "站点基础信息采集。用户说「采集」即自动执行：关键词搜索 → 导航站子站提取 → 逐站采集联系方式 → 输出 JSON 文件推送到 Telegram。"
metadata:
  requires:
    tools: [exec]
---

# 站点基础信息采集 Skill

用户下达采集指令（如「开始采集」「去采集」「采集导航站」），自动调用 Python 脚本完成全流程，不消耗 AI token。

## 触发指令

当用户消息包含「采集」「开始采集」「去采集」「跑采集」等关键词时，立即用 `exec` 调用采集脚本，不要反问用户。

## 执行命令

**日常采集（每日执行，用缓存 URL，不消耗搜索 API）：**
```bash
exec: python3 skills/site-info-collector/scripts/site-collector.py --use-cache --output /tmp/site-info-$(date +%Y%m%d-%H%M%S).json
```

**全量搜索+采集（首次或每周一次，消耗 Tavily API）：**
```bash
exec: python3 skills/site-info-collector/scripts/site-collector.py --search --output /tmp/site-info-$(date +%Y%m%d-%H%M%S).json
```

**指定类别搜索+采集：**
```bash
# 采集导航站
exec: python3 skills/site-info-collector/scripts/site-collector.py --search --category 导航 --output /tmp/site-info-nav.json

# 采集小说站 / 视频站 / 漫画站
exec: python3 skills/site-info-collector/scripts/site-collector.py --search --category 小说 --output /tmp/site-info-novel.json
exec: python3 skills/site-info-collector/scripts/site-collector.py --search --category 视频 --output /tmp/site-info-video.json
exec: python3 skills/site-info-collector/scripts/site-collector.py --search --category 漫画 --output /tmp/site-info-comic.json
```

**手动指定 URL（用户给了具体网址）：**

先把 URL 写入文件，再调用脚本：
```bash
exec: echo "https://site1.com\nhttps://site2.com" > /tmp/manual-urls.txt && python3 skills/site-info-collector/scripts/site-collector.py --urls /tmp/manual-urls.txt --output /tmp/site-info-manual.json
```

**重要**：
- 收到采集指令后直接 exec 执行，不要反问用户
- 脚本会自动搜索关键词、采集站点、生成 JSON、推送到 Telegram
- 回复用户「采集已启动，完成后会自动推送结果」即可
- TG_BOT_TOKEN 和 TG_CHAT_ID 从环境变量读取，无需传参

---

## 架构说明

整个采集流程由 Python 脚本完成，不走 AI 模型：

```
site-collector.py（主脚本）
  ├── 调用 keyword-search.py（Tavily API 搜索关键词）
  ├── 调用 nav-extractor.py（Playwright 渲染导航站提取子站）
  ├── requests 并发抓取页面 HTML
  ├── 正则提取联系方式（email/TG/QQ/微信/Twitter 等）
  ├── 去重 + 脱敏
  ├── 输出 JSON 文件
  └── TG Bot API 推送结果
```

AI 仅负责理解用户指令并调用 exec，实际采集零 token 消耗。

---

## 采集规则

### 扫描页面

对每个站点扫描以下页面：

```
/, /contact, /contact-us, /about, /about-us,
/support, /business, /advertise, /help,
/ad, /ads, /link, /links, /cooperation,
/partner, /partners,
/友链, /广告, /合作, /联系我们, /关于我们, /商务合作
```

### 提取联系方式类型

| type | 匹配规则 |
|------|----------|
| email | 邮箱地址，过滤平台域名 |
| telegram | `t.me/xxx`、`telegram.me/xxx` |
| whatsapp | `wa.me/xxx`、`api.whatsapp.com/send?phone=xxx` |
| twitter | `twitter.com/xxx`、`x.com/xxx` |
| facebook | `facebook.com/xxx`、`fb.com/xxx` |
| instagram | `instagram.com/xxx` |
| qq | QQ号（QQ/qq 关键词旁 5-12 位数字） |
| wechat | 微信号（微信/WeChat 关键词旁的 ID） |
| phone | 中国手机号（1[3-9]开头 11 位）、国际格式 |
| skype | Skype ID |
| form | 联系表单 URL |

### 脱敏规则

| 类型 | 规则 | 示例 |
|------|------|------|
| email | 首尾保留，中间*** | `admin@qq.com` → `a***n@qq.com` |
| phone | 前3后4保留 | `13812345678` → `138****5678` |
| qq | 前2后2保留 | `123456789` → `12***89` |
| wechat | 前2后2保留 | `wxid_abc123` → `wx***23` |
| 其他 | 不脱敏（公开信息） | 原值 |

### 去重规则

- 站点级：同一域名只采集一次
- 联系方式级：按 type + value（忽略大小写）去重

---

## 输出格式

### JSON 结构

```json
[
  {
    "site_name": "示例网站",
    "site_name_safe": "示例网站",
    "site_url": "https://example.com",
    "contacts": [
      {
        "type": "email",
        "value": "admin@example.com",
        "value_safe": "a***n@example.com",
        "source_page": "https://example.com/contact"
      }
    ],
    "status": "success",
    "failure_reason": ""
  }
]
```

### status 值

| status | 含义 |
|--------|------|
| success | 提取到至少一条联系方式 |
| partial | 页面可访问但未找到联系方式 |
| failed | 所有页面均不可访问 |

### 采集报告

脚本完成后自动推送到 Telegram：
- 统计摘要（成功/部分/失败/联系方式数量）
- 失败归因（按 timeout/403/connection_error 分组）
- 复盘建议
- JSON 结果文件（作为文档附件）

---

## 边界说明

- 仅采集公开可见信息
- 不登录、不绕过反爬
- 微信二维码不识别
- 遵守 robots.txt
