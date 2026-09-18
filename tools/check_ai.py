#!/usr/bin/env python3
"""Run the Claude-in-Studio panel against a simulated Studio and a fake API.

This plugin is the only thing that lets an assistant see and change the open
place, and it holds an API key while it does it. Both halves of that are worth
proving rather than assuming, because both fail silently: a malformed request
comes back as "the API rejected it" with no clue why, and a key that leaks into
Output looks exactly like a key that did not.

Checked here:
  1. THE REQUEST IS WELL FORMED   key header, version header, model, and four
                                  tools whose schemas encode as JSON objects
  2. THE TOOL LOOP CLOSES         a tool_use runs the tool and comes back as a
                                  tool_result with the SAME id, and the tool
                                  really read the place
  3. EDITS ARE OFF BY DEFAULT     run_luau is refused until the owner allows it,
                                  and the place is untouched
  4. EDITS WORK WHEN ALLOWED      the part actually appears, in one undo step
  5. NEVER DURING PLAY            Studio discards Play-mode changes, so a change
                                  made then would appear to work and vanish
  6. THE KEY NEVER ESCAPES        not into Output, not into the transcript, not
                                  into an error message quoting a failed call
"""
import json
import sys
from pathlib import Path

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed (pip install lupa)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check_syntax import luau_to_lua  # noqa: E402

KEY = "sk-ant-api03-TOTALLY-FAKE-KEY-FOR-THE-TEST-0000"


# ------------------------------------------------------------------
# JSON across the Lua/Python line
# ------------------------------------------------------------------
def from_lua(obj):
    """Lua table -> Python, the way Roblox's JSONEncode sees it.

    An empty table encodes as [] in Roblox, not {}. That is not a detail: it is
    why a tool call with no arguments corrupts the next request, and the plugin
    guards against it. Reproducing it here is what makes that guard testable.
    """
    if lupa.lua_type(obj) == "table":
        keys = list(obj.keys())
        if not keys:
            return []
        if all(isinstance(k, int) for k in keys) and \
                sorted(keys) == list(range(1, len(keys) + 1)):
            return [from_lua(obj[i]) for i in range(1, len(keys) + 1)]
        return {str(k): from_lua(obj[k]) for k in keys}
    return obj


def to_lua(lua, obj):
    if isinstance(obj, dict):
        t = lua.eval("{}")
        for k, v in obj.items():
            t[k] = to_lua(lua, v)
        return t
    if isinstance(obj, list):
        t = lua.eval("{}")
        for i, v in enumerate(obj, 1):
            t[i] = to_lua(lua, v)
        return t
    return obj


# ------------------------------------------------------------------
# A Studio-shaped world with a fake Anthropic API behind HttpService
# ------------------------------------------------------------------
class Studio:
    def __init__(self, playing=False, responses=None):
        self.requests = []
        self.responses = list(responses or [])
        self.lua = lupa.LuaRuntime(unpack_returned_tuples=False)
        G = self.lua.globals()
        self.mock = self.lua.execute((ROOT / "tools" / "roblox_mock.lua").read_text())
        for k in ("Instance", "game", "workspace", "Color3", "Vector3", "Enum",
                  "UDim", "UDim2", "TweenInfo", "DockWidgetPluginGuiInfo",
                  "settings"):
            G[k] = self.mock[k]

        self.lua.execute("""
            OUT, WARN = {}, {}
            print = function(...) local p={} for i=1,select('#',...) do p[i]=tostring((select(i,...))) end
                OUT[#OUT+1]=table.concat(p,' ') end
            warn = function(...) local p={} for i=1,select('#',...) do p[i]=tostring((select(i,...))) end
                WARN[#WARN+1]=table.concat(p,' ') end
            -- task.spawn must actually run, or pressing Send does nothing and
            -- every assertion after it passes vacuously.
            task = { spawn=function(f, ...) return f(...) end,
                     wait=function() return 0 end, defer=function(f,...) return f(...) end,
                     delay=function(_, f, ...) return f(...) end }
            loadstring = function(src, name) return load(src, name) end
        """)

        gm = self.mock["game"]
        rsv = gm["GetService"](gm, "RunService")
        self.lua.eval(
            "function(rs, v) rawget(rs,'_p').IsRunning = function() return v end end"
        )(rsv, playing)

        # A plugin object: settings live in a table, exactly as Studio keeps
        # them per-machine.
        self.settings = {}
        G["PY_GET_SETTING"] = lambda k: self.settings.get(k)
        G["PY_SET_SETTING"] = lambda k, v: self.settings.__setitem__(k, v)
        G["PY_REQUEST"] = self._request
        G["PY_ENCODE"] = lambda t: json.dumps(from_lua(t))
        G["PY_DECODE"] = lambda s: to_lua(self.lua, json.loads(s))

        self.lua.execute("""
            local function newInstance(cls) return Instance.new(cls) end
            plugin = {
                GetSetting = function(_, k) return PY_GET_SETTING(k) end,
                SetSetting = function(_, k, v) PY_SET_SETTING(k, v) end,
                CreateToolbar = function()
                    return { CreateButton = function()
                        local b = newInstance("PluginToolbarButton")
                        b.SetActive = function() end
                        return b
                    end }
                end,
                CreateDockWidgetPluginGui = function()
                    local w = newInstance("DockWidgetPluginGui")
                    w.Enabled = true
                    return w
                end,
            }
            local hs = game:GetService("HttpService")
            hs.JSONEncode = function(_, t) return PY_ENCODE(t) end
            hs.JSONDecode = function(_, s) return PY_DECODE(s) end
            hs.RequestAsync = function(_, opts) return PY_REQUEST(opts) end
        """)

    def _request(self, opts):
        self.requests.append({
            "url": opts["Url"],
            "method": opts["Method"],
            "headers": from_lua(opts["Headers"]),
            "body": json.loads(opts["Body"]),
        })
        if not self.responses:
            raise AssertionError("the plugin made more API calls than the test "
                                 "queued responses for")
        status, payload = self.responses.pop(0)
        return to_lua(self.lua, {
            "Success": 200 <= status < 300,
            "StatusCode": status,
            "StatusMessage": "",
            "Body": json.dumps(payload) if isinstance(payload, dict) else payload,
        })

    # -- running and driving ---------------------------------------
    def load_plugin(self):
        src = luau_to_lua((ROOT / "src/Plugin/StarPetsAI.server.lua").read_text())
        self.lua.execute(src)
        self.widget = self.lua.eval("plugin:CreateDockWidgetPluginGui()")
        # The widget the plugin built is the one it parented its UI into; find
        # it by looking for the frame it created rather than trusting order.
        return self

    def descendants(self):
        gm = self.mock["game"]
        out = []
        # Everything the plugin built hangs off the widget it asked for, which
        # is not in game's tree. Walk what the plugin kept instead: the mock
        # records every Instance.new under its parent, so start from the
        # DockWidgetPluginGui the plugin made (the first one created).
        for w in self._widgets():
            out.extend(self.lua.eval("function(w) return w:GetDescendants() end")(w).values())
        _ = gm
        return out

    def _widgets(self):
        return getattr(self, "_widget_list", [])

    def find(self, **props):
        """First UI instance whose properties match."""
        for inst in self.ui:
            ok = True
            for k, want in props.items():
                got = inst[k]
                if isinstance(want, str) and want.endswith("*"):
                    if not (isinstance(got, str) and got.startswith(want[:-1])):
                        ok = False
                        break
                elif got != want:
                    ok = False
                    break
            if ok:
                return inst
        return None

    def click(self, inst):
        self.lua.eval("function(b) b.MouseButton1Click:Fire() end")(inst)

    def out(self):
        return list(self.lua.globals()["OUT"].values()) + \
               list(self.lua.globals()["WARN"].values())

    def bubbles(self):
        return [i["Text"] for i in self.ui
                if i["ClassName"] == "TextLabel" and isinstance(i["Text"], str)]


def build(playing=False, responses=None, with_key=True):
    """Load the plugin, save a key through its own UI, hand back the harness."""
    s = Studio(playing=playing, responses=responses)
    # Capture every instance the plugin creates, so the test can press its
    # buttons without the plugin having to expose them.
    created = []
    s.lua.globals()["PY_CREATED"] = created.append
    s.lua.execute("""
        local realNew = Instance.new
        Instance = setmetatable({}, { __index = function(_, k)
            if k == "new" then
                return function(cls, parent)
                    local i = realNew(cls, parent)
                    PY_CREATED(i)
                    return i
                end
            end
        end })
    """)
    src = luau_to_lua((ROOT / "src/Plugin/StarPetsAI.server.lua").read_text())
    s.lua.execute(src)
    s.ui = created

    if with_key:
        box = s.find(ClassName="TextBox", PlaceholderText="sk-ant-...")
        assert box is not None, "the key entry box was not built"
        box["Text"] = KEY
        save = s.find(ClassName="TextButton", Text="Save key")
        s.click(save)
    return s


def ask(s, text):
    box = s.find(ClassName="TextBox", PlaceholderText="Ask for a change, or ask "
                                                     "what is in the place...")
    assert box is not None, "the composer box was not built"
    box["Text"] = text
    s.click(s.find(ClassName="TextButton", Text="Send"))


def text_reply(body):
    return (200, {"id": "msg_1", "type": "message", "role": "assistant",
                  "model": "claude-opus-5", "stop_reason": "end_turn",
                  "content": [{"type": "text", "text": body}],
                  "usage": {"input_tokens": 10, "output_tokens": 5}})


def tool_reply(name, tool_input, tid="toolu_1"):
    return (200, {"id": "msg_1", "type": "message", "role": "assistant",
                  "model": "claude-opus-5", "stop_reason": "tool_use",
                  "content": [{"type": "tool_use", "id": tid, "name": name,
                               "input": tool_input}],
                  "usage": {"input_tokens": 10, "output_tokens": 5}})


# ------------------------------------------------------------------
# the checks
# ------------------------------------------------------------------
FAILURES = []


def check(label, fn):
    try:
        detail = fn()
        print("   ok  %-34s %s" % (label, detail or ""))
    except AssertionError as e:
        print("   x   %-34s %s" % (label, e))
        FAILURES.append(label)
    except Exception as e:  # noqa: BLE001 - a crash is a failure like any other
        print("   x   %-34s crashed: %r" % (label, e))
        FAILURES.append(label)


def seed_place(s):
    """A couple of recognisable things to look at."""
    s.lua.execute("""
        local map = Instance.new("Folder"); map.Name = "StarPetsMap"; map.Parent = workspace
        local meadow = Instance.new("Folder"); meadow.Name = "Meadow"; meadow.Parent = map
        local p = Instance.new("Part"); p.Name = "HatchPad"
        p.Size = Vector3.new(8, 1, 8); p.Position = Vector3.new(0, 1, 0)
        p.Parent = meadow
    """)


def t_request_shape():
    s = build(responses=[text_reply("Hello.")])
    seed_place(s)
    ask(s, "what is in the place?")
    assert len(s.requests) == 1, "expected exactly one API call, got %d" % len(s.requests)
    r = s.requests[0]
    assert r["url"] == "https://api.anthropic.com/v1/messages", r["url"]
    assert r["method"] == "POST", r["method"]
    h = r["headers"]
    assert h.get("x-api-key") == KEY, "the key header is missing or wrong"
    assert h.get("anthropic-version"), "anthropic-version header is missing"
    assert h.get("content-type") == "application/json", h.get("content-type")
    b = r["body"]
    assert b["model"].startswith("claude-"), b["model"]
    assert isinstance(b["max_tokens"], int) and b["max_tokens"] > 0
    assert "StarPets" in b["system"], "the system prompt lost its project rules"
    assert b["messages"] == [{"role": "user", "content": "what is in the place?"}], \
        b["messages"]
    names = [t["name"] for t in b["tools"]]
    assert names == ["look", "read_script", "find", "run_luau"], names
    for t in b["tools"]:
        sch = t["input_schema"]
        assert isinstance(sch, dict), "%s: schema encoded as %r" % (t["name"], type(sch))
        assert isinstance(sch["properties"], dict) and sch["properties"], \
            "%s: properties must be a non-empty object" % t["name"]
        assert sch["required"], "%s: no required field, so an empty {} input " \
                                "could corrupt the next request" % t["name"]
    return "%d tools, %d headers" % (len(names), len(h))


def t_tool_loop():
    s = build(responses=[
        tool_reply("look", {"path": "workspace.StarPetsMap", "depth": 2}),
        text_reply("There is a Meadow with a HatchPad in it."),
    ])
    seed_place(s)
    ask(s, "what is in the map?")
    assert len(s.requests) == 2, "expected a second call carrying the result"
    msgs = s.requests[1]["body"]["messages"]
    assert len(msgs) == 3, [m["role"] for m in msgs]
    assert msgs[1]["role"] == "assistant"
    assert msgs[2]["role"] == "user"
    res = msgs[2]["content"][0]
    assert res["type"] == "tool_result", res
    assert res["tool_use_id"] == "toolu_1", "the id did not come back"
    assert "HatchPad" in res["content"], \
        "the tool did not actually read the place: %r" % res["content"][:200]
    assert "Meadow" in res["content"]
    assert any("Meadow with a HatchPad" in b for b in s.bubbles()), \
        "the reply never reached the transcript"
    return "result carried %d chars back" % len(res["content"])


def t_empty_input_guard():
    """A tool call with no arguments must not re-encode as []."""
    s = build(responses=[
        tool_reply("look", {}),
        text_reply("ok"),
    ])
    seed_place(s)
    ask(s, "look around")
    assistant = s.requests[1]["body"]["messages"][1]["content"][0]
    assert isinstance(assistant["input"], dict), \
        "empty input re-encoded as %r, which the API rejects" % assistant["input"]
    return "empty input survived the round trip"


def t_edits_off_by_default():
    s = build(responses=[
        tool_reply("run_luau", {"code": 'local p = Instance.new("Part") '
                                        'p.Name = "ClaudeWasHere" p.Parent = workspace',
                                "why": "drop a test part"}),
        text_reply("It is switched off."),
    ])
    seed_place(s)
    ask(s, "make a part")
    res = s.requests[1]["body"]["messages"][2]["content"][0]["content"]
    assert "Refused" in res, res[:200]
    found = s.lua.eval('workspace:FindFirstChild("ClaudeWasHere")')
    assert found is None, "the part was created even though edits were OFF"
    return "refused, place untouched"


def allow_edits(s):
    btn = s.find(ClassName="TextButton", Text="Edits: OFF")
    assert btn is not None, "the edits chip was not built"
    s.click(btn)


def t_edits_when_allowed():
    s = build(responses=[
        tool_reply("run_luau", {"code": 'local p = Instance.new("Part") '
                                        'p.Name = "ClaudeWasHere" p.Parent = workspace '
                                        'print("made it")',
                                "why": "drop a test part"}),
        text_reply("Done."),
    ])
    seed_place(s)
    allow_edits(s)
    ask(s, "make a part")
    res = s.requests[1]["body"]["messages"][2]["content"][0]["content"]
    assert res.startswith("OK."), res[:200]
    assert "made it" in res, "print() inside the command never came back: %r" % res
    found = s.lua.eval('workspace:FindFirstChild("ClaudeWasHere")')
    assert found is not None, "the part was never created"

    recs = from_lua(s.mock["ChangeHistoryService"]["Recordings"])
    assert recs, "the change was not wrapped in an undo recording"
    assert "Commit" in str(recs[-1]["state"]), \
        "the recording was not committed: %r" % recs[-1]
    printed = "\n".join(s.out())
    assert "drop a test part" in printed, "the command was not announced first"
    assert 'p.Name = "ClaudeWasHere"' in printed, \
        "the code was not printed before running"
    return "part created, 1 undo step, announced first"


def t_never_during_play():
    s = build(playing=True, responses=[
        tool_reply("run_luau", {"code": 'local p = Instance.new("Part") '
                                        'p.Name = "PlayModePart" p.Parent = workspace',
                                "why": "should not happen"}),
        text_reply("Press Stop first."),
    ])
    allow_edits(s)
    ask(s, "make a part")
    res = s.requests[1]["body"]["messages"][2]["content"][0]["content"]
    assert "PLAY" in res, res[:200]
    found = s.lua.eval('workspace:FindFirstChild("PlayModePart")')
    assert found is None, "it ran during Play; the change would vanish on Stop"
    return "refused while playing"


def t_key_never_escapes():
    # A 401 is the case that matters: the natural thing to do with a rejected
    # request is print it back, and the key is what was rejected.
    s = build(responses=[(401, {"type": "error",
                                "error": {"type": "authentication_error",
                                          "message": "invalid x-api-key"}})])
    ask(s, "hello")
    everywhere = "\n".join(s.out() + s.bubbles())
    assert KEY not in everywhere, "THE API KEY LEAKED into output or transcript"
    assert "console.anthropic.com" in everywhere, \
        "a rejected key should say where to get a new one"
    tail = KEY[-4:]
    shown = [b for b in s.bubbles() if tail in b]
    assert all(KEY not in b for b in shown), "the full key is on screen"
    return "401 handled, key not in %d lines" % len(everywhere.splitlines())


def t_scrub_catches_a_leak():
    """Proven by pushing the key back at the panel, not by absence alone.

    Every other check shows the key staying put when nothing tries to print it.
    This one hands the panel the key inside a reply and watches what it renders,
    which is the case a careless error path would actually hit.
    """
    s = build(responses=[text_reply("I can see your key is " + KEY + " by the way.")])
    ask(s, "hello")
    bubbles = s.bubbles()
    assert any("I can see your key is" in b for b in bubbles), \
        "the reply never rendered, so this check proves nothing"
    for b in bubbles:
        assert KEY not in b, "scrub() let the key through into the transcript"
    assert any("<key hidden>" in b for b in bubbles), \
        "the key was not replaced, it just never arrived"
    return "reply carrying the key was scrubbed on screen"


def t_http_disabled_message():
    s = build(responses=[])
    s.lua.execute("""
        local hs = game:GetService("HttpService")
        hs.RequestAsync = function() error("Http requests are not enabled", 0) end
    """)
    ask(s, "hello")
    joined = "\n".join(s.bubbles())
    assert "Allow HTTP Requests" in joined, \
        "the one setting that blocks this is not named: %r" % joined[-300:]
    return "names the setting to switch on"


def main():
    plugin_path = ROOT / "src/Plugin/StarPetsAI.server.lua"
    if not plugin_path.exists():
        print("   x the AI plugin is missing")
        return 1

    print("Claude-in-Studio panel:")
    check("request is well formed", t_request_shape)
    check("tool loop closes", t_tool_loop)
    check("empty tool input guarded", t_empty_input_guard)
    check("edits refused by default", t_edits_off_by_default)
    check("edits work when allowed", t_edits_when_allowed)
    check("never runs during Play", t_never_during_play)
    check("key never escapes", t_key_never_escapes)
    check("scrub() removes the key", t_scrub_catches_a_leak)
    check("http-disabled is explained", t_http_disabled_message)

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\nthe panel talks to the API, sees the place, and holds the key safely")
    return 0


if __name__ == "__main__":
    sys.exit(main())
