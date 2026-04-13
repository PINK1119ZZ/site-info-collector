#!/usr/bin/env python3
"""
站点信息采集主脚本 — 全 Python 实现，不走 AI。

用法：
  # 从 URL 文件采集
  python site-collector.py --urls urls.txt --output results.json

  # 全量：关键词搜索 + 采集
  python site-collector.py --search --output results.json

  # 指定类别
  python site-collector.py --search --category 导航 --output results.json

  # 推送到 Telegram
  python site-collector.py --urls urls.txt --output results.json --tg-token BOT_TOKEN --tg-chat CHAT_ID

环境变量：
  TAVILY_API_KEY  — Tavily 搜索 API Key
  TG_BOT_TOKEN    — Telegram Bot Token（可选）
  TG_CHAT_ID      — Telegram Chat ID（可选）
"""

import argparse
import json
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from urllib.parse import urlparse, urljoin
from datetime import datetime

try:
    import requests
except ImportError:
    print("需要安装 requests: pip3 install requests", file=sys.stderr)
    sys.exit(1)

try:
    from bs4 import BeautifulSoup
except ImportError:
    print("需要安装 beautifulsoup4: pip3 install beautifulsoup4", file=sys.stderr)
    sys.exit(1)

# ── 正则 ──

EMAIL_RE = re.compile(
    r'\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b'
)
EMAIL_BLACKLIST = {
    "example.com", "sentry.io", "schema.org", "w3.org",
    "wix.com", "wordpress.com", "squarespace.com", "shopify.com",
    "google.com", "jquery.com", "bootstrap.com", "cloudflare.com",
    "gravatar.com", "googleapis.com", "gstatic.com", "baidu.com",
    "qq.com", "163.com", "sina.com", "126.com",
}

TELEGRAM_RE = re.compile(
    r'(?:https?://)?(?:t\.me|telegram\.me)/([a-zA-Z0-9_]{5,})',
    re.IGNORECASE
)

WHATSAPP_RE = re.compile(
    r'(?:https?://)?(?:wa\.me|api\.whatsapp\.com/send\?phone=)[\s]*(\+?[0-9]{7,15})',
    re.IGNORECASE
)

TWITTER_RE = re.compile(
    r'(?:https?://)?(?:twitter\.com|x\.com)/([a-zA-Z0-9_]{1,15})',
    re.IGNORECASE
)

FACEBOOK_RE = re.compile(
    r'(?:https?://)?(?:www\.)?(?:facebook\.com|fb\.com|fb\.me)/([a-zA-Z0-9._\-]+)',
    re.IGNORECASE
)

INSTAGRAM_RE = re.compile(
    r'(?:https?://)?(?:www\.)?instagram\.com/([a-zA-Z0-9._]+)',
    re.IGNORECASE
)

QQ_RE = re.compile(
    r'(?:QQ|qq)\s*[:：]?\s*(\d{5,12})'
)

WECHAT_RE = re.compile(
    r'(?:微信|WeChat|wechat)\s*[:：]\s*([a-zA-Z][a-zA-Z0-9_\-]{5,19})',
    re.IGNORECASE
)

PHONE_RE = re.compile(
    r'(?<!\d)(?:\+?86[-\s]?)?1[3-9]\d{9}(?!\d)'           # 中国手机号（严格11位）
    r'|(?<!\d)\+\d{1,3}[-.\s]\d{2,4}[-.\s]\d{4,8}(?!\d)'  # 国际格式（必须有分隔符）
)

SKYPE_RE = re.compile(
    r'(?:skype)\s*[:：]?\s*([a-zA-Z0-9._\-]+)',
    re.IGNORECASE
)

# 排除的社交/工具路径
SOCIAL_EXCLUDE = {"login", "signup", "register", "share", "sharer", "intent", "hashtag",
                  "home", "settings", "help", "about", "legal", "privacy", "terms",
                  "policies", "p", "watch", "search", "explore", "favicon.ico"}

# ── 扫描路径 ──

SCAN_PATHS = [
    "/", "/contact", "/contact-us", "/about", "/about-us",
    "/support", "/business", "/advertise", "/help",
    "/ad", "/ads", "/link", "/links", "/cooperation",
    "/partner", "/partners",
    "/%E5%8F%8B%E9%93%BE",       # /友链
    "/%E5%B9%BF%E5%91%8A",       # /广告
    "/%E5%90%88%E4%BD%9C",       # /合作
    "/%E8%81%94%E7%B3%BB%E6%88%91%E4%BB%AC",  # /联系我们
    "/%E5%85%B3%E4%BA%8E%E6%88%91%E4%BB%AC",  # /关于我们
    "/%E5%95%86%E5%8A%A1%E5%90%88%E4%BD%9C",  # /商务合作
]

# ── 脱敏 ──

def mask_value(contact_type, value):
    if contact_type == "email":
        parts = value.split("@")
        if len(parts) != 2:
            return value
        local, domain = parts
        if len(local) <= 2:
            return local[0] + "***@" + domain
        return local[0] + "***" + local[-1] + "@" + domain
    elif contact_type == "phone":
        digits = re.sub(r'\D', '', value)
        if len(digits) >= 7:
            return digits[:3] + "****" + digits[-4:]
        return "****"
    elif contact_type == "qq":
        if len(value) <= 4:
            return value[:1] + "***"
        return value[:2] + "***" + value[-2:]
    elif contact_type == "wechat":
        if len(value) <= 4:
            return value[:1] + "***"
        return value[:2] + "***" + value[-2:]
    else:
        return value


# ── 提取联系方式 ──

def extract_contacts(html, page_url):
    """从 HTML 中提取所有联系方式"""
    contacts = []
    text = html if isinstance(html, str) else ""

    # Email
    for m in EMAIL_RE.finditer(text):
        email = m.group(0).lower()
        domain = email.split("@")[1]
        if domain not in EMAIL_BLACKLIST:
            contacts.append({"type": "email", "value": email, "source_page": page_url})

    # Telegram
    for m in TELEGRAM_RE.finditer(text):
        handle = m.group(1)
        if handle.lower() not in SOCIAL_EXCLUDE:
            contacts.append({"type": "telegram", "value": f"@{handle}", "source_page": page_url})

    # WhatsApp
    for m in WHATSAPP_RE.finditer(text):
        phone = m.group(1)
        contacts.append({"type": "whatsapp", "value": phone, "source_page": page_url})

    # Twitter
    for m in TWITTER_RE.finditer(text):
        handle = m.group(1)
        if handle.lower() not in SOCIAL_EXCLUDE:
            contacts.append({"type": "twitter", "value": f"@{handle}", "source_page": page_url})

    # Facebook
    for m in FACEBOOK_RE.finditer(text):
        page = m.group(1)
        if page.lower() not in SOCIAL_EXCLUDE:
            contacts.append({"type": "facebook", "value": page, "source_page": page_url})

    # Instagram
    for m in INSTAGRAM_RE.finditer(text):
        handle = m.group(1)
        if handle.lower() not in SOCIAL_EXCLUDE:
            contacts.append({"type": "instagram", "value": f"@{handle}", "source_page": page_url})

    # QQ
    for m in QQ_RE.finditer(text):
        qq = m.group(1)
        contacts.append({"type": "qq", "value": qq, "source_page": page_url})

    # WeChat
    for m in WECHAT_RE.finditer(text):
        wechat = m.group(1)
        contacts.append({"type": "wechat", "value": wechat, "source_page": page_url})

    # Phone
    for m in PHONE_RE.finditer(text):
        phone = m.group(0)
        contacts.append({"type": "phone", "value": phone, "source_page": page_url})

    # Skype
    for m in SKYPE_RE.finditer(text):
        skype = m.group(1)
        contacts.append({"type": "skype", "value": skype, "source_page": page_url})

    # Form
    try:
        soup = BeautifulSoup(text, "html.parser")
        for a in soup.find_all("a", href=True):
            href = a["href"].lower()
            if any(kw in href for kw in ["contact", "feedback", "form", "support"]):
                full_url = urljoin(page_url, a["href"])
                contacts.append({"type": "form", "value": full_url, "source_page": page_url})
    except:
        pass

    return contacts


def extract_site_name(html):
    """从 HTML 中提取站点名称"""
    try:
        soup = BeautifulSoup(html, "html.parser")
        # og:site_name
        og = soup.find("meta", property="og:site_name")
        if og and og.get("content"):
            return og["content"].strip()
        # title
        title = soup.find("title")
        if title and title.string:
            name = title.string.strip()
            # 去掉常见分隔符后面的部分
            for sep in [" - ", " | ", " – ", " — ", " :: "]:
                if sep in name:
                    name = name.split(sep)[0].strip()
            return name
    except:
        pass
    return ""


# ── 采集单个站点 ──

def fetch_page(url, timeout=15):
    """抓取页面 HTML"""
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        resp = requests.get(url, headers=headers, timeout=timeout, allow_redirects=True)
        resp.encoding = resp.apparent_encoding or "utf-8"
        return resp.text, resp.status_code
    except requests.exceptions.Timeout:
        return None, "timeout"
    except requests.exceptions.ConnectionError:
        return None, "connection_error"
    except Exception as e:
        return None, str(e)


def collect_site(site_url, timeout=15):
    """采集单个站点的所有信息"""
    all_contacts = []
    site_name = ""
    any_success = False
    last_error = ""

    for path in SCAN_PATHS:
        page_url = site_url.rstrip("/") + path
        html, status = fetch_page(page_url, timeout)

        if html is None:
            last_error = status
            continue

        if isinstance(status, int) and status >= 400:
            last_error = f"HTTP {status}"
            continue

        any_success = True

        # 提取站名（只从首页提取）
        if path == "/" and not site_name:
            site_name = extract_site_name(html)

        # 提取联系方式
        contacts = extract_contacts(html, page_url)
        all_contacts.extend(contacts)

    # 去重
    seen = set()
    deduped = []
    for c in all_contacts:
        key = (c["type"], c["value"].lower().strip())
        if key not in seen:
            seen.add(key)
            c["value_safe"] = mask_value(c["type"], c["value"])
            deduped.append(c)

    # 状态判断
    if not any_success:
        status = "failed"
        failure_reason = f"所有页面均不可访问: {last_error}"
    elif not deduped:
        status = "partial"
        failure_reason = "页面可访问但未找到联系方式"
    else:
        status = "success"
        failure_reason = ""

    return {
        "site_name": site_name,
        "site_name_safe": site_name,
        "site_url": site_url,
        "contacts": deduped,
        "status": status,
        "failure_reason": failure_reason,
    }


# ── 批量采集 ──

def collect_batch(urls, max_workers=15, timeout=15, progress_callback=None):
    """并发采集多个站点"""
    results = []
    total = len(urls)

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        future_to_url = {executor.submit(collect_site, url, timeout): url for url in urls}

        for i, future in enumerate(as_completed(future_to_url), 1):
            url = future_to_url[future]
            try:
                result = future.result()
                results.append(result)
                status_icon = {"success": "✅", "partial": "⚠️", "failed": "❌"}.get(result["status"], "?")
                contacts_count = len(result["contacts"])
                print(f"  [{i}/{total}] {status_icon} {url} — {contacts_count} 条联系方式", file=sys.stderr)
            except Exception as e:
                print(f"  [{i}/{total}] ❌ {url} — 异常: {e}", file=sys.stderr)
                results.append({
                    "site_name": "",
                    "site_name_safe": "",
                    "site_url": url,
                    "contacts": [],
                    "status": "failed",
                    "failure_reason": f"采集异常: {str(e)}",
                })

            if progress_callback and i % 50 == 0:
                progress_callback(i, total)

    return results


# ── 生成报告 ──

def generate_report(results):
    """生成采集统计报告"""
    total = len(results)
    success = sum(1 for r in results if r["status"] == "success")
    partial = sum(1 for r in results if r["status"] == "partial")
    failed = sum(1 for r in results if r["status"] == "failed")
    contacts = sum(len(r["contacts"]) for r in results)

    report = f"""📊 采集报告

总计: {total} 个站点
✅ 成功: {success} 个（提取到联系方式）
⚠️ 部分: {partial} 个（页面可访问但未找到联系方式）
❌ 失败: {failed} 个（页面不可访问）
📇 联系方式: 共 {contacts} 条"""

    # 失败归因
    if failed > 0:
        failure_reasons = {}
        for r in results:
            if r["status"] == "failed":
                reason = r.get("failure_reason", "未知")
                # 简化原因
                if "timeout" in reason:
                    key = "timeout"
                elif "connection_error" in reason:
                    key = "connection_error"
                elif "HTTP 403" in reason:
                    key = "HTTP 403"
                elif "HTTP 5" in reason:
                    key = "HTTP 5xx"
                else:
                    key = reason[:30]
                failure_reasons.setdefault(key, []).append(r["site_url"])

        report += "\n\n--- 失败归因 ---"
        for reason, sites in failure_reasons.items():
            site_list = ", ".join(s.replace("https://", "").replace("http://", "") for s in sites[:10])
            if len(sites) > 10:
                site_list += f" ...等{len(sites)}个"
            report += f"\n• {reason} ({len(sites)}个): {site_list}"

    # 复盘建议
    if failed > 0 or partial > 0:
        report += "\n\n--- 复盘建议 ---"
        if any("timeout" in r.get("failure_reason", "") for r in results if r["status"] == "failed"):
            report += "\n• timeout → 建议稍后重试或增加超时时间"
        if any("403" in r.get("failure_reason", "") for r in results if r["status"] == "failed"):
            report += "\n• HTTP 403 → 可能有反爬机制，建议手动访问确认"
        if any("connection_error" in r.get("failure_reason", "") for r in results if r["status"] == "failed"):
            report += "\n• connection_error → 站点可能已下线，建议从列表移除"
        if partial > 0:
            report += "\n• 部分成功 → 联系方式可能以图片/二维码形式展示，需人工确认"

    return report


# ── Telegram 推送 ──

def send_telegram(token, chat_id, text=None, file_path=None):
    """发送 Telegram 消息或文件"""
    if text:
        # 截断过长消息
        if len(text) > 4000:
            text = text[:4000] + "\n\n...（已截断）"
        requests.post(
            f"https://api.telegram.org/bot{token}/sendMessage",
            data={"chat_id": chat_id, "text": text},
            timeout=30,
        )

    if file_path and os.path.exists(file_path):
        with open(file_path, "rb") as f:
            requests.post(
                f"https://api.telegram.org/bot{token}/sendDocument",
                data={"chat_id": chat_id, "caption": "站点基础信息采集结果"},
                files={"document": f},
                timeout=60,
            )


# ── 主流程 ──

def main():
    parser = argparse.ArgumentParser(description="站点信息全自动采集（纯 Python）")
    parser.add_argument("--urls", help="URL 列表文件")
    parser.add_argument("--search", action="store_true", help="执行关键词搜索获取 URL")
    parser.add_argument("--category", help="搜索类别: 小说/视频/漫画/导航")
    parser.add_argument("--max-per-keyword", type=int, default=5, help="每个关键词最多取几个结果")
    parser.add_argument("--nav-extract", action="store_true", default=True, help="对导航站提取子站")
    parser.add_argument("--output", "-o", required=True, help="JSON 输出文件路径")
    parser.add_argument("--workers", type=int, default=15, help="并发线程数")
    parser.add_argument("--timeout", type=int, default=15, help="页面请求超时(秒)")
    parser.add_argument("--tg-token", help="Telegram Bot Token")
    parser.add_argument("--tg-chat", help="Telegram Chat ID")
    parser.add_argument("--engine", default="tavily", help="搜索引擎")
    parser.add_argument("--url-cache", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "url-cache.txt"),
                        help="URL 缓存文件路径（搜索结果会追加到此文件，下次可跳过搜索直接采集）")
    parser.add_argument("--use-cache", action="store_true", help="使用缓存的 URL 列表，跳过搜索（日常采集模式）")
    args = parser.parse_args()

    # TG 参数也可从环境变量获取
    tg_token = args.tg_token or os.environ.get("TG_BOT_TOKEN")
    tg_chat = args.tg_chat or os.environ.get("TG_CHAT_ID")

    script_dir = os.path.dirname(os.path.abspath(__file__))
    all_urls = set()

    # 确保缓存目录存在
    cache_dir = os.path.dirname(args.url_cache)
    if cache_dir:
        os.makedirs(cache_dir, exist_ok=True)

    # ── 第一步：获取 URL ──

    # 读取缓存 URL
    if args.use_cache:
        if os.path.exists(args.url_cache):
            print(f"[1/4] 读取缓存 URL 列表...", file=sys.stderr)
            with open(args.url_cache) as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("http"):
                        all_urls.add(line)
            print(f"  缓存中共 {len(all_urls)} 个站点", file=sys.stderr)
            if not args.search:
                print(f"  日常采集模式，跳过搜索", file=sys.stderr)
        else:
            print(f"[1/4] 缓存文件不存在，转为搜索模式", file=sys.stderr)
            args.search = True

    if args.urls:
        print(f"[1/4] 读取 URL 文件: {args.urls}", file=sys.stderr)
        with open(args.urls) as f:
            for line in f:
                line = line.strip()
                if line.startswith("http"):
                    all_urls.add(line)
        print(f"  读取到 {len(all_urls)} 个站点", file=sys.stderr)

    if args.search:
        print("[1/4] 关键词搜索...", file=sys.stderr)
        import subprocess
        search_cmd = [
            sys.executable, os.path.join(script_dir, "keyword-search.py"),
            "--engine", args.engine,
            "--max-per-keyword", str(args.max_per_keyword),
            "--output", "/tmp/search-urls.txt",
        ]
        if args.category:
            search_cmd.extend(["--category", args.category])
        subprocess.run(search_cmd, check=True)
        with open("/tmp/search-urls.txt") as f:
            for line in f:
                line = line.strip()
                if line.startswith("http"):
                    all_urls.add(line)
        print(f"  搜索后共 {len(all_urls)} 个站点", file=sys.stderr)

    if not all_urls:
        print("没有 URL 可采集", file=sys.stderr)
        sys.exit(1)

    # ── 第二步：导航站提取 ──
    if args.nav_extract:
        print("[2/4] 检查导航站...", file=sys.stderr)
        nav_keywords = ["导航", "nav", "daohang", "dh.", "hao123", "fuliba", "114", "大全", "索引"]
        nav_candidates = [u for u in all_urls if any(kw in u.lower() for kw in nav_keywords)]
        if nav_candidates:
            print(f"  发现 {len(nav_candidates)} 个疑似导航站", file=sys.stderr)
            nav_file = "/tmp/nav-candidates.txt"
            with open(nav_file, "w") as f:
                f.write("\n".join(nav_candidates) + "\n")
            try:
                import subprocess
                result = subprocess.run(
                    [sys.executable, os.path.join(script_dir, "nav-extractor.py"),
                     nav_file, "--output", "/tmp/nav-urls.txt"],
                    capture_output=True, text=True, timeout=300,
                )
                if os.path.exists("/tmp/nav-urls.txt"):
                    with open("/tmp/nav-urls.txt") as f:
                        for line in f:
                            line = line.strip()
                            if line.startswith("http"):
                                all_urls.add(line)
                print(f"  合并后共 {len(all_urls)} 个站点", file=sys.stderr)
            except Exception as e:
                print(f"  导航站提取失败: {e}", file=sys.stderr)
        else:
            print("  未发现导航站", file=sys.stderr)

    # 保存 URL 缓存（供日后 --use-cache 使用）
    if args.search or args.urls:
        existing_cache = set()
        if os.path.exists(args.url_cache):
            with open(args.url_cache) as f:
                existing_cache = {line.strip() for line in f if line.strip().startswith("http")}
        new_urls = all_urls - existing_cache
        if new_urls:
            with open(args.url_cache, "a") as f:
                for u in sorted(new_urls):
                    f.write(u + "\n")
            print(f"  💾 {len(new_urls)} 个新 URL 已追加到缓存（总计 {len(existing_cache | all_urls)}）", file=sys.stderr)

    urls_list = sorted(all_urls)
    print(f"\n[3/4] 开始采集 {len(urls_list)} 个站点（{args.workers} 并发）...", file=sys.stderr)

    # 发送开始通知
    if tg_token and tg_chat:
        send_telegram(tg_token, tg_chat,
                      text=f"🚀 开始采集 {len(urls_list)} 个站点...\n预计耗时 {len(urls_list) * 2 // 60} 分钟")

    # 进度回调
    def on_progress(done, total):
        if tg_token and tg_chat:
            send_telegram(tg_token, tg_chat,
                          text=f"⏳ 采集进度: {done}/{total} ({done*100//total}%)")

    # ── 第三步：批量采集 ──
    start_time = time.time()
    results = collect_batch(urls_list, max_workers=args.workers, timeout=args.timeout,
                           progress_callback=on_progress)
    elapsed = time.time() - start_time

    # ── 第四步：输出 ──
    print(f"\n[4/4] 输出结果...", file=sys.stderr)

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)

    report = generate_report(results)
    report += f"\n\n⏱ 耗时: {elapsed:.0f} 秒 ({elapsed/60:.1f} 分钟)"
    print(f"\n{report}", file=sys.stderr)
    print(f"\n结果文件: {args.output}", file=sys.stderr)

    # 推送到 Telegram
    if tg_token and tg_chat:
        send_telegram(tg_token, tg_chat, text=report)
        send_telegram(tg_token, tg_chat, file_path=args.output)
        print("已推送到 Telegram", file=sys.stderr)


if __name__ == "__main__":
    main()
