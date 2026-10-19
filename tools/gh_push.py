#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""用 GitHub REST API 推送本仓库并触发 Actions 构建(不需要本机装 git / gh)。

背景:本机无 git、gh,且 urllib 在该网络下会 TLS EOF;这里用原生 socket 直连
api.github.com 发 HTTP/1.1(支持 Content-Length / chunked),只依赖标准库。

用法:
    # 仅体检(不需要 token)
    python tools/gh_push.py --check

    # 建仓(可选)+ 全量推送到 main + 触发构建,等待结束并下载 deb
    python tools/gh_push.py --repo liudubin/douyin-fudai-helper --private \
        --token-file C:/Users/12936/Downloads/gh_token.txt --wait

token 从 --token-file 或环境变量 GITHUB_TOKEN 读取,脚本不会打印它。
需要的权限(fine-grained PAT): Contents: R/W、Workflows: R/W、Actions: R、
Administration: R/W(仅建仓时需要)。
"""
import argparse
import base64
import hashlib
import json
import os
import socket
import ssl
import sys
import time
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOST = "api.github.com"
SKIP_DIRS = {".git", ".theos", "packages", "out", "objc_dump", "__pycache__"}
SKIP_SUFFIX = {".deb", ".ddeb", ".o", ".dylib"}
API_VERSION = "2022-11-28"


def log(msg):
    print(msg, flush=True)


class Resp:
    def __init__(self, status, headers, body):
        self.status = status
        self.headers = headers
        self.body = body

    @property
    def json(self):
        try:
            return json.loads(self.body.decode("utf-8"))
        except Exception:
            return None

    def __repr__(self):
        return "<%s %d %s>" % (self.status, len(self.body), self.body[:160])


def _contexts():
    """GitHub 在本网络下偶发 TLS 握手 EOF:依次尝试 TLS1.3 / 强制 TLS1.2 / 宽松校验。"""
    try:
        yield ssl.create_default_context()
    except Exception:
        pass
    try:
        ctx = ssl.create_default_context()
        ctx.maximum_version = ssl.TLSVersion.TLSv1_2
        yield ctx
    except Exception:
        pass


def request(method, path, token=None, payload=None, timeout=60, raw=False):
    last = None
    for attempt in range(6):
        for ctx in _contexts():
            try:
                return _request_once(method, path, token, payload, timeout, ctx)
            except (ssl.SSLError, OSError) as exc:
                last = exc
        time.sleep(1.2 + attempt * 0.8)
    raise last if last else RuntimeError("request failed")


def _request_once(method, path, token, payload, timeout, ctx):
    headers = [
        "Host: %s" % HOST,
        "User-Agent: douyin-fudai-helper-ci",
        "Accept: application/vnd.github+json",
        "X-GitHub-Api-Version: " + API_VERSION,
        "Connection: close",
    ]
    if token:
        headers.append("Authorization: Bearer " + token)
    body = b""
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers.append("Content-Type: application/json")
    headers.append("Content-Length: %d" % len(body))

    req = ("%s %s HTTP/1.1\r\n" % (method, path) + "\r\n".join(headers) + "\r\n\r\n").encode()
    sock = socket.create_connection((HOST, 443), timeout=timeout)
    ss = ctx.wrap_socket(sock, server_hostname=HOST)
    try:
        ss.sendall(req + body)
        buf = b""
        while True:
            chunk = ss.recv(65536)
            if not chunk:
                break
            buf += chunk
            if b"\r\n\r\n" in buf:
                head, _, rest = buf.partition(b"\r\n\r\n")
                lines = head.decode("latin-1").split("\r\n")
                status = int(lines[0].split()[1])
                hdrs = {}
                for line in lines[1:]:
                    if ":" in line:
                        k, v = line.split(":", 1)
                        hdrs[k.strip().lower()] = v.strip()
                if "content-length" in hdrs:
                    need = int(hdrs["content-length"])
                    while len(rest) < need:
                        more = ss.recv(65536)
                        if not more:
                            break
                        rest += more
                    buf = head + b"\r\n\r\n" + rest
                    break
                if hdrs.get("transfer-encoding", "").lower() == "chunked":
                    if rest.endswith(b"0\r\n\r\n"):
                        buf = head + b"\r\n\r\n" + rest
                        break
                elif b"\r\n\r\n" in buf:
                    break
    finally:
        try:
            ss.close()
        except Exception:
            pass

    head, _, rest = buf.partition(b"\r\n\r\n")
    lines = head.decode("latin-1").split("\r\n")
    status = int(lines[0].split()[1])
    hdrs = {}
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            hdrs[k.strip().lower()] = v.strip()
    if hdrs.get("transfer-encoding", "").lower() == "chunked":
        out, i = b"", 0
        while i < len(rest):
            j = rest.find(b"\r\n", i)
            if j < 0:
                break
            size = int(rest[i:j].split(b";")[0] or b"0", 16)
            if size == 0:
                break
            out += rest[j + 2:j + 2 + size]
            i = j + 2 + size + 2
        rest = out
    return Resp(status, hdrs, rest)


def die(msg, resp=None):
    log("失败: " + msg)
    if resp is not None:
        log("  HTTP %s %s" % (resp.status, (resp.body[:400] or b"").decode("utf-8", "replace")))
    sys.exit(1)


def collect_files():
    files = []
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(ROOT)
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        if path.suffix in SKIP_SUFFIX:
            continue
        files.append(rel)
    return files


def cmd_check():
    r = request("GET", "/rate_limit")
    if r.status != 200:
        die("api.github.com 不可达", r)
    core = r.json["resources"]["core"]
    log("api.github.com 可达 · 匿名额度 %s/%s(剩余 %s,重置 %s)"
        % (core["used"], core["limit"], core["remaining"], time.strftime("%H:%M:%S", time.localtime(core["reset"]))))
    files = collect_files()
    log("待推送文件 %d 个,合计 %d 字节" % (len(files), sum((ROOT / f).stat().st_size for f in files)))


def ensure_repo(owner, name, token, private):
    r = request("GET", "/repos/%s/%s" % (owner, name), token)
    if r.status == 200:
        log("仓库已存在: %s/%s" % (owner, name))
        return r.json
    if r.status != 404:
        die("查询仓库失败", r)
    r = request("GET", "/user", token)
    if r.status != 200:
        die("token 无效或权限不足", r)
    me = r.json["login"]
    log("token 属于账号: %s" % me)
    if me.lower() != owner.lower():
        die("仓库 %s 不属于 token 账号 %s;请先在网页建好仓库,或把 --repo 改成 %s/..." % (owner, me, me))
    r = request("POST", "/user/repos", token, {
        "name": name,
        "private": bool(private),
        "description": "抖音直播间福袋助手 · Theos deb(relaxin 无根 / 抖音 40.7.0)",
        "has_issues": True,
        "has_wiki": False,
        "auto_init": False,
    })
    if r.status not in (201, 200):
        die("建仓失败", r)
    log("建仓成功: %s/%s (private=%s)" % (owner, name, private))
    return r.json


def ensure_initialized(owner, name, token):
    """空仓库不支持 Git Data API(blobs 返回 409),先用 Contents API 落首个提交。"""
    r = request("GET", "/repos/%s/%s/git/ref/heads/main" % (owner, name), token)
    if r.status == 200:
        return
    seed = ".gitattributes"
    data = (ROOT / seed).read_bytes()
    r = request("PUT", "/repos/%s/%s/contents/%s" % (owner, name, seed), token,
                {"message": "chore: init", "content": base64.b64encode(data).decode("ascii"), "branch": "main"})
    if r.status not in (200, 201):
        die("初始化空仓库失败", r)
    log("空仓库已初始化(seed commit: %s)" % seed)


def push_tree(owner, name, token, message):
    ensure_initialized(owner, name, token)
    files = collect_files()
    entries = []
    for rel in files:
        data = (ROOT / rel).read_bytes()
        r = request("POST", "/repos/%s/%s/git/blobs" % (owner, name), token,
                    {"content": base64.b64encode(data).decode("ascii"), "encoding": "base64"})
        if r.status not in (200, 201):
            die("上传 blob 失败: %s" % rel, r)
        sha = r.json["sha"]
        mode = "100755" if str(rel).endswith((".sh",)) else "100644"
        entries.append({"path": str(rel).replace(os.sep, "/"), "mode": mode, "type": "blob", "sha": sha})
        log("  blob %-42s %8d B -> %s" % (str(rel).replace(os.sep, "/"), len(data), sha[:8]))

    r = request("POST", "/repos/%s/%s/git/trees" % (owner, name), token, {"tree": entries})
    if r.status not in (200, 201):
        die("建 tree 失败", r)
    tree_sha = r.json["sha"]

    parent = None
    r = request("GET", "/repos/%s/%s/git/ref/heads/main" % (owner, name), token)
    if r.status == 200:
        parent = r.json["object"]["sha"]
        log("现有 main 头: %s" % parent[:8])

    payload = {"message": message, "tree": tree_sha}
    if parent:
        payload["parents"] = [parent]
    r = request("POST", "/repos/%s/%s/git/commits" % (owner, name), token, payload)
    if r.status not in (200, 201):
        die("建 commit 失败", r)
    commit = r.json["sha"]
    log("commit: %s" % commit[:8])

    if parent:
        r = request("PATCH", "/repos/%s/%s/git/refs/heads/main" % (owner, name), token,
                    {"sha": commit, "force": False})
    else:
        r = request("POST", "/repos/%s/%s/git/refs" % (owner, name), token,
                    {"ref": "refs/heads/main", "sha": commit})
    if r.status not in (200, 201):
        die("更新分支失败", r)
    log("main 已更新到 %s,共 %d 个文件" % (commit[:8], len(entries)))
    return commit


def trigger_and_wait(owner, name, token, wait):
    r = request("POST", "/repos/%s/%s/actions/workflows/build.yml/dispatches" % (owner, name), token,
                {"ref": "main"})
    if r.status not in (204, 200):
        die("触发 workflow 失败(确认 token 有 Workflows:write,且 .github/workflows/build.yml 已在 main)", r)
    log("workflow 已触发,等待排队…")
    if not wait:
        log("用 --wait 可以等到构建完成并下载 deb")
        return None

    run = None
    for _ in range(30):
        time.sleep(6)
        r = request("GET", "/repos/%s/%s/actions/runs?branch=main&per_page=1" % (owner, name), token)
        if r.status != 200:
            die("查询运行状态失败", r)
        runs = r.json.get("workflow_runs") or []
        if not runs:
            continue
        run = runs[0]
        log("run #%s status=%s conclusion=%s" % (run["run_number"], run["status"], run.get("conclusion")))
        if run["status"] == "completed":
            break
    if not run or run["status"] != "completed":
        die("等待超时,请到 Actions 页面查看")
    if run.get("conclusion") != "success":
        die("构建失败,conclusion=%s;日志: %s" % (run.get("conclusion"), run["html_url"]))
    log("构建成功: %s" % run["html_url"])

    r = request("GET", "/repos/%s/%s/actions/runs/%s/artifacts" % (owner, name, run["id"]), token)
    if r.status != 200:
        die("查询 artifact 失败", r)
    artifacts = r.json.get("artifacts") or []
    if not artifacts:
        die("没有 artifact 产出")
    art = artifacts[0]
    log("artifact: %s (%d B)" % (art["name"], art["size_in_bytes"]))
    r = request("GET", "/repos/%s/%s/actions/artifacts/%s/zip" % (owner, name, art["id"]), token)
    if r.status not in (200, 302):
        die("下载 artifact 失败", r)
    out_zip = ROOT / "out" / (art["name"] + ".zip")
    out_zip.parent.mkdir(exist_ok=True)
    out_zip.write_bytes(r.body)
    log("已下载: %s (%d B,sha256=%s)" % (out_zip, len(r.body), hashlib.sha256(r.body).hexdigest()))
    try:
        with zipfile.ZipFile(out_zip) as zf:
            zf.extractall(out_zip.parent)
            log("解压到: %s → %s" % (out_zip.parent, ", ".join(zf.namelist())))
    except Exception as exc:
        log("解压失败(不影响 deb 已下载): %s" % exc)
    return run


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="只体检 API 可达性与待推文件")
    ap.add_argument("--repo", help="OWNER/NAME")
    ap.add_argument("--private", action="store_true", help="新仓库设为私有")
    ap.add_argument("--token-file", help="含 PAT 的文件路径(不打印内容)")
    ap.add_argument("--message", default="feat: 抖音福袋助手 v0.7.2 (relaxin 无根 / 抖音 40.7.0)")
    ap.add_argument("--wait", action="store_true", help="等待 Actions 构建完成并下载 deb")
    ap.add_argument("--push-only", action="store_true", help="只推代码,不触发构建")
    ap.add_argument("--poll-only", action="store_true", help="只触发并等待构建(不重复推送)")
    args = ap.parse_args()

    if args.check:
        cmd_check()
        return

    token = os.environ.get("GITHUB_TOKEN", "")
    if args.token_file:
        p = Path(args.token_file)
        if not p.is_file():
            die("token 文件不存在: %s" % p)
        token = p.read_text(encoding="utf-8").strip()
    if not token:
        die("缺少 token:用 --token-file 指定,或设置 GITHUB_TOKEN")
    if not args.repo:
        die("缺少 --repo OWNER/NAME")
    owner, _, name = args.repo.partition("/")
    if not owner or not name:
        die("--repo 需要 OWNER/NAME 形式")

    if args.poll_only:
        trigger_and_wait(owner, name, token, True)
        return

    ensure_repo(owner, name, token, args.private)
    push_tree(owner, name, token, args.message)
    if not args.push_only:
        trigger_and_wait(owner, name, token, args.wait)


if __name__ == "__main__":
    main()
