#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""福袋助手静态自检(无 iOS 工具链环境下的替代校验)。

检查项:
  1. 去注释/去字符串后的 () {} [] 平衡
  2. @interface / @implementation / @end 配对,%hook / %end 配对
  3. 自有类方法调用是否都有声明或实现
  4. FudaiConfig 属性访问是否都存在同名 @property
用法: python tools/fu_check.py
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"


def strip_code(text: str) -> str:
    out = []
    i, n = 0, len(text)
    mode = 0  # 0 code, 1 str, 2 chr, 3 line comment, 4 block comment
    while i < n:
        ch = text[i]
        if mode == 0:
            if ch == '"':
                mode = 1
            elif ch == "'":
                mode = 2
            elif ch == "/" and i + 1 < n and text[i + 1] == "/":
                mode = 3
                i += 1
            elif ch == "/" and i + 1 < n and text[i + 1] == "*":
                mode = 4
                i += 1
            else:
                out.append(ch)
        elif mode == 1:
            if ch == "\\":
                i += 1
            elif ch == '"':
                mode = 0
        elif mode == 2:
            if ch == "\\":
                i += 1
            elif ch == "'":
                mode = 0
        elif mode == 3:
            if ch == "\n":
                mode = 0
                out.append(ch)
        elif mode == 4:
            if ch == "*" and i + 1 < n and text[i + 1] == "/":
                mode = 0
                i += 1
        i += 1
    return "".join(out)


problems = []

files = sorted(list(SRC.glob("*.h")) + list(SRC.glob("*.m")) + list(SRC.glob("*.x")))
print("检查文件:", ", ".join(f.name for f in files))

raw = {}
for f in files:
    text = f.read_text(encoding="utf-8")
    code = strip_code(text)
    raw[f.name] = (text, code)

    for opener, closer, label in (("{", "}", "花括号"), ("(", ")", "圆括号"), ("[", "]", "方括号")):
        depth = 0
        for ln, line in enumerate(code.split("\n"), 1):
            depth += line.count(opener) - line.count(closer)
            if depth < 0:
                problems.append(f"{f.name}:{ln} {label}提前闭合")
                depth = 0
        if depth != 0:
            problems.append(f"{f.name} {label}未闭合(剩余 {depth})")

    ifaces = len(re.findall(r"@interface", code))
    impls = len(re.findall(r"@implementation", code))
    ends = len(re.findall(r"@end", code))
    if ifaces + impls != ends:
        problems.append(f"{f.name} @interface({ifaces}) + @implementation({impls}) != @end({ends})")
    hooks = len(re.findall(r"%hook", code))
    hook_ends = len(re.findall(r"%end", code))
    if f.suffix == ".x" and hooks != hook_ends:
        problems.append(f"{f.name} %hook({hooks}) != %end({hook_ends})")

# ---- 自有类方法声明表 ----
CLASS_DECL = {}
for name, (text, code) in raw.items():
    for m in re.finditer(r"@interface\s+(\w+)\s*(?:\([^)]*\))?\s*(?::\s*\w+)?(.*?)@end",
                         text, re.S):
        cls, body = m.group(1), m.group(2)
        body_code = strip_code(body)
        selectors = set()
        for sm in re.finditer(r"[-+]\s*\([^)]*\)\s*([A-Za-z_][\w:]*)", body_code):
            selectors.add(sm.group(1))
        # 属性也当作 setter/getter 可用
        for pm in re.finditer(r"@property\s*\(([^)]*)\)\s*[\w<>\*,\s]*?\b(\w+)\s*;", body_code):
            attrs = pm.group(1)
            prop = pm.group(2)
            selectors.add(prop)
            if "readonly" not in attrs:
                selectors.add("set" + prop[0].upper() + prop[1:] + ":")
        CLASS_DECL.setdefault(cls, set()).update(selectors)
    for m in re.finditer(r"@implementation\s+(\w+)", code):
        cls = m.group(1)
        body = code[m.end():]
        end = body.find("@end")
        body = body[:end] if end >= 0 else body
        selectors = set()
        for sm in re.finditer(r"[-+]\s*\([^)]*\)\s*([A-Za-z_][\w:]*)", body):
            selectors.add(sm.group(1))
        CLASS_DECL.setdefault(cls, set()).update(selectors)

our_classes = set(CLASS_DECL.keys())
print("自有类:", ", ".join(sorted(our_classes)))

# ---- 调用点校验:[Class sel...] ----
CALL_RE = re.compile(r"\[\s*(\w+)\s+([A-Za-z_][\w]*)")
for name, (text, code) in raw.items():
    # 只检查以类名(message to class)形式出现的调用
    for cm in CALL_RE.finditer(code):
        cls, sel = cm.group(1), cm.group(2)
        if cls not in our_classes:
            continue
        declared = CLASS_DECL.get(cls, set())
        declared_bases = {d.split(":")[0] for d in declared}
        if sel in declared or sel in declared_bases:
            continue
        # 允许 setter 形式 setXxx: 与属性
        if sel.startswith("set") and sel[3:4].isupper():
            cand = sel[3].lower() + sel[4:]
            if cand in declared:
                continue
        # alloc/init/new 等运行时消息
        if sel in ("alloc", "new", "class", "shared", "superclass", "respondsToSelector",
                   "instancesRespondToSelector", "description"):
            continue
        problems.append(f"{name}: [{cls} {sel}...] 未在 {cls} 的 @interface/@implementation 中声明")

# ---- 向 FuXxx 发消息时必须是已声明的类(防止把宏名当类名用) ----
var_names = set()
for name, (text, code) in raw.items():
    for vm in re.finditer(r"(?:static\s+)?[A-Za-z_]\w*(?:\s*<[^>]*>)?\s*\*?\s*(Fu\w+)\s*[=;,)]", code):
        var_names.add(vm.group(1))
    for vm in re.finditer(r"\bstatic\s+\w+\s*\*?\s*(Fu\w+)\s*=", code):
        var_names.add(vm.group(1))
for name, (text, code) in raw.items():
    for cm in re.finditer(r"\[\s*(Fu[A-Za-z]\w*)\s+[A-Za-z_]", code):
        ident = cm.group(1)
        if ident in our_classes or ident in var_names:
            continue
        problems.append(f"{name}: [{ident} ...] 既不是已声明类也不是变量(宏名当类名?)")

# ---- FudaiConfig 属性访问校验 ----
cfg_props = set()
cfg_text, cfg_code = raw["FudaiConfig.h"]
for pm in re.finditer(r"@property\s*\(([^)]*)\)\s*[\w<>\*,\s]*?\b(\w+)\s*;", cfg_code):
    cfg_props.add(pm.group(2))
for name, (text, code) in raw.items():
    for am in re.finditer(r"\bcfg\.(\w+)", code):
        prop = am.group(1)
        if prop not in cfg_props:
            problems.append(f"{name}: cfg.{prop} 不是 FudaiConfig 的属性")
    for am in re.finditer(r"\[FudaiConfig shared\]\.(\w+)", code):
        prop = am.group(1)
        if prop not in cfg_props:
            problems.append(f"{name}: [FudaiConfig shared].{prop} 不是 FudaiConfig 的属性")
print("FudaiConfig 属性数:", len(cfg_props))

# ---- 宏映射一致性 ----
macro_pairs = re.findall(r"#define\s+(Fudai\w+)\s+(Fu[0-9A-F]+)", cfg_code)
seen = {}
for orig, mangled in macro_pairs:
    if mangled in seen and seen[mangled] != orig:
        problems.append(f"宏冲突: {mangled} 同时映射 {seen[mangled]} 与 {orig}")
    seen[mangled] = orig
print("混淆宏:", len(macro_pairs))

if problems:
    print("\n发现问题 %d 项:" % len(problems))
    for p in problems:
        print("  -", p)
    sys.exit(1)
print("\n静态自检通过")
