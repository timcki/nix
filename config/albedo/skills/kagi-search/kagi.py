"""Kagi Search and Extract for albedo's Python kernel, stdlib only.

Import once per kernel; the module stays loaded across cells:

    import sys, pathlib
    sys.path.insert(0, str(pathlib.Path.home() / ".albedo/skills/kagi-search"))
    import kagi
    print(kagi.search("query"))
"""

from __future__ import annotations

import html
import json
import os
import re
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlparse
from urllib.request import Request, urlopen

BASE_URL = "https://kagi.com/api/v1"
KEY_FILE = os.path.expanduser("~/.config/kagi/api_key")
MAX_PAGE_CHARS = 15_000
MAX_RESULTS_PER_GROUP = 2
MAX_EXTRACT_URLS = 10
TIMEOUT_SECONDS = 60

__all__ = ["KagiError", "search", "read"]


class KagiError(RuntimeError):
    """a failed or malformed Kagi request; nothing is retried, to avoid double billing"""


def _record(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _array(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def _string(value: Any) -> str:
    return value if isinstance(value, str) else ""


def _clean(text: str) -> str:
    text = re.sub(r"</?strong\b[^>]*>", "", text, flags=re.I)
    return html.unescape(re.sub(r"<[^>]*>", "", text))


def _truncate(text: str) -> str:
    if len(text) <= MAX_PAGE_CHARS:
        return text
    return text[:MAX_PAGE_CHARS] + f"\n[... truncated at {MAX_PAGE_CHARS} characters]"


def _describe(status: int, body: Any) -> str:
    envelope = _record(body)
    errors = envelope.get("errors", envelope.get("error"))
    details = []
    for error in errors if isinstance(errors, list) else [errors]:
        entry = _record(error)
        detail = _string(entry.get("message")) or _string(entry.get("code")) or _string(error)
        if detail:
            details.append(detail)
    return f"Kagi request failed (HTTP {status})" + (": " + "; ".join(details) if details else "")


def _api_key() -> str:
    key = os.environ.get("KAGI_API_KEY")
    if key is None:
        try:
            with open(KEY_FILE, encoding="utf-8") as file:
                key = file.read()
        except FileNotFoundError:
            raise KagiError(f"no Kagi key: set KAGI_API_KEY or write it to {KEY_FILE}") from None
    if not key.strip():
        raise KagiError("Kagi API key is empty")
    return key.strip()


def _api(path: str, payload: dict[str, Any]) -> Any:
    request = Request(
        BASE_URL + path,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Authorization": f"Bearer {_api_key()}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urlopen(request, timeout=TIMEOUT_SECONDS) as response:
            body = json.load(response)
    except HTTPError as error:
        try:
            body = json.loads(error.read())
        except (ValueError, UnicodeError):
            body = None
        finally:
            error.close()
        raise KagiError(_describe(error.code, body)) from None
    except (URLError, TimeoutError, OSError):
        raise KagiError("Kagi connection failed or timed out") from None
    except (ValueError, UnicodeError):
        raise KagiError("Kagi returned invalid JSON") from None
    if not isinstance(body, dict) or "data" not in body or body.get("errors") or body.get("error"):
        raise KagiError(_describe(200, body))
    return body["data"]


def _results(value: Any) -> list[dict[str, Any]]:
    results = []
    for item in map(_record, _array(value)):
        url = _string(item.get("url"))
        if url:
            results.append({
                "url": url,
                "title": _clean(_string(item.get("title")) or url),
                "snippet": _clean(_string(item.get("snippet"))),
                "time": _string(item.get("time")),
                "group": _record(item.get("props")).get("group_id"),
                "markdown": _string(item.get("markdown")),
            })
    return results


def _cap_per_group(results: list[dict[str, Any]]) -> list[dict[str, Any]]:
    counts: dict[str, int] = {}
    kept = []
    for result in results:
        group = result["group"]
        key = str(group) if isinstance(group, (str, int)) and not isinstance(group, bool) and group != "" else result["url"]
        if counts.get(key, 0) < MAX_RESULTS_PER_GROUP:
            counts[key] = counts.get(key, 0) + 1
            kept.append(result)
    return kept


def _entry(entry: dict[str, Any]) -> str:
    lines = [entry["title"], entry["url"]]
    if entry["time"]:
        lines.append(entry["time"])
    if entry["snippet"]:
        lines.append(_truncate(entry["snippet"]))
    if entry["markdown"]:
        lines += ["extracted:", _truncate(entry["markdown"])]
    return "\n".join(lines)


def search(query: str, count: int = 15, extract: int = 0) -> str:
    """Kagi web search, billed per call. Returns ranked results as text.

    count: 1-50 results to show (capped at 2 per source unless the query has `site:`).
    extract: 0-10 top results to also extract as markdown, billed per page.
    """
    query = query.strip()
    if not query:
        raise ValueError("query must be non-empty")
    if not 1 <= count <= 50:
        raise ValueError("count must be 1-50")
    if not 0 <= extract <= MAX_EXTRACT_URLS:
        raise ValueError("extract must be 0-10")
    payload: dict[str, Any] = {"query": query}
    if extract:
        payload["extract"] = {"count": extract}
    data = _record(_api("/search", payload))

    sections = []
    direct = []
    for item in map(_record, _array(data.get("direct_answer"))):
        title, snippet = _string(item.get("title")), _string(item.get("snippet"))
        line = f"{title}: {snippet}" if title and snippet else title or snippet
        if line:
            direct.append(_truncate(_clean(line)))
    if direct:
        sections.append("direct answer:\n" + "\n".join(direct))
    sections += ["infobox:\n" + _entry(entry) for entry in _results(data.get("infobox"))]

    raw = _results(data.get("search"))
    site_scoped = re.search(r"(?:^|\s)site:", query, re.I) is not None
    shown = (raw if site_scoped else _cap_per_group(raw))[:count]
    if shown:
        header = f'{len(shown)} of {len(raw)} results for "{query}"'
        sections.append(header + "\n\n" + "\n\n".join(f"{i}. {_entry(e)}" for i, e in enumerate(shown, 1)))
    else:
        sections.append(f'no results for "{query}"')

    finds = _results(data.get("interesting_finds"))
    if finds:
        sections.append("interesting finds:\n" + "\n\n".join(map(_entry, finds)))
    return "\n\n".join(sections)


def read(*urls: str) -> str:
    """Extract 1-10 HTTP(S) pages as markdown via Kagi, billed per page.

    Each page is capped at 15,000 characters; truncation is marked. Per-page
    failures are reported inline, not raised.
    """
    if not 1 <= len(urls) <= MAX_EXTRACT_URLS:
        raise ValueError("read takes 1-10 URLs; split larger batches")
    cleaned = []
    for url in (u.strip() for u in urls):
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username or parsed.password:
            raise ValueError(f"not an HTTP(S) URL without credentials: {url}")
        cleaned.append(url)
    data = _api("/extract", {"pages": [{"url": url} for url in cleaned]})
    if not isinstance(data, list):
        raise KagiError("Kagi returned invalid extract data")
    pages = {_string(_record(item).get("url")): _record(item) for item in data}
    out = []
    for url in cleaned:
        page = pages.get(url, {})
        markdown = _string(page.get("markdown"))
        error = _string(page.get("error")) or _string(_record(page.get("error")).get("message"))
        out.append(f"=== {url} ===\n" + (_truncate(markdown) if markdown else f"extraction failed: {error or 'no content'}"))
    return "\n\n".join(out)
