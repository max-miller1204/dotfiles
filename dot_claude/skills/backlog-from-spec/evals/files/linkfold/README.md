# linkfold

## Status (current)
MVP implemented: `POST /shorten {url}` and `GET /:code` redirect, using an
**in-memory dict** (lost on restart). Base62 7-char codes work.

Not yet implemented:
- Postgres persistence, immutability, tombstones (410 Gone)
- Custom aliases (`alias` field + 409 on collision)
- Rate limiting (per-IP anon, per-key authed)
- Analytics: resolve event capture, GeoIP, `GET /:code/stats`
- Auth: API-key minting, bearer auth, owner-scoped stats/delete

## Run
`uvicorn linkfold.app:app` — see `src/linkfold/app.py` (single module, ~80 LOC).
