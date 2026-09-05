#!/usr/bin/env python3
"""
Tweakbyjie 上游更新看门脚本
监控 Kiwi-Tweaks 等上游优化项目的新 Commit / Release，并在发现更新时生成结构化报告。

自 v2 起按"分支"跟踪（用户拍板：永远看完整提交，不做路径过滤）：
  - 已知分支：通过 compare API 列出基线 -> 头部区间的全部 commit；
  - 新出现的分支：作为更新上报（附头部 commit），人工评估后写入基线；
  - 已消失的分支：提示清理 upstream-sources.json 基线；
  - Release tag 变化与分支无关，单独上报。
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


def first_line(message):
    return (message or "").splitlines()[0] if message else ""


def head_commit_info(repo, sha):
    data = api_get(f"https://api.github.com/repos/{repo}/commits/{sha}")
    return {"sha": sha[:7], "msg": first_line(data.get("commit", {}).get("message", "")) if data else ""}


def list_branch_commits(repo, base, head):
    """基线 -> 头部区间的全部 commit；取不到 compare 时退回单条头部。"""
    data = api_get(f"https://api.github.com/repos/{repo}/compare/{base}...{head}")
    if data and isinstance(data.get("commits"), list) and data["commits"]:
        return [
            {"sha": c.get("sha", "")[:7], "msg": first_line(c.get("commit", {}).get("message", ""))}
            for c in data["commits"]
        ]
    return [head_commit_info(repo, head)]


def check_source(name, cfg):
    """返回 (updates, notes)。updates 为该源全部更新明细，notes 为无动作说明。"""
    repo = cfg["repo"]
    branches = cfg.get("branches") or [cfg.get("branch", "main")]
    synced = cfg.get("last_synced_commits") or {}
    legacy_default = cfg.get("branch", "main")
    legacy_commit = cfg.get("last_synced_commit", "")

    updates = []
    notes = []

    remote = api_get(f"https://api.github.com/repos/{repo}/branches?per_page=100")
    remote_map = {b.get("name", ""): (b.get("commit", {}) or {}).get("sha", "") for b in remote} if remote else {}

    for branch in branches:
        head = remote_map.get(branch, "")
        base = synced.get(branch, legacy_commit if branch == legacy_default else "")
        if not head:
            updates.append({"type": "branch-missing", "branch": branch, "base": base,
                            "commits": [], "detail": "分支在远端已不存在，请清理基线"})
            continue
        if not base:
            commits = [head_commit_info(repo, head)]
            updates.append({"type": "branch-new", "branch": branch, "base": "",
                            "commits": commits, "detail": "新分支（首次纳入跟踪）"})
            continue
        if head.startswith(base) or base.startswith(head[:7]):
            notes.append(f"{branch} 已是最新 ({base[:7]})")
            continue
        commits = list_branch_commits(repo, base, head)
        updates.append({"type": "branch-update", "branch": branch, "base": base,
                        "commits": commits, "detail": f"{len(commits)} 个新提交"})

    for branch, head_sha in remote_map.items():
        if branch and branch not in branches:
            updates.append({"type": "branch-new", "branch": branch, "base": "",
                            "commits": [head_commit_info(repo, head_sha)],
                            "detail": "远端新出现的分支（尚未纳入基线）"})

    release_data = api_get(f"https://api.github.com/repos/{repo}/releases/latest")
    latest_release = release_data.get("tag_name", "") if release_data else ""
    last_release = cfg.get("last_synced_release", "")
    rel_1 = latest_release.lstrip("v")
    rel_2 = last_release.lstrip("v")
    if rel_1 and rel_2 and rel_1 != rel_2:
        updates.append({"type": "release", "branch": "-", "base": last_release,
                        "commits": [], "detail": f"Release {last_release} -> {latest_release}"})
    elif latest_release and not last_release:
        notes.append(f"Release 首次记录 {latest_release}")

    return updates, notes


def esc(text):
    return (text or "").replace("|", "\\|").replace("\n", " ")


TYPE_LABELS = {
    "branch-update": "分支更新",
    "branch-new": "新分支",
    "branch-missing": "分支消失",
    "release": "新 Release",
}


def main():
    if not os.path.exists(SOURCES_FILE):
        print(f"Sources file not found: {SOURCES_FILE}", file=sys.stderr)
        sys.exit(1)

    with open(SOURCES_FILE, "r", encoding="utf-8") as f:
        data = json.load(f)

    sources = data.get("sources", {})
    updated_sources = []

    print(f"=== 开始巡检 {len(sources)} 个上游优化项目 ===")
    for name, cfg in sources.items():
        updates, notes = check_source(name, cfg)
        for n in notes:
            print(f"  ✅ [{name}] {n}")
        if updates:
            updated_sources.append({"name": name, "repo": cfg["repo"], "items": updates})
            for u in updates:
                head = u["commits"][-1]["sha"] if u["commits"] else "-"
                print(f"  🚀 [{name}] {TYPE_LABELS[u['type']]} {u['branch']}: {u['detail']} (head {head})")

    print(f"\n巡检结束：共发现 {len(updated_sources)} 个项目存在上游新提交/新分支/新版本。")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a", encoding="utf-8") as f:
            f.write(f"has_updates={'true' if updated_sources else 'false'}\n")
            f.write(f"update_count={len(updated_sources)}\n")

    if "--report" in sys.argv and updated_sources:
        report_lines = [
            "# 🔔 上游项目更新通知 (Upstream Updates Detected)\n",
            f"检测时间：`{datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}`\n",
            "| 项目名称 | 上游仓库 | 类型 | 分支 | 基线 | 最新 | 新提交明细 |",
            "| :--- | :--- | :--- | :--- | :--- | :--- | :--- |",
        ]
        for u in updated_sources:
            repo = u["repo"]
            for item in u["items"]:
                if item["type"] in ("branch-update", "branch-new") and item["commits"]:
                    head_sha = item["commits"][-1]["sha"]
                    diff_url = (
                        f"https://github.com/{repo}/compare/{item['base']}...{head_sha}"
                        if item["base"]
                        else f"https://github.com/{repo}/tree/{item['branch']}"
                    )
                    latest = head_sha
                    detail = "<br>".join(f"[`{c['sha']}`]({diff_url}) {esc(c['msg'])}" for c in item["commits"])
                else:
                    diff_url = f"https://github.com/{repo}"
                    latest = item["detail"].split("-> ")[-1] if "-> " in item["detail"] else "-"
                    detail = esc(item["detail"])
                report_lines.append(
                    f"| **`{u['name']}`** | [{repo}](https://github.com/{repo}) | {TYPE_LABELS[item['type']]} | {esc(item['branch'])} | `{item['base'] or '-'}` | [`{latest}`]({diff_url}) | {detail or '-'} |"
                )
        report_lines.extend([
            "\n### 🛠️ 处理建议",
            "1. 点击提交明细中的 SHA 链接或 Compare 链接查看具体代码差异与新优化项；",
            "2. 评估是否包含适合 `tweakbyjie`（模块化脚本）或 `youshouldknow`（原理知识库）吸收的内容；",
            "3. 排除任何破坏性或玄学修改（如非法硬编码、粗暴停用核心系统服务等）；",
            "4. 分支消失/新分支类提醒需要在评估后同步维护 `tools/upstream-sources.json` 的分支基线；",
            "5. 评估确认无须改动或完成吸收后，在此 Issue 留言并关闭即可。"
        ])
        report_text = "\n".join(report_lines)
        with open(os.path.join(ROOT_DIR, "upstream-report.md"), "w", encoding="utf-8") as f:
            f.write(report_text)


if __name__ == "__main__":
    main()
