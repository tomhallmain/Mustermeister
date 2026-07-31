#!/usr/bin/env python3
"""Manual test client for Mustermeister's GET /api/tools/:tool_name endpoint.

Run from the project root:
    python scripts/call_api.py overdue_tasks --limit 10
    python scripts/call_api.py open_tasks_by_priorities --priorities high medium --limit 20
    python scripts/call_api.py search_tasks --keyword backup
    python scripts/call_api.py project_summary

Reads MUSTERMEISTER_BASE_URL / MUSTERMEISTER_API_TOKEN from the environment,
or pass --base-url/--token explicitly. Generate a token first via the profile
page's "Regenerate Token" button, or `rake api:generate_token[email]`.

Stdlib only, no external dependencies - and sets an explicit User-Agent,
since this app's rack-attack config blocks the curl/wget-style default one
some HTTP libraries send.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_BASE_URL = "http://localhost:3000"
USER_AGENT = "Mustermeister-API-Client/1.0"
KNOWN_TOOLS = [
    "project_summary",
    "status_breakdown",
    "overdue_tasks",
    "high_priority_open_tasks",
    "open_tasks_by_priorities",
    "recent_tasks",
    "search_tasks",
]


def parse_args():
    parser = argparse.ArgumentParser(
        description="Call a Mustermeister /api/tools/:tool_name endpoint.",
        epilog="Known tools: " + ", ".join(KNOWN_TOOLS),
    )
    parser.add_argument("tool_name", help="e.g. overdue_tasks, recent_tasks, search_tasks")
    parser.add_argument("--base-url", default=os.environ.get("MUSTERMEISTER_BASE_URL", DEFAULT_BASE_URL))
    parser.add_argument("--token", default=os.environ.get("MUSTERMEISTER_API_TOKEN"))
    parser.add_argument("--limit", type=int)
    parser.add_argument("--days", type=int)
    parser.add_argument("--keyword")
    parser.add_argument("--priorities", nargs="+", choices=["leisure", "low", "medium", "high"])
    parser.add_argument("--project-ids", nargs="+", type=int)
    return parser.parse_args()


def build_url(base_url, tool_name, args):
    query = {}
    if args.limit is not None:
        query["limit"] = args.limit
    if args.days is not None:
        query["days"] = args.days
    if args.keyword is not None:
        query["keyword"] = args.keyword
    if args.priorities:
        query["priorities[]"] = args.priorities
    if args.project_ids:
        query["project_ids[]"] = args.project_ids

    query_string = urllib.parse.urlencode(query, doseq=True)
    path = f"/api/tools/{urllib.parse.quote(tool_name)}"
    url = f"{base_url.rstrip('/')}{path}"
    return f"{url}?{query_string}" if query_string else url


def main():
    args = parse_args()

    if not args.token:
        sys.exit("No API token given - set MUSTERMEISTER_API_TOKEN or pass --token.")

    url = build_url(args.base_url, args.tool_name, args)
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {args.token}",
            "User-Agent": USER_AGENT,
            "Accept": "application/json",
        },
    )

    try:
        with urllib.request.urlopen(request) as response:
            print(json.dumps(json.load(response), indent=2))
    except urllib.error.HTTPError as error:
        body = error.read()
        print(f"HTTP {error.code}: {error.reason}", file=sys.stderr)
        try:
            print(json.dumps(json.loads(body), indent=2), file=sys.stderr)
        except json.JSONDecodeError:
            print(body.decode("utf-8", errors="replace"), file=sys.stderr)
        sys.exit(1)
    except urllib.error.URLError as error:
        sys.exit(f"Could not reach {args.base_url}: {error.reason}")


if __name__ == "__main__":
    main()
