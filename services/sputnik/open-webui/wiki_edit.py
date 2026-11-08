"""
title: Wiki edit
description: Propose a rewrite of a SilverBullet page, show the user a diff, and write it only after they approve.
version: 0.1.0
"""

# Open WebUI tool (Workspace -> Tools, ID wiki_edit), attached to the Household
# model. Native rather than n8n because only native tools can render a diff in
# the chat. Path and content rules mirror the Check node in
# services/sputnik/workflows/mercurius-wiki-write.json; keep them in step.
#
# Helpers live at module level: Open WebUI offers every public method of
# Tools to the model as a tool.

import difflib
import html
import json
import re
import secrets
import time
from urllib.parse import quote

import aiohttp
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field

# SilverBullet runs these as code in the browser of whoever opens the page.
CODE_MARKERS = ["space-lua", "space-style", "space-script", "${", "<!--#", "<script", "<iframe"]

# Proposal id -> proposal. In memory: a restart or a tool edit drops them,
# and the model proposes again.
PROPOSALS = {}


class WikiError(Exception):
    pass


class Tools:
    class Valves(BaseModel):
        wiki_url: str = Field(default="https://wiki.loft.hsimah.com/home/.fs")
        api_token: str = Field(default="", description="SilverBullet API token of the sputnik account.")
        proposal_hours: int = Field(default=24, description="How long a proposal can be approved.")
        max_chars: int = Field(default=100000, description="Largest page a proposal may write.")
        timeout: int = Field(default=30)

    def __init__(self):
        self.valves = self.Valves()

    async def propose_page_edit(
        self,
        path: str,
        new_text: str,
        summary: str,
        __user__: dict = None,
    ):
        """
        Propose new full contents for one wiki page, existing or new. Shows the user a diff against the page as it is now, with Approve and Request changes buttons. Nothing is written. Afterwards, stop and wait for the user.
        :param path: Page path ending in .md, e.g. Travel/Canada/Quebec/Montreal.md
        :param new_text: The complete new markdown of the page, not just the changed part and not wrapped in a code block.
        :param summary: One sentence describing the change, shown above the diff.
        """
        try:
            p, url_path = check_path(path)
            new = (new_text or "").rstrip() + "\n"
            if not new.strip():
                raise WikiError("Nothing to write: new_text is empty.")
            if len(new) > self.valves.max_chars:
                raise WikiError(f"new_text is {len(new)} characters; the limit is {self.valves.max_chars}.")
            check_code(new, "The new text")
            current, etag = await read_page(self.valves, url_path)
            if current is not None:
                check_code(current, f"{p} already")
                if new.startswith("```") and not current.startswith("```"):
                    raise WikiError("new_text is wrapped in a code block. Send the page markdown itself.")
                if new == current.rstrip() + "\n":
                    raise WikiError(f"new_text is the same as {p} now; there is nothing to change.")
        except WikiError as e:
            return f"Not proposed: {e}"

        expire_proposals(self.valves.proposal_hours)
        pid = secrets.token_hex(3)
        PROPOSALS[pid] = {
            "path": p,
            "url_path": url_path,
            "etag": etag,
            "text": new,
            "user": (__user__ or {}).get("id"),
            "created": time.time(),
        }
        old_lines = [] if current is None else current.rstrip("\n").split("\n")
        new_lines = new.rstrip("\n").split("\n")
        body, added, removed = render_diff(old_lines, new_lines)
        page = render_page(pid, p, summary, current is None, added, removed, body)
        context = {
            "proposal_id": pid,
            "path": p,
            "new_page": current is None,
            "lines_added": added,
            "lines_removed": removed,
            "status": (
                "The diff is shown to the user with Approve and Request changes buttons. "
                "Stop here. Call apply_page_edit only when the user's latest message approves "
                f"proposal {pid} by its id."
            ),
        }
        return HTMLResponse(content=page, headers={"Content-Disposition": "inline"}), context

    async def apply_page_edit(
        self,
        proposal_id: str,
        __user__: dict = None,
        __messages__: list = None,
    ) -> str:
        """
        Write a proposal made with propose_page_edit. Only call this when the user's latest message approves that proposal by its id.
        :param proposal_id: The id propose_page_edit returned, e.g. 3fa9c1.
        """
        pid = (proposal_id or "").strip().lower()
        proposal = PROPOSALS.get(pid)
        if proposal is None or time.time() - proposal["created"] > self.valves.proposal_hours * 3600:
            PROPOSALS.pop(pid, None)
            return f"Not applied: there is no open proposal {pid}. Propose the change again."
        if proposal["user"] != (__user__ or {}).get("id"):
            return f"Not applied: proposal {pid} belongs to another user."
        # The gate: the approval must come from the user, naming this proposal.
        if pid not in last_user_text(__messages__).lower():
            return (
                f"Not applied: the user's latest message does not approve proposal {pid}. "
                "Ask them to press Approve under the diff, or to reply with the proposal id."
            )

        headers = {"If-Match": proposal["etag"]} if proposal["etag"] else {"If-None-Match": "*"}
        status = await write_page(self.valves, proposal["url_path"], proposal["text"], headers)
        p = proposal["path"]
        if status == 412:
            PROPOSALS.pop(pid, None)
            return f"Not applied: {p} changed after proposal {pid} was made. Read it again and make a new proposal."
        if status >= 300:
            return f"Not applied: writing {p} failed with HTTP {status}. Tell the user."
        # Other proposals for this page were made against the old version.
        for other in [k for k, v in PROPOSALS.items() if v["path"] == p]:
            PROPOSALS.pop(other, None)
        verb = "Created" if proposal["etag"] is None else "Updated"
        return f"{verb} {p} from proposal {pid}. SilverBullet keeps the previous revision."


def check_path(path):
    p = (path or "").strip().lstrip("/")
    segments = p.split("/")
    if not p.endswith(".md") or any(s in ("", "..") or s.startswith(".") for s in segments):
        raise WikiError(f'Invalid page path "{p}". Use a relative path ending in .md, e.g. Travel/Canada/Quebec/Montreal.md')
    # SilverBullet's own library and its sources, mostly Space Lua.
    if segments[0].lower() in ("library", "repositories"):
        raise WikiError(f"{segments[0]}/ holds SilverBullet's own files. Edit household pages only.")
    return p, "/".join(quote(s, safe="") for s in segments)


def check_code(text, what):
    lower = text.lower()
    for marker in CODE_MARKERS:
        if marker in lower:
            raise WikiError(
                f'{what} contains "{marker}", which SilverBullet runs as code. '
                "Pages with code are edited by hand; new text must be plain markdown."
            )


def expire_proposals(hours):
    cutoff = time.time() - hours * 3600
    for pid in [k for k, v in PROPOSALS.items() if v["created"] < cutoff]:
        PROPOSALS.pop(pid, None)


def last_user_text(messages):
    for message in reversed(messages or []):
        if message.get("role") != "user":
            continue
        content = message.get("content")
        if isinstance(content, list):
            return " ".join(part.get("text", "") for part in content if part.get("type") == "text")
        return str(content or "")
    return ""


def auth_headers(valves):
    if not valves.api_token:
        raise WikiError("The wiki_edit tool has no API token. Tell the user to set its valve.")
    # Without X-Sync-Mode SilverBullet answers a .md path with the editor.
    return {"Authorization": f"Bearer {valves.api_token}", "X-Sync-Mode": "true"}


async def read_page(valves, url_path):
    """Returns (text, etag), or (None, None) when the page does not exist."""
    timeout = aiohttp.ClientTimeout(total=valves.timeout)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        async with session.get(f"{valves.wiki_url.rstrip('/')}/{url_path}", headers=auth_headers(valves)) as r:
            if r.status == 404:
                return None, None
            if r.status != 200:
                raise WikiError(f"Reading the page failed: HTTP {r.status}.")
            etag = r.headers.get("ETag")
            if not etag:
                raise WikiError("The wiki returned no ETag, so a write could not be guarded. Tell the user.")
            return await r.text(encoding="utf-8"), etag


async def write_page(valves, url_path, text, condition):
    headers = auth_headers(valves) | condition | {"Content-Type": "text/markdown"}
    timeout = aiohttp.ClientTimeout(total=valves.timeout)
    async with aiohttp.ClientSession(timeout=timeout) as session:
        async with session.put(
            f"{valves.wiki_url.rstrip('/')}/{url_path}", data=text.encode("utf-8"), headers=headers
        ) as r:
            return r.status


# ---- Diff rendering ----------------------------------------------------------


def render_diff(old, new):
    """Unified diff as HTML table rows, three lines of context per hunk."""
    rows = []
    added = removed = 0
    matcher = difflib.SequenceMatcher(None, old, new, autojunk=False)
    for n, group in enumerate(matcher.get_grouped_opcodes(3)):
        if n:
            rows.append('<tr class="gap"><td></td><td></td><td>⋯</td></tr>')
        for tag, i1, i2, j1, j2 in group:
            if tag == "equal":
                for k in range(i2 - i1):
                    rows.append(row("ctx", i1 + k + 1, j1 + k + 1, html.escape(old[i1 + k])))
                continue
            olds, news = old[i1:i2], new[j1:j2]
            removed += len(olds)
            added += len(news)
            # Lines changed in place get word-level highlights.
            pairs = len(olds) == len(news)
            for k, line in enumerate(olds):
                text = word_diff(line, news[k])[0] if pairs else html.escape(line)
                rows.append(row("del", i1 + k + 1, "", text))
            for k, line in enumerate(news):
                text = word_diff(olds[k], line)[1] if pairs else html.escape(line)
                rows.append(row("add", "", j1 + k + 1, text))
    return "\n".join(rows), added, removed


def row(kind, old_no, new_no, text):
    sign = {"del": "−", "add": "+", "ctx": " "}[kind]
    return (
        f'<tr class="{kind}"><td class="no">{old_no}</td><td class="no">{new_no}</td>'
        f'<td class="ln"><span class="sign">{sign}</span>{text or " "}</td></tr>'
    )


def word_diff(a, b):
    ta = re.findall(r"\s+|\w+|[^\w\s]", a)
    tb = re.findall(r"\s+|\w+|[^\w\s]", b)
    out_a, out_b = [], []
    for tag, i1, i2, j1, j2 in difflib.SequenceMatcher(None, ta, tb, autojunk=False).get_opcodes():
        sa, sb = html.escape("".join(ta[i1:i2])), html.escape("".join(tb[j1:j2]))
        if tag == "equal":
            out_a.append(sa)
            out_b.append(sb)
        else:
            if sa:
                out_a.append(f"<mark>{sa}</mark>")
            if sb:
                out_b.append(f"<mark>{sb}</mark>")
    return "".join(out_a), "".join(out_b)


def render_page(pid, path, summary, new_page, added, removed, rows):
    approve = json.dumps(f"Approve proposal {pid}: apply it to {path}.")
    revise = json.dumps(f"Change proposal {pid}: ")
    badge = '<span class="badge">new page</span>' if new_page else ""
    return f"""<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<style>
:root {{ --bg:#fff; --fg:#1f2328; --muted:#656d76; --line:#d0d7de;
  --add:#e6ffec; --add-hl:#abf2bc; --del:#ffebe9; --del-hl:#ffc1c0; --gap:#f6f8fa;
  --btn:#1f883d; --btn-fg:#fff; }}
@media (prefers-color-scheme: dark) {{ :root {{ --bg:#0d1117; --fg:#e6edf3; --muted:#8d96a0;
  --line:#30363d; --add:#12261e; --add-hl:#1f6f3a; --del:#25171c; --del-hl:#7d2a2f; --gap:#161b22;
  --btn:#238636; }} }}
* {{ box-sizing:border-box; }}
body {{ margin:0; padding:12px; background:var(--bg); color:var(--fg);
  font:14px/1.45 system-ui,-apple-system,"Segoe UI",sans-serif; }}
header {{ margin-bottom:10px; }}
.path {{ font-weight:600; word-break:break-all; }}
.badge {{ margin-left:6px; padding:1px 6px; border:1px solid var(--line); border-radius:10px;
  font-size:12px; color:var(--muted); }}
.summary {{ margin:4px 0; }}
.stats {{ color:var(--muted); font-size:13px; }}
.stats b.a {{ color:#1a7f37; }} .stats b.d {{ color:#cf222e; }}
.diff {{ border:1px solid var(--line); border-radius:6px; overflow:hidden; }}
table {{ width:100%; border-collapse:collapse;
  font:12.5px/1.5 ui-monospace,SFMono-Regular,Menlo,Consolas,monospace; }}
td.no {{ width:1%; padding:0 6px; text-align:right; color:var(--muted); user-select:none;
  white-space:nowrap; vertical-align:top; }}
td.ln {{ padding:0 8px; white-space:pre-wrap; word-break:break-word; }}
.sign {{ display:inline-block; width:1.2em; color:var(--muted); user-select:none; }}
tr.add {{ background:var(--add); }} tr.del {{ background:var(--del); }}
tr.add mark {{ background:var(--add-hl); color:inherit; }}
tr.del mark {{ background:var(--del-hl); color:inherit; }}
tr.gap td {{ background:var(--gap); color:var(--muted); text-align:center; }}
.actions {{ display:flex; gap:8px; flex-wrap:wrap; margin-top:10px; align-items:center; }}
button {{ font:inherit; padding:6px 14px; border-radius:6px; border:1px solid var(--line);
  background:var(--gap); color:var(--fg); cursor:pointer; }}
button.ok {{ background:var(--btn); border-color:var(--btn); color:var(--btn-fg); }}
button:disabled {{ opacity:.5; cursor:default; }}
.note {{ color:var(--muted); font-size:13px; }}
</style></head><body>
<header>
  <div><span class="path">{html.escape(path)}</span>{badge}</div>
  <div class="summary">{html.escape(summary or "")}</div>
  <div class="stats">Proposal {pid} · <b class="a">+{added}</b> <b class="d">−{removed}</b> lines</div>
</header>
<div class="diff"><table>{rows}</table></div>
<div class="actions">
  <button class="ok" id="approve">Approve</button>
  <button id="revise">Request changes</button>
  <span class="note" id="note"></span>
</div>
<script>
const send = (type, text) => parent.postMessage({{ type, text }}, "*");
const done = (msg) => {{
  document.querySelectorAll("button").forEach((b) => (b.disabled = true));
  document.getElementById("note").textContent = msg;
}};
document.getElementById("approve").onclick = () => {{ send("input:prompt:submit", {approve}); done("Approval sent."); }};
document.getElementById("revise").onclick = () => {{ send("input:prompt", {revise}); document.getElementById("note").textContent = "Describe the change in the chat box."; }};
const height = () => parent.postMessage({{ type: "iframe:height", height: document.documentElement.scrollHeight }}, "*");
new ResizeObserver(height).observe(document.body);
window.addEventListener("load", height);
</script>
</body></html>"""
