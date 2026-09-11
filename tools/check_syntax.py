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
    # continue -> Lua has no continue; goto is close enough for a PARSE check.
    src = re.sub(r'\bcontinue\b', "--[[continue]]", src)
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
    src = re.sub(r'(\([^()\n]*?)\s*:\s*[\w.<>{}|?\[\]]+(\s*[,)])', r'\1\2', src)
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


def main() -> int:
    lua = lupa.LuaRuntime(unpack_returned_tuples=False)
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
