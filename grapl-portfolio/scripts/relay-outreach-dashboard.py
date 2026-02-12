#!/usr/bin/env python3
"""Relay Outreach dashboard for Telegram.

Outputs a Markdown summary based on Supabase REST queries.
"""

from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, List, Tuple, Union
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

AEST = timezone(timedelta(hours=10))


def get_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


def resolve_supabase_config() -> Tuple[str, str]:
    url = get_env("SUPABASE_URL")
    service_key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if service_key:
        return url, service_key
    anon_key = os.getenv("SUPABASE_ANON_KEY", "").strip()
    if anon_key:
        return url, anon_key
    raise RuntimeError("Missing SUPABASE_SERVICE_ROLE_KEY (or SUPABASE_ANON_KEY fallback).")


Params = Union[Dict[str, Any], List[Tuple[str, Any]]]


def normalize_params(params: Params) -> List[Tuple[str, Any]]:
    if isinstance(params, dict):
        items: List[Tuple[str, Any]] = []
        for key, value in params.items():
            if isinstance(value, (list, tuple)):
                for item in value:
                    items.append((key, item))
            else:
                items.append((key, value))
        return items
    return list(params)


def build_url(base: str, path: str, params: Params) -> str:
    base = base.rstrip("/")
    path = path.lstrip("/")
    query = urlencode(normalize_params(params), doseq=True)
    return f"{base}/{path}?{query}" if query else f"{base}/{path}"


def request_json(url: str, headers: Dict[str, str]) -> Tuple[List[Dict[str, Any]], Dict[str, str]]:
    req = Request(url, headers=headers, method="GET")
    with urlopen(req, timeout=30) as resp:
        body = resp.read().decode("utf-8")
        data = json.loads(body) if body else []
        return data, {k: v for k, v in resp.headers.items()}


def get_count(base_url: str, table: str, params: Params, headers: Dict[str, str]) -> int:
    count_headers = dict(headers)
    count_headers["Prefer"] = "count=exact"
    param_items = normalize_params(params)
    if not any(key == "select" for key, _ in param_items):
        param_items.append(("select", "id"))
    if not any(key == "limit" for key, _ in param_items):
        param_items.append(("limit", 1))
    url = build_url(base_url, f"rest/v1/{table}", param_items)
    data, resp_headers = request_json(url, count_headers)
    content_range = resp_headers.get("Content-Range", "")
    if "/" in content_range:
        try:
            return int(content_range.split("/")[-1])
        except ValueError:
            pass
    return len(data)


def fetch_rows(base_url: str, table: str, params: Params, headers: Dict[str, str]) -> List[Dict[str, Any]]:
    url = build_url(base_url, f"rest/v1/{table}", params)
    data, _ = request_json(url, headers)
    return data


def parse_ts(value: str | None) -> datetime | None:
    if not value:
        return None
    value = value.replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


def format_date(dt: datetime | None) -> str:
    if not dt:
        return "—"
    return dt.astimezone(AEST).strftime("%Y-%m-%d")


def days_overdue(start_of_day: datetime, due_at: datetime | None) -> int:
    if not due_at:
        return 0
    due_date = due_at.astimezone(AEST).date()
    return max(0, (start_of_day.date() - due_date).days)


def format_dashboard(
    now: datetime,
    start_of_day: datetime,
    sent_today: int,
    due_followups: int,
    replies_today: int,
    booked_today: int,
    pipeline_counts: Dict[str, int],
    overdue_followups: List[Dict[str, Any]],
) -> str:
    lines: List[str] = []
    lines.append(f"*Relay Outreach — Daily Dashboard (AEST {now.strftime('%Y-%m-%d')})*")
    lines.append("")
    lines.append(f"Sent today: `{sent_today}`")
    lines.append(f"Due followups: `{due_followups}`")
    lines.append(f"Replies today: `{replies_today}`")
    lines.append(f"Booked today: `{booked_today}`")
    lines.append("")
    lines.append("*Pipeline (by status)*")
    for status in sorted(pipeline_counts.keys()):
        lines.append(f"{status}: `{pipeline_counts[status]}`")
    lines.append("")
    lines.append("*Overdue followups (top 5)*")
    if not overdue_followups:
        lines.append("None")
    else:
        for idx, row in enumerate(overdue_followups, start=1):
            name = row.get("prospect_name") or "Unknown"
            last_touch = parse_ts(row.get("last_touch_at"))
            due_at = parse_ts(row.get("followup_due_at"))
            overdue_days = days_overdue(start_of_day, due_at)
            lines.append(
                f"{idx}. {name} — last touch {format_date(last_touch)} — {overdue_days}d overdue"
            )
    return "\n".join(lines)


def main() -> int:
    try:
        base_url, api_key = resolve_supabase_config()
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1

    headers = {
        "apikey": api_key,
        "Authorization": f"Bearer {api_key}",
        "Accept": "application/json",
    }

    now = datetime.now(AEST)
    start_of_day = datetime(now.year, now.month, now.day, tzinfo=AEST)
    end_of_day = start_of_day + timedelta(days=1)

    def iso(dt: datetime) -> str:
        return dt.isoformat()

    try:
        sent_today = get_count(
            base_url,
            "prospect_touchpoints",
            {
                "select": "id",
                "direction": "eq.outbound",
                "outcome": "eq.sent",
                "occurred_at": [f"gte.{iso(start_of_day)}", f"lt.{iso(end_of_day)}"],
            },
            headers,
        )
    except Exception:
        sent_today = 0

    try:
        replies_today = get_count(
            base_url,
            "prospect_touchpoints",
            {
                "select": "id",
                "outcome": "eq.replied",
                "occurred_at": [f"gte.{iso(start_of_day)}", f"lt.{iso(end_of_day)}"],
            },
            headers,
        )
    except Exception:
        replies_today = 0

    try:
        booked_today = get_count(
            base_url,
            "prospect_touchpoints",
            {
                "select": "id",
                "outcome": "eq.booked_call",
                "occurred_at": [f"gte.{iso(start_of_day)}", f"lt.{iso(end_of_day)}"],
            },
            headers,
        )
    except Exception:
        booked_today = 0

    try:
        due_rows = fetch_rows(
            base_url,
            "followup_queue",
            {
                "select": "touchpoint_id",
            },
            headers,
        )
        due_followups = len(due_rows)
    except Exception:
        due_followups = 0

    pipeline_counts: Dict[str, int] = {}
    try:
        rows = fetch_rows(
            base_url,
            "prospects",
            {
                "select": "status",
            },
            headers,
        )
        for row in rows:
            status = row.get("status") or "unknown"
            pipeline_counts[status] = pipeline_counts.get(status, 0) + 1
    except Exception:
        pipeline_counts = {}

    overdue_followups: List[Dict[str, Any]] = []
    try:
        overdue_followups = fetch_rows(
            base_url,
            "followup_queue",
            {
                "select": "prospect_name,last_touch_at,followup_due_at",
                "followup_due_at": f"lt.{iso(start_of_day)}",
                "order": "followup_due_at.asc",
                "limit": 5,
            },
            headers,
        )
    except Exception:
        overdue_followups = []

    output = format_dashboard(
        now,
        start_of_day,
        sent_today,
        due_followups,
        replies_today,
        booked_today,
        pipeline_counts,
        overdue_followups,
    )

    print(output)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (HTTPError, URLError) as exc:
        print(f"Supabase request failed: {exc}", file=sys.stderr)
        sys.exit(1)
