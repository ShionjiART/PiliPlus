#!/usr/bin/env python3
"""生成 AltStore / SideStore 源（altstore.json）和一个添加源用的网页。

从本仓库的 GitHub Releases 读出每个版本附带的 .ipa，解开里面的 Info.plist，
按安装包实际的包名、版本号、构建号、最低系统版本和权限填写源。AltStore 安装时
会核对这些信息，和安装包不一致就拒绝安装，所以不手写，每次都从安装包里读。

由 .github/workflows/altstore.yml 在发布 Release 后运行，部署到 GitHub Pages。
也可以在本机运行，检查生成的结果（只用到 Python 标准库）：

    python3 .github/altstore/build_source.py --repo ShionjiArt/PiliPlus --out logs/altstore
"""

from __future__ import annotations

import argparse
import html
import json
import os
import plistlib
import re
import shutil
import struct
import sys
import tempfile
import urllib.parse
import urllib.request
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
ICON = REPO_ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset/Icon-App-1024x1024@1x.png"

TINT_COLOR = "5CB67B"  # 图标的绿色

# 名字里带上维护者，在 AltStore 里和原版 PiliPlus 区分开。
SOURCE_NAME = "PiliPlus (sssakuya)"
SOURCE_SUBTITLE = "sssakuya 个人维护版，适配 iPhone Duo"
SOURCE_DESCRIPTION = (
    "sssakuya 个人维护的 PiliPlus（加入了 iPhone Duo 适配）的安装源，不是原版 PiliPlus 的源。"
    "每次在 GitHub 发布新版本后自动更新。"
)

APP_NAME = "PiliPlus (sssakuya)"
APP_DEVELOPER = "sssakuya"
APP_SUBTITLE = "sssakuya 个人维护版，适配 iPhone Duo"
APP_CATEGORY = "entertainment"
APP_DESCRIPTION = """\
这是 sssakuya 个人维护的 PiliPlus，不是原版。PiliPlus 是用 Flutter 开发的 BiliBili 第三方客户端，\
原作者 bggRGjQaUbCoE。

这个维护版加入了 iPhone Duo（折叠屏 iPhone）适配：合上和展开时自动切换布局，\
首页的标签栏放进竖状态栏，页面、播放器和直播间都避开竖状态栏。另外还改进了系统播放器\
播放 HDR 和杜比视界、AirPlay 投原画质等。

相对原版新增的功能和修复，见功能清单：
https://github.com/{repo}/blob/release/FEATURES.md"""

USER_AGENT = "altstore-source-builder"


@dataclass
class IpaInfo:
    bundle_id: str
    version: str
    build: str
    min_os: str | None
    privacy: dict[str, str] = field(default_factory=dict)
    entitlements: set[str] = field(default_factory=set)


# ---------------------------------------------------------------- GitHub

def api_get(url: str, token: str | None):
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": USER_AGENT,
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers)) as resp:
        return json.load(resp)


def list_releases(repo: str, token: str | None) -> list[dict]:
    releases, page = [], 1
    while True:
        batch = api_get(f"https://api.github.com/repos/{repo}/releases?per_page=100&page={page}", token)
        releases += batch
        if len(batch) < 100:
            return releases
        page += 1


def download(url: str, dest: Path) -> None:
    # 公开仓库的安装包不需要令牌；带着令牌跟随跳转到存储服务器反而会被拒绝。
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    tmp = dest.with_suffix(dest.suffix + ".part")
    with urllib.request.urlopen(req) as resp, open(tmp, "wb") as out:
        shutil.copyfileobj(resp, out)
    tmp.replace(dest)


# ---------------------------------------------------------------- 安装包

def read_entitlements(binary: bytes) -> dict:
    """从 Mach-O 的代码签名里读 entitlements；没有签名时返回空字典。"""
    magic = struct.unpack(">I", binary[:4])[0]
    if magic in (0xCAFEBABE, 0xCAFEBABF):  # 多架构
        result: dict = {}
        count = struct.unpack(">I", binary[4:8])[0]
        for i in range(count):
            if magic == 0xCAFEBABE:
                _, _, offset, size, _ = struct.unpack(">iiIII", binary[8 + i * 20 : 28 + i * 20])
            else:
                _, _, offset, size, _, _ = struct.unpack(">iiQQII", binary[8 + i * 32 : 40 + i * 32])
            result.update(read_entitlements(binary[offset : offset + size]))
        return result

    magic = struct.unpack("<I", binary[:4])[0]
    if magic == 0xFEEDFACF:
        header_size = 32
    elif magic == 0xFEEDFACE:
        header_size = 28
    else:
        raise ValueError(f"不是 Mach-O 文件（magic {magic:#x}）")
    ncmds = struct.unpack("<I", binary[16:20])[0]
    offset = header_size
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack("<II", binary[offset : offset + 8])
        if cmd == 0x1D:  # LC_CODE_SIGNATURE
            dataoff, datasize = struct.unpack("<II", binary[offset + 8 : offset + 16])
            return _entitlements_from_superblob(binary[dataoff : dataoff + datasize])
        offset += cmdsize
    return {}


def _entitlements_from_superblob(blob: bytes) -> dict:
    magic, _, count = struct.unpack(">III", blob[:12])
    if magic != 0xFADE0CC0:
        return {}
    for i in range(count):
        _, offset = struct.unpack(">II", blob[12 + i * 8 : 20 + i * 8])
        sub_magic, length = struct.unpack(">II", blob[offset : offset + 8])
        if sub_magic == 0xFADE7171:  # XML entitlements
            return plistlib.loads(blob[offset + 8 : offset + length])
    return {}


def inspect_ipa(path: Path) -> IpaInfo:
    with zipfile.ZipFile(path) as ipa:
        names = ipa.namelist()
        app_plists = [n for n in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)]
        if len(app_plists) != 1:
            raise ValueError(f"{path.name}: 找不到唯一的 Payload/*.app/Info.plist")
        app_dir = app_plists[0][: -len("Info.plist")]
        ext_plists = [n for n in names if re.fullmatch(re.escape(app_dir) + r"PlugIns/[^/]+\.appex/Info\.plist", n)]

        main = plistlib.loads(ipa.read(app_plists[0]))
        info = IpaInfo(
            bundle_id=main["CFBundleIdentifier"],
            version=str(main["CFBundleShortVersionString"]),
            build=str(main["CFBundleVersion"]),
            min_os=main.get("MinimumOSVersion"),
        )
        # AltStore 核对的是主程序和扩展的 *UsageDescription 和 entitlements。
        for plist_name in [app_plists[0], *ext_plists]:
            plist = main if plist_name == app_plists[0] else plistlib.loads(ipa.read(plist_name))
            for key, value in plist.items():
                if key.endswith("UsageDescription") and isinstance(value, str):
                    info.privacy.setdefault(key, value)
            executable = plist_name[: -len("Info.plist")] + plist["CFBundleExecutable"]
            info.entitlements |= set(read_entitlements(ipa.read(executable)))
        return info


# ---------------------------------------------------------------- 生成

def collect_versions(repo: str, token: str | None, cache: Path) -> list[tuple[dict, dict, IpaInfo]]:
    """返回 (release, asset, IpaInfo)，新版本在前。跳过草稿、预发布和没有安装包的 Release。"""
    found = []
    for release in list_releases(repo, token):
        if release["draft"] or release["prerelease"]:
            continue
        ipas = [a for a in release["assets"] if a["name"].endswith(".ipa")]
        if not ipas:
            print(f"跳过 {release['tag_name']}：没有 .ipa", file=sys.stderr)
            continue
        if len(ipas) > 1:
            print(f"{release['tag_name']} 有多个 .ipa，用 {ipas[0]['name']}", file=sys.stderr)
        asset = ipas[0]
        local = cache / f"{asset['id']}-{asset['name']}"
        if not local.exists() or local.stat().st_size != asset["size"]:
            print(f"下载 {asset['name']}", file=sys.stderr)
            download(asset["browser_download_url"], local)
        found.append((release, asset, inspect_ipa(local)))
    found.sort(key=lambda item: item[0]["published_at"], reverse=True)
    return found


def build_source(repo: str, base_url: str, versions: list[tuple[dict, dict, IpaInfo]]) -> dict:
    bundle_id = versions[0][2].bundle_id
    entries, seen = [], set()
    privacy: dict[str, str] = {}
    entitlements: set[str] = set()
    for release, asset, info in versions:
        tag = release["tag_name"]
        if info.bundle_id != bundle_id:
            print(f"跳过 {tag}：包名 {info.bundle_id} 和最新版的 {bundle_id} 不同", file=sys.stderr)
            continue
        # AltStore 要求每一项的版本号或构建号不同；重复时只留较新的 Release。
        if (info.version, info.build) in seen:
            print(f"跳过 {tag}：{info.version} ({info.build}) 和较新的 Release 重复", file=sys.stderr)
            continue
        seen.add((info.version, info.build))
        # 权限取所有版本的并集，安装旧版本时也不会因为少写了权限被拒绝。
        for key, value in info.privacy.items():
            privacy.setdefault(key, value)
        entitlements |= info.entitlements
        entry = {
            "version": info.version,
            "buildVersion": info.build,
            "marketingVersion": tag,
            "date": release["published_at"],
            "localizedDescription": (release.get("body") or release["name"] or tag).replace("\r\n", "\n").strip(),
            "downloadURL": asset["browser_download_url"],
            "size": asset["size"],
        }
        if info.min_os:
            entry["minOSVersion"] = info.min_os
        entries.append(entry)

    latest = entries[0]
    icon_url = base_url + "icon.png"
    app = {
        "name": APP_NAME,
        "bundleIdentifier": bundle_id,
        "developerName": APP_DEVELOPER,
        "subtitle": APP_SUBTITLE,
        "localizedDescription": APP_DESCRIPTION.format(repo=repo),
        "iconURL": icon_url,
        "tintColor": TINT_COLOR,
        "category": APP_CATEGORY,
        "versions": entries,
        "appPermissions": {
            "entitlements": sorted(entitlements),
            "privacy": dict(sorted(privacy.items())),
        },
        # 旧版 AltStore（1.x）和部分 SideStore 只认下面这几个字段。
        "version": latest["version"],
        "versionDate": latest["date"],
        "versionDescription": latest["localizedDescription"],
        "downloadURL": latest["downloadURL"],
        "size": latest["size"],
    }
    return {
        "name": SOURCE_NAME,
        "identifier": "io.github." + repo.replace("/", ".").lower(),
        "subtitle": SOURCE_SUBTITLE,
        "description": SOURCE_DESCRIPTION,
        "iconURL": icon_url,
        "website": f"https://github.com/{repo}",
        "tintColor": TINT_COLOR,
        "featuredApps": [bundle_id],
        "apps": [app],
        "news": [],
    }


def build_page(repo: str, source_url: str, source: dict) -> str:
    latest = source["apps"][0]["versions"][0]
    encoded = urllib.parse.quote(source_url, safe="")
    e = html.escape
    return f"""<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(SOURCE_NAME)} 安装源</title>
<style>
  :root {{ color-scheme: light dark; --tint: #{TINT_COLOR}; }}
  body {{ font: 16px/1.6 -apple-system, BlinkMacSystemFont, "PingFang SC", sans-serif;
         max-width: 34rem; margin: 0 auto; padding: 2rem 1rem; }}
  img {{ width: 88px; height: 88px; border-radius: 22%; }}
  h1 {{ font-size: 1.5rem; margin: .5rem 0 0; }}
  .button {{ display: block; text-align: center; padding: .8rem; margin: .6rem 0;
            border-radius: .8rem; background: var(--tint); color: #fff;
            text-decoration: none; font-weight: 600; }}
  code {{ word-break: break-all; }}
  .muted {{ opacity: .7; }}
</style>
</head>
<body>
<img src="icon.png" alt="">
<h1>{e(APP_NAME)}</h1>
<p class="muted">{e(APP_SUBTITLE)}</p>
<p>最新版本：{e(latest["marketingVersion"])}（{e(latest["version"])}，构建 {e(latest["buildVersion"])}），{e(latest["date"][:10])} 发布</p>
<a class="button" href="altstore://source?url={encoded}">添加到 AltStore</a>
<a class="button" href="sidestore://source?url={encoded}">添加到 SideStore</a>
<p>也可以在 AltStore 或 SideStore 的「源」里手动添加这个地址：<br><code>{e(source_url)}</code></p>
<p><a href="https://github.com/{e(repo)}/releases">全部版本</a> · <a href="https://github.com/{e(repo)}/blob/release/FEATURES.md">功能清单</a></p>
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--repo", default=os.environ.get("GITHUB_REPOSITORY"), help="owner/name")
    parser.add_argument("--base-url", help="网页的根地址，默认 https://<owner>.github.io/<name>/")
    parser.add_argument("--out", type=Path, required=True, help="输出目录")
    parser.add_argument("--cache-dir", type=Path, help="缓存下载的安装包，默认用临时目录")
    args = parser.parse_args()
    if not args.repo:
        parser.error("需要 --repo 或环境变量 GITHUB_REPOSITORY")

    owner, name = args.repo.split("/")
    base_url = args.base_url or f"https://{owner.lower()}.github.io/{name}/"
    if not base_url.endswith("/"):
        base_url += "/"
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")

    with tempfile.TemporaryDirectory() as tmp:
        cache = args.cache_dir or Path(tmp)
        cache.mkdir(parents=True, exist_ok=True)
        versions = collect_versions(args.repo, token, cache)
    if not versions:
        print("没有找到带 .ipa 的 Release，不生成源", file=sys.stderr)
        return 1

    source = build_source(args.repo, base_url, versions)
    source_url = base_url + "altstore.json"
    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "altstore.json").write_text(json.dumps(source, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (args.out / "index.html").write_text(build_page(args.repo, source_url, source), encoding="utf-8")
    shutil.copyfile(ICON, args.out / "icon.png")

    for v in source["apps"][0]["versions"]:
        print(f"{v['marketingVersion']}: {v['version']} ({v['buildVersion']}), {v['size']} 字节")
    print(f"源地址：{source_url}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
