#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 GitHub Release 同步发布到 Gitee（创建 / 更新 Release 并同步附件）。

只依赖 Python 标准库，供 GitHub Actions 在发布完成后调用，也可本地手动执行：

    GITEE_TOKEN=xxx python3 scripts/gitee_release.py \
        --repo kuwinet/frp-onekey --tag v0.72.0 \
        --name "frp 0.72.0 一键脚本" --notes-file release-notes.md \
        --assets-dir assets

退出码：0 = 成功或按预期跳过；1 = 出错（调用方可用 continue-on-error 兜住）。
"""

import argparse
import json
import mimetypes
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

API = "https://gitee.com/api/v5"


def log(msg):
    print(msg, flush=True)


def api(method, path, token=None, params=None, fields=None, files=None, timeout=60):
    """调用 Gitee OpenAPI v5。

    files: [(field_name, filename, bytes)]，存在时使用 multipart/form-data。
    """
    url = API + path
    query = dict(params or {})
    headers = {"User-Agent": "frp-onekey-release-sync"}

    if files:
        boundary = "----frponekey" + uuid.uuid4().hex
        body = bytearray()
        for k, v in query.items():
            body += ("--%s\r\n" % boundary).encode()
            body += ('Content-Disposition: form-data; name="%s"\r\n\r\n' % k).encode()
            body += ("%s\r\n" % v).encode()
        for field, filename, content in files:
            ctype = mimetypes.guess_type(filename)[0] or "application/octet-stream"
            body += ("--%s\r\n" % boundary).encode()
            body += (
                'Content-Disposition: form-data; name="%s"; filename="%s"\r\n'
                % (field, filename)
            ).encode()
            body += ("Content-Type: %s\r\n\r\n" % ctype).encode()
            body += content
            body += b"\r\n"
        body += ("--%s--\r\n" % boundary).encode()
        headers["Content-Type"] = "multipart/form-data; boundary=%s" % boundary
        data = bytes(body)
    elif fields:
        data = urllib.parse.urlencode(fields).encode()
        headers["Content-Type"] = "application/x-www-form-urlencoded"
    else:
        data = None

    if method == "GET" and data is None and query:
        url += "?" + urllib.parse.urlencode(query)

    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw.strip().startswith((b"{", b"[")) else raw.decode("utf-8", "replace"))
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            payload = json.loads(raw)
        except Exception:
            payload = raw.decode("utf-8", "replace")
        return e.code, payload
    except urllib.error.URLError as e:
        return None, str(e)


def tag_exists(repo, tag):
    st, body = api("GET", "/repos/%s/tags" % repo)
    if st != 200 or not isinstance(body, list):
        return None
    return any((x or {}).get("name") == tag for x in body)


def get_release_by_tag(repo, tag, token):
    st, body = api("GET", "/repos/%s/releases/tags/%s" % (repo, urllib.parse.quote(tag)), token)
    if st == 200 and isinstance(body, dict):
        return body
    return None


def list_assets(repo, release_id, token):
    st, body = api(
        "GET", "/repos/%s/releases/%s/attach_files" % (repo, release_id), token
    )
    if st == 200 and isinstance(body, list):
        return body
    return []


def delete_asset(repo, release_id, attach_id, token):
    st, body = api(
        "DELETE",
        "/repos/%s/releases/%s/attach_files/%s" % (repo, release_id, attach_id),
        token,
    )
    return st


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True, help="Gitee 仓库，如 kuwinet/frp-onekey")
    ap.add_argument("--tag", required=True)
    ap.add_argument("--name", default=None)
    ap.add_argument("--notes-file", default=None)
    ap.add_argument("--assets-dir", default=None)
    ap.add_argument("--token", default=os.environ.get("GITEE_TOKEN", ""))
    ap.add_argument("--prerelease", action="store_true")
    ap.add_argument("--wait-tag", type=int, default=0, help="等待 tag 同步的最长秒数")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    notes = ""
    if args.notes_file and os.path.exists(args.notes_file):
        with open(args.notes_file, encoding="utf-8") as f:
            notes = f.read()

    name = args.name or args.tag

    # 1) 等 tag 出现（Gitee 镜像同步有延迟）
    waited = 0
    while True:
        exists = tag_exists(args.repo, args.tag)
        if exists:
            log("✅ Gitee 已有 tag %s" % args.tag)
            break
        if waited >= args.wait_tag:
            log("⚠️ Gitee 仓库暂未同步到 tag %s，已等待 %ds，跳过本次 Gitee 发布" % (args.tag, waited))
            return 0
        log("⏳ 等待 Gitee 镜像同步 tag %s ...（已等待 %ds）" % (args.tag, waited))
        time.sleep(15)
        waited += 15

    if args.dry_run:
        log("[dry-run] 将创建/更新 Release：%s（%s）" % (args.tag, name))
        if args.assets_dir and os.path.isdir(args.assets_dir):
            for fn in sorted(os.listdir(args.assets_dir)):
                log("  附件: %s" % fn)
        return 0

    if not args.token:
        log("⚠️ 未提供 GITEE_TOKEN，跳过 Gitee 发布")
        return 0

    # 2) 创建或更新 Release
    rel = get_release_by_tag(args.repo, args.tag, args.token)
    if rel and rel.get("id"):
        log("Release %s 已存在（id=%s），更新说明" % (args.tag, rel["id"]))
        st, body = api(
            "PATCH",
            "/repos/%s/releases/%s" % (args.repo, rel["id"]),
            params={"access_token": args.token},
            fields={"tag_name": args.tag, "name": name, "body": notes, "prerelease": "true" if args.prerelease else "false"},
        )
        if st != 200:
            log("::error::更新 Gitee Release 失败（HTTP %s）：%s" % (st, body))
            return 1
        rid = rel["id"]
    else:
        log("创建 Gitee Release %s" % args.tag)
        st, body = api(
            "POST",
            "/repos/%s/releases" % args.repo,
            params={"access_token": args.token},
            fields={
                "tag_name": args.tag,
                "name": name,
                "body": notes,
                "target_commitish": "master",
                "prerelease": "true" if args.prerelease else "false",
            },
        )
        if st not in (200, 201) or not isinstance(body, dict) or not body.get("id"):
            log("::error::创建 Gitee Release 失败（HTTP %s）：%s" % (st, body))
            return 1
        rid = body["id"]
    log("✅ Release 已就绪（id=%s）" % rid)

    # 3) 同步附件：先删同名旧附件，再上传
    if not args.assets_dir or not os.path.isdir(args.assets_dir):
        log("未提供附件目录，仅同步 Release 说明")
        return 0

    wanted = sorted(
        fn for fn in os.listdir(args.assets_dir)
        if os.path.isfile(os.path.join(args.assets_dir, fn))
    )
    existing = list_assets(args.repo, rid, args.token)
    for a in existing:
        aname = (a or {}).get("name")
        aid = (a or {}).get("id")
        if aname in wanted and aid:
            delete_asset(args.repo, rid, aid, args.token)
            log("   已删除同名旧附件: %s" % aname)

    ok = 0
    for fn in wanted:
        path = os.path.join(args.assets_dir, fn)
        with open(path, "rb") as f:
            content = f.read()
        st, body = api(
            "POST",
            "/repos/%s/releases/%s/attach_files" % (args.repo, rid),
            params={"access_token": args.token},
            files=[("file", fn, content)],
            timeout=120,
        )
        if st in (200, 201):
            ok += 1
            log("   ✅ 上传附件 %s（%d 字节）" % (fn, len(content)))
        else:
            log("::error::上传附件 %s 失败（HTTP %s）：%s" % (fn, st, body))
            return 1

    log("🎉 Gitee Release %s 同步完成，共同步 %d 个附件" % (args.tag, ok))
    return 0


if __name__ == "__main__":
    sys.exit(main())
