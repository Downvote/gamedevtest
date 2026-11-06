#!/usr/bin/env python3
"""Embed the Rojo tree (from a sourcemap.json) and every script source into one Luau module.
Usage: gen_sources.py <repo> <sourcemap.json> <out.luau>

A file the project maps to more than one place (src/shared/Render/PixelFont.luau is also ReplicatedFirst.Loading's,
default.project.json) becomes one ModuleScript in each place, as in Roblox, each with its own copy of the module when
required; its text is embedded once (a long string in the table F, the nodes refer to it)."""
import json
import os
import sys

repo, smap, out = sys.argv[1], sys.argv[2], sys.argv[3]
tree = json.load(open(smap, encoding="utf-8"))

def long_str(s):
    level = 0
    while ("]" + "=" * level + "]") in s:
        level += 1
    eq = "=" * level
    # a leading newline right after the opening bracket is dropped by Lua; add one so line 1 stays line 1
    return "[" + eq + "[\n" + s + "]" + eq + "]"

def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'

def script_file(node):
    files = [f for f in node.get("filePaths", []) if f.endswith(".luau") or f.endswith(".lua")]
    if files and node["className"] in ("ModuleScript", "Script", "LocalScript"):
        return files[0]
    return None

# files mapped more than once: their text goes in F once
uses = {}
def count(node):
    f = script_file(node)
    if f:
        uses[f] = uses.get(f, 0) + 1
    for k in node.get("children", []):
        count(k)
count(tree)
shared = {}
head = []
for f in sorted(uses):
    if uses[f] > 1:
        shared[f] = len(shared) + 1
        head.append("F[%d] = %s" % (shared[f], long_str(open(os.path.join(repo, f), encoding="utf-8").read())))

parts = []
counted = [0]

def emit(node, indent):
    pad = "\t" * indent
    fields = ["name=" + lua_str(node["name"]), "className=" + lua_str(node["className"])]
    f = script_file(node)
    if f:
        fields.append("file=" + lua_str(f))
        if f in shared:
            fields.append("src=F[%d]" % shared[f])
        else:
            fields.append("src=" + long_str(open(os.path.join(repo, f), encoding="utf-8").read()))
        counted[0] += 1
    kids = node.get("children", [])
    if kids:
        parts.append(pad + "{" + ", ".join(fields) + ", children={")
        for k in kids:
            emit(k, indent + 1)
        parts.append(pad + "}},")
    else:
        parts.append(pad + "{" + ", ".join(fields) + "},")

parts.append("return")
emit(tree, 0)
text = "\n".join(parts)
text = text[: text.rstrip().rfind(",")] if text.rstrip().endswith(",") else text
if head:
    text = "local F = {}\n" + "\n".join(head) + "\n" + text
open(out, "w", encoding="utf-8").write(text + "\n")
print("scripts", counted[0], "files mapped twice", len(shared))
