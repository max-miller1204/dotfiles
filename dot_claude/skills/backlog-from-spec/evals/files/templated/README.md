# pingpal

## Status (current)
Implemented: `pingpal add` and `pingpal check` — registers endpoints in
`pingpal.toml` and probes them once with `httpx`, printing status + latency.

Not yet implemented:
- `pingpal watch` interval scheduling
- SQLite history store + `pingpal history`
- Alerting on status transitions (stderr + webhook sinks)

Single module so far: `src/pingpal/cli.py` (~90 LOC).
