#!/usr/bin/env python3
"""
导航站子站链接提取脚本 — 用 Playwright 渲染 JS 页面，提取所有外部链接。

用法：
  python nav-extractor.py https://fuliba123.com
  python nav-extractor.py https://fuliba123.com --output sub-urls.txt
  python nav-extractor.py urls.txt              # 批量处理多个导航站

输出：去重后的子站 URL 列表，可直接喂给 site-info-collector Skill。
"""

import argparse
import sys
import os
from urllib.parse import urlparse

try:
    from playwright.sync_api import sync_playwright
except ImportError:
    print("需要安装 playwright: pip3 install playwright && python3 -m playwright install chromium", file=sys.stderr)
    sys.exit(1)

# 排除的域名
EXCLUDE_DOMAINS = {
    "google.com", "google.com.hk", "google.co.jp", "googleapis.com", "gstatic.com",
    "bing.com", "baidu.com", "sogou.com", "so.com", "360.cn",
    "youtube.com", "wikipedia.org", "wikimedia.org",
    "zhihu.com", "weibo.com", "bilibili.com", "douban.com",
    "reddit.com", "quora.com",
    "twitter.com", "x.com", "facebook.com", "instagram.com",
    "tiktok.com", "douyin.com", "xiaohongshu.com",
    "github.com", "stackoverflow.com",
    "apple.com", "microsoft.com", "amazon.com",
    "w3.org", "schema.org", "jquery.com", "cloudflare.com",
    "cdn.jsdelivr.net", "unpkg.com", "fonts.googleapis.com",
}


def is_excluded(domain):
    domain = domain.lower().lstrip("www.")
    for exc in EXCLUDE_DOMAINS:
        if domain == exc or domain.endswith("." + exc):
            return True
    return False


def extract_links(url, timeout=30000):
    """用 Playwright 打开页面，等 JS 渲染完，提取所有外部链接"""
    source_domain = urlparse(url).netloc.lower().lstrip("www.")
    links = set()

    try:
        with sync_playwright() as p:
            browser = p.chromium.launch(headless=True)
            page = browser.new_page(
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            )
            page.goto(url, wait_until="networkidle", timeout=timeout)

            # 提取所有 a[href] 链接
            anchors = page.query_selector_all("a[href]")
            for a in anchors:
                href = a.get_attribute("href")
                if not href or not href.startswith("http") or "@" in href:
                    continue
                parsed = urlparse(href)
                domain = parsed.netloc.lower().lstrip("www.")
                # 排除自身域名、排除列表中的域名
                if domain and domain != source_domain and not is_excluded(domain):
                    base = f"{parsed.scheme}://{parsed.netloc}"
                    links.add(base)

            browser.close()
    except Exception as e:
        print(f"  提取失败 [{url}]: {e}", file=sys.stderr)

    return sorted(links)


def main():
    parser = argparse.ArgumentParser(description="导航站子站链接提取")
    parser.add_argument("input", help="导航站 URL 或包含 URL 列表的文件")
    parser.add_argument("--output", "-o", help="输出文件路径（默认 stdout）")
    parser.add_argument("--timeout", type=int, default=30000, help="页面加载超时(ms)")
    args = parser.parse_args()

    # 判断输入是 URL 还是文件
    if args.input.startswith("http"):
        urls = [args.input]
    elif os.path.isfile(args.input):
        with open(args.input) as f:
            urls = [line.strip() for line in f if line.strip().startswith("http")]
    else:
        print(f"无效输入: {args.input}", file=sys.stderr)
        sys.exit(1)

    all_links = set()
    for url in urls:
        print(f"提取: {url}", file=sys.stderr)
        links = extract_links(url, args.timeout)
        print(f"  发现 {len(links)} 个子站链接", file=sys.stderr)
        all_links.update(links)

    all_links = sorted(all_links)
    print(f"\n共 {len(all_links)} 个去重后的子站", file=sys.stderr)

    output_text = "\n".join(all_links)
    if args.output:
        with open(args.output, "w") as f:
            f.write(output_text + "\n")
        print(f"已写入 {args.output}", file=sys.stderr)
    else:
        print(output_text)


if __name__ == "__main__":
    main()
