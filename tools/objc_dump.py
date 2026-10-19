#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""从抖音 IPA 的 AwemeCore 里导出 ObjC 类名/方法名(证据链复现工具)。

用法:
    python tools/objc_dump.py <ipa 路径> [输出目录]

做法:解析 AwemeCore 的 Mach-O 载入命令,定位 __TEXT,__objc_classname 与
__TEXT,__objc_methname 两个节,顺序解压到该偏移后只读取这两个节,避免把
1GB 二进制落盘。输出 classnames.txt / methnames.txt,可直接 grep。
"""
import struct
import sys
import zipfile
from pathlib import Path

CORE = "Payload/Aweme.app/Frameworks/AwemeCore.framework/AwemeCore"


def parse_sections(head: bytes):
    ncmds = struct.unpack_from("<I", head, 16)[0]
    off = 32
    sections = {}
    cryptid = None
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", head, off)
        if cmdsize == 0:
            break
        if cmd == 0x19:  # LC_SEGMENT_64
            nsects = struct.unpack_from("<I", head, off + 64)[0]
            so = off + 72
            for _ in range(nsects):
                sname = head[so:so + 16].rstrip(b"\0").decode("utf-8", "replace")
                size = struct.unpack_from("<Q", head, so + 40)[0]
                soff = struct.unpack_from("<I", head, so + 48)[0]
                if not sname.startswith("__debug"):
                    sections[sname] = (soff, size)
                so += 80
        elif cmd == 0x2C:  # LC_ENCRYPTION_INFO_64
            cryptid = struct.unpack_from("<I", head, off + 16)[0]
        off += cmdsize
    return sections, cryptid


def read_range(f, target: int, length: int) -> bytes:
    pos = 0
    chunk = 8 * 1024 * 1024
    while pos < target:
        data = f.read(min(chunk, target - pos))
        if not data:
            break
        pos += len(data)
    return f.read(length)


def strings(blob: bytes):
    for raw in blob.split(b"\0"):
        if len(raw) > 2 and all(32 < c < 127 for c in raw):
            yield raw.decode()


def main():
    if len(sys.argv) < 2:
        sys.exit("用法: python tools/objc_dump.py <ipa 路径> [输出目录]")
    ipa = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("objc_dump")
    out.mkdir(parents=True, exist_ok=True)

    zf = zipfile.ZipFile(ipa)
    f = zf.open(CORE)
    head = f.read(4 * 1024 * 1024)
    sections, cryptid = parse_sections(head)
    if cryptid not in (0, None):
        sys.exit("二进制未解密(cryptid=%s),无法导出类名" % cryptid)
    if "__objc_classname" not in sections or "__objc_methname" not in sections:
        sys.exit("未找到 ObjC 名字节")

    meth_off, meth_size = sections["__objc_methname"]
    cls_off, cls_size = sections["__objc_classname"]
    meth = read_range(f, meth_off, meth_size)
    cls = read_range(f, cls_off, cls_size)

    classes = sorted(set(strings(cls)))
    methods = sorted(set(strings(meth)))
    (out / "classnames.txt").write_text("\n".join(classes), encoding="utf-8")
    (out / "methnames.txt").write_text("\n".join(methods), encoding="utf-8")
    print("classname 节 @0x%x (%d B) / methname 节 @0x%x (%d B)"
          % (cls_off, cls_size, meth_off, meth_size))
    print("类名 %d 条 / 方法名 %d 条 → %s" % (len(classes), len(methods), out))


if __name__ == "__main__":
    main()
