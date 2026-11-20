#!/usr/bin/env python3
# scripts/locale_strings.py: the words the game can put on screen, for the Lang spec's check that every language has
# them (docs/LOCALIZATION.md 6).
#
#   python3 scripts/locale_strings.py <out.luau>      the list as a Luau module (scripts/check.sh writes it into
#                                                     build/luautest for tests/specs/Lang.spec.luau)
#   python3 scripts/locale_strings.py --list          the list, one per line (what the check looks at)
#
# A word is any string literal in src/first (the loading card), src/client, src/server and
# src/shared/{Data,Logic,Config} that is not a name the code looks things up by (FindFirstChild("Shelf"),
# Instance.new("Frame"), .Name = "Face", an id, a path, a sprite's pixels, a log line), and every chain of literals and
# values ("Sold " .. n is the template "Sold {1}"; string.format's %s / %d are {n} too). locale/ignore.txt lists
# what is never shown (one per line, exactly as listed by --list): the check skips those.
import os, re, sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
DIRS = ["src/first", "src/client", "src/server", "src/shared/Data", "src/shared/Logic", "src/shared/Config"]
SKIP_FILES = {"ArtData.luau", "ThumbData.luau", "CosmeticThumbData.luau", "LoadingArt.luau", "Audio.luau"}  # sprite pixels and sound names, no words

TOK = re.compile(r'''--\[(=*)\[.*?\]\1\]|--[^\n]*|"(?:[^"\\\n]|\\.)*"|'(?:[^'\\\n]|\\.)*'|\[(=*)\[.*?\]\2\]|\.\.\.|\.\.|[A-Za-z_][A-Za-z0-9_]*|\d[\d.]*|==|~=|<=|>=|\n|\S''', re.S)
LEFT_STOP = {"=", ",", "(", "{", "[", "return", "then", "else", "do", "and", "or", "not", "local", "in", "==", "~=", "<",
             ">", "<=", ">=", ";", "if", "elseif", "while", "until"}
RIGHT_STOP = {",", ")", "}", "]", "then", "else", "elseif", "end", "do", "and", "or", "==", "~=", "<", ">", "<=", ">=",
              ";", "="}
OPEN, CLOSE = {"(", "{", "["}, {")", "}", "]"}
# calls whose string argument is a name the code looks something up by, or a line for the output window (not
# string.format: its pattern is a template, "Make %s coins in all." is "Make {1} coins in all.")
LOOKUP_CALLS = {"FindFirstChild", "WaitForChild", "FindFirstChildOfClass", "FindFirstChildWhichIsA", "FindFirstAncestor",
                "FindFirstAncestorOfClass", "FindFirstAncestorWhichIsA", "GetAttribute", "SetAttribute", "GetService",
                "IsA", "GetPropertyChangedSignal", "new", "require", "warn", "print", "error", "assert", "log", "sound",
                "pxSprite", "sprite", "spriteSize", "color", "shade", "find", "match", "gsub", "gmatch", "split",
                "rep", "byte", "char", "GetMouse", "BindAction", "UnbindAction", "BindToRenderStep",
                "UnbindFromRenderStep", "getD", "fire", "on", "onAny", "send", "request", "invoke", "path", "icon",
                "SetCore", "GetCore", "RegisterEvent", "Connect", "tag", "Signal", "remote", "event", "action",
                "warnOnce", "recordError", "safe", "guard", "try", "report", "picture", "portrait", "customerPortrait",
                "roomPreview", "snapIcon", "snapLabel", "isNew", "checkBought", "useMock", "stopWorkers", "Funnel",
                "track", "count", "SetCoreGuiEnabled", "GetFullName", "safeCall", "badge", "px", "canvas", "model", "part",
                "registerPanel", "image", "anim", "has", "play", "stop", "openPanel", "debugTip", "mod", "modOr"}


def unq(t):
    if t.startswith("["):
        return re.sub(r"^\[=*\[|\]=*\]$", "", t)
    s = t[1:-1]
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            out.append({"n": "\n", "t": "\t", "\\": "\\", '"': '"', "'": "'"}.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return "".join(out)


def is_str(t):
    return t[:1] in "\"'" or re.match(r"^\[=*\[", t) is not None


def fmt_template(s):
    # string.format's %s / %d / %.1f ... as {n}; %% as %
    n = [0]

    def rep(m):
        if m.group(0) == "%%":
            return "%"
        n[0] += 1
        return "{%d}" % n[0]

    return re.sub(r"%%|%[-+ #0]*\d*(?:\.\d+)?[sdifgxXq]", rep, s)


def scan(path, client=False):
    text = open(path, encoding="utf-8").read()
    toks, lines, line = [], [], 1
    for m in TOK.finditer(text):
        t = m.group(0)
        if not t.startswith("--"):
            toks.append(t)
            lines.append(line)
        line += t.count("\n")
    # a chain that goes on over lines: the line breaks beside a .. do not end it
    keep = [i for i, t in enumerate(toks) if not (t == "\n" and ((i > 0 and toks[i - 1] == "..") or (i + 1 < len(toks) and toks[i + 1] == "..")))]
    toks = [toks[i] for i in keep]
    lines = [lines[i] for i in keep]
    found, used, n, i = [], set(), len(toks), 0
    while i < n:
        if toks[i] != "..":
            i += 1
            continue
        j, depth = i - 1, 0
        while j >= 0:
            t = toks[j]
            if t in CLOSE:
                depth += 1
            elif t in OPEN:
                if depth == 0:
                    break
                depth -= 1
            elif depth == 0 and (t in LEFT_STOP or t == "\n"):
                break
            j -= 1
        start = j + 1
        ops, cur, k, depth = [], [], start, 0
        while k < n:
            t = toks[k]
            if t in OPEN:
                depth += 1
                cur.append(k)
                k += 1
                continue
            if t in CLOSE:
                if depth == 0:
                    break
                depth -= 1
                cur.append(k)
                k += 1
                continue
            if depth == 0 and t == "..":
                ops.append(cur)
                cur = []
            elif depth == 0 and t in RIGHT_STOP and cur:
                break
            elif depth == 0 and t == "\n":
                break
            elif t != "\n":
                cur.append(k)
            k += 1
        if cur:
            ops.append(cur)
        before = toks[start - 1] if start > 0 else ""
        before2 = toks[start - 2] if start > 1 else ""
        if len(ops) >= 2 and not (before == "(" and before2 in LOOKUP_CALLS):
            parts, slot, lit = [], 0, False
            for op in ops:
                if len(op) == 1 and is_str(toks[op[0]]):
                    parts.append(unq(toks[op[0]]))
                    used.add(op[0])
                    lit = True
                else:
                    slot += 1
                    parts.append("{%d}" % slot)
            if lit:
                found.append(("".join(parts), lines[start], True))
        elif len(ops) >= 2:
            for op in ops:
                for t_i in op:
                    if is_str(toks[t_i]):
                        used.add(t_i)
        i += 1  # on to the next .., chains inside this one too ("(" .. dur .. " left)")
    for idx, t in enumerate(toks):
        if not is_str(t) or idx in used:
            continue
        prev = toks[idx - 1] if idx > 0 else ""
        prev2 = toks[idx - 2] if idx > 1 else ""
        nxt = toks[idx + 1] if idx + 1 < n else ""
        if prev == "(" and prev2 in LOOKUP_CALLS:
            continue
        if prev == "[" and nxt == "]":  # a table key
            continue
        if prev in ("==", "~=") or nxt in ("==", "~="):  # an id compared
            continue
        if prev == "=" and prev2 == "Name":  # an Instance's name
            continue
        # a UIKit option's instance name ({ name = "Words" }) in the client: one word, never shown ("VIP" is a pass's
        # name in the Store's list; names with a space are those passes' and products' names, shown)
        if client and prev == "=" and prev2 == "name" and " " not in unq(t) and unq(t) != "VIP":
            continue
        s = unq(t)
        if prev == "(" and prev2 == "format":
            s = fmt_template(s)
        found.append((s, lines[idx], False))
    return found


def wanted(s):
    # a {n} glued after a word is an English plural ("find{2}": "" or "s") or an optional phrase stuck on: no
    # language can take those as they are; their whole strings are in the tables (the catalog's runtime capture)
    if re.search(r"[a-z]{3,}\{\d+\}|\{\d+\}[A-Z][a-z]", s):
        return False
    if len(re.findall(r"[A-Za-z]", re.sub(r"\{\d+\}", "", s))) < 2:
        return False
    core = re.sub(r"\{\d+\}", "", s)
    if re.fullmatch(r"[a-z_][A-Za-z0-9_]*", core):  # an id ("golden", "auto_roll")
        return False
    if re.search(r"rbxasset|rbxthumb|https?:|\.luau|::|^[A-Za-z]+\.[A-Za-z.]+$", s):  # paths, Enum.Font.X
        return False
    if re.search(r"[_/\\]", core) and " " not in core:  # an id or a path ("PP_Save", "a/b")
        return False
    if re.fullmatch(r"[.#A-Za-z0-9]+", core) and (core.count(".") >= 2 or re.search(r"\d", core) or re.search(r"(.)\1\1", core)):
        return False  # a sprite's pixel rows ("..kGGk..", "k2222k")
    if re.fullmatch(r"[^\sA-Za-z]*[A-Za-z][a-z]*[A-Z][A-Za-z0-9]*", core) and " " not in core:  # CamelCase names
        return False
    if re.match(r"^[\[\]<]", core) and "font" not in core:  # log prefixes "[Hud]"
        return False
    if re.match(r"^[A-Za-z#-]+:\S", s) or re.match(r"^[a-z]+:$", s):  # an id ("desk:plate:{1}", "grade:AA")
        return False
    if s.startswith("^") or re.search(r"%[adswlupx]|%[-+]?\d*\.?\d*[dfs]|\(%", s):  # a Lua pattern or a format
        return False
    if re.search(r"\b(failed|ignored|refused|unknown|unavailable|timed out|no handler|expected [a-z]+$|bad [a-z]+$|out of range|not a dense)\b", s):
        return False  # a line for the output window
    return True


def collect():
    out = {}
    for d in DIRS:
        for dp, _, fs in os.walk(os.path.join(ROOT, d)):
            for f in sorted(fs):
                if not f.endswith(".luau") or f in SKIP_FILES:
                    continue
                p = os.path.join(dp, f)
                rel = os.path.relpath(p, ROOT)
                for s, line, tpl in scan(p, rel.startswith("src/client") or rel.startswith("src/first")):
                    s = s.replace("{n}", "{1}")  # a task's count (Data/Rewards: "Sell {n} driftlings")
                    if wanted(s) and s not in out:
                        out[s] = "%s:%d" % (rel, line)
    return out


def extra():
    # strings the scan cannot see (a template too short for it, "{1} h"; words put together at run time), one per line
    # in locale/extra.txt ("\\n" for a line break; lines starting "# " are notes)
    p = os.path.join(ROOT, "locale", "extra.txt")
    out = {}
    if os.path.exists(p):
        for ln in open(p, encoding="utf-8").read().split("\n"):
            if ln and not ln.startswith("# "):
                out[ln.replace("\\n", "\n")] = "locale/extra.txt"
    return out


def ignored():
    p = os.path.join(ROOT, "locale", "ignore.txt")
    if not os.path.exists(p):
        return set()
    out = set()
    for ln in open(p, encoding="utf-8").read().split("\n"):
        if ln and not ln.startswith("# "):
            out.add(ln.replace("\\n", "\n"))
    return out


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\r", "").replace("\t", "\\t") + '"'


def main():
    words = collect()
    for s, where in extra().items():
        words.setdefault(s, where)
    skip = ignored()
    rows = [(s, where) for s, where in sorted(words.items()) if s not in skip]
    if sys.argv[1:] == ["--list"]:
        for s, where in rows:
            print("%s\t%s" % (s.replace("\n", "\\n"), where))
        return
    out = sys.argv[1]
    body = ["-- GENERATED by scripts/locale_strings.py: the words the game can show (docs/LOCALIZATION.md 6).", "return {"]
    for s, where in rows:
        body.append("\t{ s = %s, at = %s }," % (lua_str(s), lua_str(where)))
    body.append("}")
    open(out, "w", encoding="utf-8").write("\n".join(body) + "\n")


if __name__ == "__main__":
    main()
