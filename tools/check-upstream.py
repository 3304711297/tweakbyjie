#!/usr/bin/env python3
"""
Tweakbyjie 上游更新看门脚本
监控 Kiwi-Tweaks 等上游优化项目的新 Commit / Release，并在发现更新时生成结构化报告。
"""

import os
import sys
import json
import urllib.request
import urllib.error
import subprocess
from datetime import datetime

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES_FILE = os.path.join(ROOT_DIR, "tools", "upstream-sources.json")


def get_headers():
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    headers = {
        "User-Agent": "TweakByjie-Upstream-Watch/1.0",
        "Accept": "application/vnd.github.v3+json",
    }
    if token:
        headers["Authorization"] = f"token {token}"
    return headers


def api_get(url):
    headers = get_headers()
    if "Authorization" in headers:
        req = urllib.request.Request(url, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except Exception:
            pass

    try:
        endpoint = url.replace("https://api.github.com/", "")
        res = subprocess.run(["gh", "api", endpoint], capture_output=True, text=True)
        if res.returncode == 0:
            return json.loads(res.stdout)
    except Exception:
        pass
    return None


def check_source(name, cfg):
    repo = cfg["repo"]
    branch = cfg.get("branch", "main")
    last_commit = cfg.get("last_synced_commit", "")
    last_release = cfg.get("last_synced_release", "")

    commit_data = api_get(f"https://api.github.com/repos/{repo}/commits/{branch}")
    latest_sha = commit_data.get("sha", "") if commit_data else ""
    latest_sha_short = latest_sha[:7] if latest_sha else ""
    commit_msg = (
        commit_data.get("commit", {}).get("message", "").splitlines()[0]
        if commit_data
        else ""
    )

    release_data = api_get(f"https://api.github.com/repos/{repo}/releases/latest")
    latest_release = release_data.get("tag_name", "") if release_data else ""

    has_update = (latest_sha_short and last_commit and latest_sha_short != last_commit) or (
        latest_release and last_release and latest_release != last_release
    )

    return {
        "name": name,
        "repo": repo,
        "description": cfg.get("description", ""),
        "last_commit": last_commit,
        "latest_commit": latest_sha_short,
        "commit_msg": commit_msg,
        "last_release": last_release,
        "latest_release": latest_release or "无",
        "has_update": has_update,
    }


def main():
    if not os.path.exists(SOURCES_FILE):
        print(f"Sources file not found: {SOURCES_FILE}", file=sys.stderr)
        sys.exit(1)

    with open(SOURCES_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)

    sources = data.get("sources", {})
    updates = []

    print(f"=== 开始巡检 {len(sources)} 个上游优化项目 ===")
    for name, cfg in sources.items():
        res = check_source(name, cfg)
        status = "🚀 发现更新" if res["has_update"] else "✅ 已是最新"
        print(f"{status} [{name}] ({res['repo']}): Commit {res['last_commit']} -> {res['latest_commit']}")
        if res["has_update"]:
            updates.append(res)

    print(f"\n巡检结束：共发现 {len(updates)} 个项目存在上游新提交/新版本。")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as f:
            f.write(f"has_updates={'true' if updates else 'false'}\n")
            f.write(f"update_count={len(updates)}\n")

    if "--report" in sys.argv and updates:
        report_lines = [
            "# 🔔 上游项目更新通知 (Upstream Updates Detected)\n",
            f"检测时间：`{datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}`\n",
            "| 项目名称 | 上游仓库 | 本地基线 | 上游最新 | 提交摘要 |",
            "| :--- | :--- | :--- | :--- | :--- |",
        ]
        for u in updates:
            diff_url = (
                f"https://github.com/{u['repo']}/compare/{u['last_commit']}...{u['latest_commit']}"
                if u["last_commit"] and u["latest_commit"]
                else f"https://github.com/{u['repo']}"
            )
            report_lines.append(
                f"| **`{u['name']}`** | [{u['repo']}](https://github.com/{u['repo']}) | Commit `{u['last_commit']}`<br>Tag `{u['last_release']}` | Commit [`{u['latest_commit']}`]({diff_url})<br>Tag `{u['latest_release']}` | {u['commit_msg']} |"
            )
        report_lines.extend([
            "\n### 🛠️ 处理建议",
            "1. 点击 Compare 链接查看具体代码差异与新优化项；",
            "2. 评估是否包含适合 `tweakbyjie`（模块化脚本）或 `youshouldknow`（原理知识库）吸收的内容；",
            "3. 排除任何破坏性或玄学修改（如非法硬编码、粗暴停用核心系统服务等）；",
            "4. 评估确认无须改动或完成吸收后，直接在此 Issue 留言并关闭即可。"
        ])
        report_text = "\n".join(report_lines)
        with open(os.path.join(ROOT_DIR, "upstream-report.md"), "w", encoding="utf-8") as f:
            f.write(report_text)


if __name__ == "__main__":
    main()
