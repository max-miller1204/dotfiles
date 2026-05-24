# pingpal — endpoint uptime monitor

## Problem
A small CLI that watches HTTP endpoints and tells you when they go down.

## Capabilities

### 1. Checks
- `pingpal add <url>` registers an endpoint; `pingpal check` probes all
  registered endpoints once and prints status + latency.
- A check is "up" on 2xx/3xx within the timeout, "down" otherwise.

### 2. Scheduling
- `pingpal watch` runs checks on a configurable interval (default 60s) until
  interrupted.

### 3. History
- Every check result is appended to a local SQLite store.
- `pingpal history <url>` prints the last N results with timestamps.

### 4. Alerting
- On a status transition (up→down or down→up), fire a notification.
- Pluggable sinks: stderr (default), and a webhook POST.

### 5. Config
- Endpoints, interval, timeout, and webhook URL live in `pingpal.toml`.

## Constraints
- Python 3.11+, `httpx`, SQLite via stdlib. No hosted monitoring services.
