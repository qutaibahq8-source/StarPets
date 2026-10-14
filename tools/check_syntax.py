#!/usr/bin/env python3
"""Parse every Luau file in the project.

A syntax error in a server Script is not a small thing in Roblox: the script
does not run at all, so the map never builds, no remotes are created, and the
game comes up as an empty baseplate. From the outside that is indistinguishable
from "nothing changed", which is the single most expensive failure this project
has had.

Lua 5.4 is not Luau, so the handful of Luau-only constructs this codebase uses
are rewritten into equivalent Lua before parsing. The rewrite is deliberately
narrow — it only touches syntax, never semantics — because a transpiler that
quietly changes what the code MEANS would make every check built on top of it
worthless.
"""
import re
import sys
from pathlib import Path

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed (pip install lupa)")

ROOT = Path(__file__).resolve().parent.parent


_LONG_OPEN = re.compile(r'\[(=*)\[')
_WORD = re.compile(r'[A-Za-z_]\w*')
_NUMBER = re.compile(r'0[xX][0-9a-fA-F_]+|\d[\d_]*(?:\.\d*)?(?:[eE][+-]?\d+)?|\.\d+')


def _code_tokens(src):
    """(start, word) for every identifier/keyword OUTSIDE strings and comments,
    plus (start, '.'/':') for the punctuation that makes `x.continue` a field."""
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith("--", i):
            m = _LONG_OPEN.match(src, i + 2)
            if m:
                close = "]" + m.group(1) + "]"
                j = src.find(close, m.end())
                i = n if j < 0 else j + len(close)
            else:
                j = src.find("\n", i)
                i = n if j < 0 else j
            continue
        m = _LONG_OPEN.match(src, i)
        if m:
            close = "]" + m.group(1) + "]"
            j = src.find(close, m.end())
            i = n if j < 0 else j + len(close)
            continue
        if c in "\"'`":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            i = j + 1
            continue
        m = _NUMBER.match(src, i) if c.isdigit() or (c == "." and i + 1 < n and src[i + 1].isdigit()) else None
        if m:
            i = m.end()
            continue
        m = _WORD.match(src, i)
        if m:
            yield i, m.group(0)
            i = m.end()
            continue
        if c in ".:":
            yield i, c
        i += 1


def _rewrite_continue(src):
    """Luau's `continue`, as Lua: a goto to a label at the end of its loop.

    It used to be rewritten as a COMMENT, which deleted it: the rest of the
    loop body ran anyway. Every check is built on this transpiler, so every
    loop that skips with `continue` was tested doing what it skips —
    CurrencyService's auto-collect, gated to the gamepass by a `continue`,
    collected for every player under test. It also rewrote the word inside
    strings. This walks the real tokens, leaves strings and comments alone,
    and keeps every line where it was, so error line numbers still match.
    """
    stack, edits, expect_do, prev, uid = [], [], False, None, 0
    for pos, tok in _code_tokens(src):
        if tok in (".", ":"):
            prev = tok
            continue
        if prev in (".", ":"):
            prev = None
            continue  # a field or method name, not a keyword
        prev = None
        if tok in ("for", "while"):
            stack.append({"kind": "loop", "label": None})
            expect_do = True
        elif tok == "do":
            if expect_do:
                expect_do = False
            else:
                stack.append({"kind": "do"})
        elif tok in ("if", "function"):
            stack.append({"kind": tok})
        elif tok == "repeat":
            stack.append({"kind": "repeat", "label": None})
        elif tok in ("end", "until") and stack:
            blk = stack.pop()
            if blk.get("label"):
                edits.append((pos, 0, "::%s:: " % blk["label"]))
        elif tok == "continue":
            for blk in reversed(stack):
                if blk["kind"] == "function":
                    break
                if blk["kind"] in ("loop", "repeat"):
                    if not blk["label"]:
                        uid += 1
                        blk["label"] = "__continue_%d" % uid
                    edits.append((pos, len("continue"), "goto " + blk["label"]))
                    break
    for pos, length, text in sorted(edits, reverse=True):
        src = src[:pos] + text + src[pos + length:]
    return src


def luau_to_lua(src: str) -> str:
    """Rewrite Luau-only syntax into Lua 5.4 that parses the same way."""
    # Compound assignment: x += 1  ->  x = x + 1
    src = re.sub(
        r'^(\s*)([\w.\[\]"\']+?)\s*([+\-*/%])=\s*(.+?)$',
        lambda m: "%s%s = %s %s (%s)" % (m.group(1), m.group(2), m.group(2),
                                         m.group(3), m.group(4).rstrip()),
        src, flags=re.M)
    # String concat assignment: s ..= x  ->  s = s .. (x)
    src = re.sub(
        r'^(\s*)([\w.\[\]"\']+?)\s*\.\.=\s*(.+?)$',
        lambda m: "%s%s = %s .. (%s)" % (m.group(1), m.group(2), m.group(2),
                                         m.group(3).rstrip()),
        src, flags=re.M)
    # continue -> a goto to the end of its loop (see _rewrite_continue).
    src = _rewrite_continue(src)
    # Type annotations on locals:  local x: Foo = 1  ->  local x = 1
    src = re.sub(r'\blocal\s+([\w\s,]+?)\s*:\s*[\w.<>{}|?\s,\[\]()]+?=', r'local \1 =', src)
    # Function parameter and return types.
    #
    # The return-type rule has to be narrow. `): Foo` and `):format(x)` look
    # alike to a loose pattern, and an early version of this stripped the
    # method call off any `(...)` followed by `:method(` on the next line —
    # silently deleting real code and then reporting a syntax error in the
    # wreckage. So: the colon must be on the SAME line as the paren (no newline
    # in the gap), and what follows must run to the end of the line rather than
    # into a `(`, which is what makes it a type and not a call.
    src = re.sub(
        r'\)[ \t]*:[ \t]*[\w.<>{}|?\[\]]+(?:[ \t]*[|,][ \t]*[\w.<>{}|?\[\]]+)*'
        r'(?=[ \t]*(?:\n|--))',
        ')', src)
    # Parameter types: (a: number, b: string) -> (a, b).
    #
    # The character class excludes quotes, and that is not cosmetic. A call
    # whose first argument is a string containing ": word," —
    # `w("  StarPetsMap: present, baked=%s", x)` — looks exactly like a typed
    # parameter list to a looser pattern, which rewrote it to
    # `w("  StarPetsMap, baked=%s", x)`. The file still parsed, the test still
    # ran, and it silently measured a string the source never contained. A
    # parameter list cannot hold a quote, so this cannot.
    src = re.sub(r'(\([^()\n"\']*?)\s*:\s*[\w.<>{}|?\[\]]+(\s*[,)])', r'\1\2', src)
    # export type / type alias declarations.
    src = re.sub(r'^\s*(export\s+)?type\s+\w+\s*=.*$', "", src, flags=re.M)
    # Luau string interpolation is not used here; if it appears, flag rather
    # than silently mangling it.
    return src


def check(path: Path, lua) -> str | None:
    src = path.read_text()
    if "`" in src and re.search(r"`[^`\n]*\{", src):
        return "uses Luau string interpolation, which this checker cannot parse"
    try:
        lua.eval("function(s, n) return assert(load(s, n)) end")(
            luau_to_lua(src), "@" + path.name)
    except Exception as e:
        return str(e).splitlines()[0][:220]
    return None


CONTINUE_PROBE = '''
local out = {}
for i = 1, 6 do
	if i % 2 == 0 then continue end
	local sq = i * i
	for j = 1, 3 do
		if j == 2 then continue end
		out[#out + 1] = i * 10 + j
	end
	if i == 5 then break end
end
local k = 0
while k < 4 do
	k += 1
	if k == 2 then continue end
	local f = function(x) return x end
	out[#out + 1] = f(100 + k)
end
local said = "Send again to continue."
return table.concat(out, ","), said
'''
CONTINUE_WANT = ("11,13,31,33,51,53,101,103,104", "Send again to continue.")


def transpiler_keeps_meaning(lua):
    """The rewrite must not change what code DOES. Run code that leans on
    continue — nested, in a while, beside break, inside a string — and compare
    with what Luau would give."""
    got = lua.eval("function(s) return assert(load(s))() end")(
        luau_to_lua(CONTINUE_PROBE))
    got = (str(got[0]), str(got[1])) if isinstance(got, tuple) else (str(got), "")
    return None if got == CONTINUE_WANT else (
        "continue is translated wrongly: got %s, Luau gives %s" % (got, CONTINUE_WANT))


def main() -> int:
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    err = transpiler_keeps_meaning(lua)
    if err:
        print("   x the transpiler every check is built on: " + err)
        return 1
    print("transpiler: continue keeps its meaning (nested, while, break, strings)")
    files = sorted(ROOT.glob("src/**/*.lua"))
    bad = []
    for f in files:
        err = check(f, lua)
        if err:
            bad.append((f, err))
    print("parsed %d Luau files" % len(files))
    if bad:
        print("\n%d file(s) DO NOT PARSE — in Roblox these do not run at all:" % len(bad))
        for f, e in bad:
            print("   x %-40s %s" % (f.relative_to(ROOT), e))
        return 1
    print("syntax: every file parses")
    return 0


if __name__ == "__main__":
    sys.exit(main())
