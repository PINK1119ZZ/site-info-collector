#!/usr/bin/env python3
"""
关键词搜索脚本 — 用搜索引擎搜关键词，输出去重后的站点 URL 列表。
这一步不走 AI，避免模型安全策略拒绝。

用法：
  python keyword-search.py                          # 搜全部关键词
  python keyword-search.py --category 导航           # 只搜导航类
  python keyword-search.py --keyword "成人导航"       # 搜单个关键词
  python keyword-search.py --max-per-keyword 5       # 每个关键词最多取5个结果
  python keyword-search.py --output urls.txt         # 输出到文件

输出：每行一个 URL，去重后的站点列表，可直接喂给 site-info-collector Skill。
"""

import argparse
import json
import os
import re
import sys
import time
from urllib.parse import urlparse

try:
    import requests
except ImportError:
    print("需要安装 requests: pip install requests", file=sys.stderr)
    sys.exit(1)

# ── 关键词库 ──

KEYWORDS = {
    "小说": [
        "黄文", "小黄文", "肉文", "H文", "高H", "成人小说", "情色小说", "色情小说",
        "18禁小说", "18X小说", "成人文学", "情欲小说", "欲望小说", "淫文", "辣文", "禁文",
        "成人故事", "情色故事", "色情故事", "成人连载", "色情短篇", "色情长篇",
        "激情小说", "艳情小说", "香艳小说", "官能小说", "露骨小说", "性描写小说",
        "性爱小说", "SM小说", "调教小说", "催眠文", "催眠调教", "群交文", "NP文",
        "后宫黄文", "双修文", "修仙肉文", "成人同人", "色情同人", "18禁同人",
        "耽美肉文", "百合H文", "BL黄文", "GL黄文", "乱伦文", "母子文", "父女文",
        "兄妹文", "姐弟文", "禁忌乱伦", "禁断之恋文", "强暴小说", "凌辱小说",
        "轮奸文", "下药文", "迷奸文", "性奴文", "主奴文", "捆绑文", "皮鞭文",
        "人妻文", "绿帽文", "出轨文", "换妻文", "校园H文", "师生H文",
        "制服诱惑文", "办公室H文", "裸聊小说", "约炮小说", "淫荡小说", "淫乱文",
        "淫欲小说", "肉欲小说", "淫妻文", "艳文", "春文", "成人向轻小说", "擦边小说",
    ],
    "视频": [
        "成人视频", "成人影片", "成人影像", "成人片", "情色影片", "情色电影",
        "情色视频", "色情视频", "色情影片", "色情电影", "黄网视频", "黄片", "小黄片",
        "18禁视频", "18禁影片", "18禁电影", "18禁资源", "禁片视频",
        "成人视频资源", "成人视频合集", "成人电影", "成人短视频",
        "激情视频", "激情影片", "激情电影", "艳情视频", "艳情电影",
        "裸露视频", "性爱视频", "性爱影片", "性行为视频",
        "无码视频", "有码视频", "无码影片", "有码影片", "无码资源",
        "成人直播", "裸聊视频", "约炮视频", "调教视频", "SM视频",
        "制服诱惑视频", "偷拍视频", "偷拍影片", "换妻视频", "群交视频",
        "迷奸视频", "乱伦视频", "母子视频", "父女视频", "兄妹视频",
        "校园H视频", "少妇视频", "人妻视频", "骚舞视频",
        "福利视频", "福利姬视频", "成人动漫视频", "H动漫视频",
        "里番", "里番动画", "成人向动画",
    ],
    "漫画": [
        "成人漫画", "情色漫画", "色情漫画", "黄漫", "本子", "H漫",
        "18禁漫画", "18禁本子", "成人向漫画", "成人向同人", "同人本",
        "里番漫画", "工口漫画", "工口本子", "肉漫", "淫漫", "禁漫",
        "禁书漫画", "禁忌漫画", "无码漫画", "有码漫画",
        "成人韩漫", "色情韩漫", "成人日漫", "成人国漫", "成人条漫",
        "成人连载漫画", "成人视频漫画", "成人向条漫",
        "裸露漫画", "性爱漫画", "SM漫画", "调教漫画", "凌辱漫画",
        "强制爱漫画", "禁断漫画", "乱伦漫画", "母子漫画", "父女漫画",
        "兄妹漫画", "姐弟漫画", "人妻漫画", "绿帽漫画", "出轨漫画",
        "催眠漫画", "群交漫画", "换妻漫画", "迷奸漫画", "下药漫画",
        "NTR漫画", "纯爱H漫", "百合H漫", "耽美H漫", "BL黄漫", "GL黄漫",
        "兽交漫画", "触手漫画", "后宫H漫", "修仙H漫",
        "成人校园漫画", "制服诱惑漫画", "福利漫画", "福利本子",
        "绅士漫画", "绅士本子",
    ],
    "导航": [
        "色情导航", "成人导航", "黄站导航", "福利导航", "色站导航",
        "成人网址导航", "成人网站导航", "黄网导航", "成人资源导航", "福利网站导航",
        "成人入口", "成人网址", "成人站大全", "黄站大全", "福利站大全",
        "成人聚合站", "色情聚合站", "成人资源站导航", "成人索引站",
        "黄网索引", "色站索引", "成人链接导航", "福利链接导航",
        "成人分类导航", "黄站分类", "成人推荐站", "福利推荐站",
        "成人频道导航", "成人内容导航", "成人论坛导航", "成人社区导航", "成人搜索导航",
    ],
}

# 排除的域名
EXCLUDE_DOMAINS = {
    "google.com", "google.com.hk", "google.co.jp", "googleapis.com",
    "bing.com", "baidu.com", "sogou.com", "so.com", "360.cn",
    "youtube.com", "wikipedia.org", "wikimedia.org",
    "zhihu.com", "weibo.com", "bilibili.com", "douban.com",
    "tieba.baidu.com", "reddit.com", "quora.com",
    "twitter.com", "x.com", "facebook.com", "instagram.com",
    "tiktok.com", "douyin.com", "xiaohongshu.com",
    "github.com", "stackoverflow.com",
    "apple.com", "microsoft.com", "amazon.com",
}


def search_bing(keyword, max_results=10):
    """用 Bing 搜索（不需要 API key）"""
    urls = []
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        resp = requests.get(
            "https://www.bing.com/search",
            params={"q": keyword, "count": max_results},
            headers=headers,
            timeout=15,
        )
        # 提取搜索结果中的 URL
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(resp.text, "html.parser")
        for a in soup.find_all("a", href=True):
            href = a["href"]
            if href.startswith("http") and "bing.com" not in href and "microsoft.com" not in href:
                urls.append(href)
    except Exception as e:
        print(f"  搜索失败 [{keyword}]: {e}", file=sys.stderr)
    return urls


def search_duckduckgo(keyword, max_results=10):
    """用 DuckDuckGo HTML 搜索（不需要 API key）"""
    urls = []
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
        }
        resp = requests.get(
            "https://html.duckduckgo.com/html/",
            params={"q": keyword},
            headers=headers,
            timeout=15,
        )
        from bs4 import BeautifulSoup
        soup = BeautifulSoup(resp.text, "html.parser")
        for a in soup.find_all("a", class_="result__a", href=True):
            href = a["href"]
            if href.startswith("http"):
                urls.append(href)
        # 限制数量
        urls = urls[:max_results]
    except Exception as e:
        print(f"  搜索失败 [{keyword}]: {e}", file=sys.stderr)
    return urls


def search_tavily(keyword, max_results=10):
    """用 Tavily API 搜索（需要 TAVILY_API_KEY）"""
    api_key = os.environ.get("TAVILY_API_KEY")
    if not api_key:
        return []
    urls = []
    try:
        resp = requests.post(
            "https://api.tavily.com/search",
            json={"query": keyword, "max_results": max_results, "api_key": api_key},
            timeout=15,
        )
        data = resp.json()
        for result in data.get("results", []):
            url = result.get("url", "")
            if url:
                urls.append(url)
    except Exception as e:
        print(f"  搜索失败 [{keyword}]: {e}", file=sys.stderr)
    return urls


def extract_base_domain(url):
    """提取基础域名"""
    try:
        parsed = urlparse(url)
        return parsed.netloc.lower().lstrip("www.")
    except:
        return ""


def is_excluded(url):
    """检查 URL 是否在排除列表中"""
    domain = extract_base_domain(url)
    for exc in EXCLUDE_DOMAINS:
        if domain == exc or domain.endswith("." + exc):
            return True
    return False


def normalize_url(url):
    """归一化 URL，返回 scheme://netloc"""
    try:
        parsed = urlparse(url)
        return f"{parsed.scheme}://{parsed.netloc}"
    except:
        return url


def main():
    parser = argparse.ArgumentParser(description="关键词搜索 → 站点 URL 列表")
    parser.add_argument("--category", help="只搜指定类别: 小说/视频/漫画/导航")
    parser.add_argument("--keyword", help="搜单个关键词")
    parser.add_argument("--max-per-keyword", type=int, default=10, help="每个关键词最多取几个结果")
    parser.add_argument("--output", "-o", help="输出文件路径（默认 stdout）")
    parser.add_argument("--engine", default="duckduckgo", choices=["bing", "duckduckgo", "tavily"],
                        help="搜索引擎")
    parser.add_argument("--delay", type=float, default=2.0, help="每次搜索间隔秒数（防封）")
    args = parser.parse_args()

    # 选择搜索函数
    search_fn = {
        "bing": search_bing,
        "duckduckgo": search_duckduckgo,
        "tavily": search_tavily,
    }[args.engine]

    # 确定要搜的关键词
    if args.keyword:
        keywords = [args.keyword]
    elif args.category:
        keywords = KEYWORDS.get(args.category, [])
        if not keywords:
            print(f"未知类别: {args.category}，可选: {', '.join(KEYWORDS.keys())}", file=sys.stderr)
            sys.exit(1)
    else:
        keywords = []
        for kws in KEYWORDS.values():
            keywords.extend(kws)

    print(f"共 {len(keywords)} 个关键词，引擎: {args.engine}", file=sys.stderr)

    seen_domains = set()
    all_urls = []

    for i, kw in enumerate(keywords):
        print(f"[{i+1}/{len(keywords)}] 搜索: {kw}", file=sys.stderr)
        urls = search_fn(kw, args.max_per_keyword)

        for url in urls:
            if is_excluded(url):
                continue
            domain = extract_base_domain(url)
            if domain and domain not in seen_domains:
                seen_domains.add(domain)
                normalized = normalize_url(url)
                all_urls.append(normalized)

        if i < len(keywords) - 1:
            time.sleep(args.delay)

    print(f"\n共发现 {len(all_urls)} 个去重后的站点", file=sys.stderr)

    # 输出
    output_text = "\n".join(all_urls)
    if args.output:
        with open(args.output, "w") as f:
            f.write(output_text + "\n")
        print(f"已写入 {args.output}", file=sys.stderr)
    else:
        print(output_text)


if __name__ == "__main__":
    main()
