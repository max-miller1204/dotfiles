# Roadmap

## North star
The fastest way to mint a branded short link and see who clicked it.

## Work areas
- **Core link service** — shorten/resolve, base62 codes, custom aliases.
- **Persistence** — Postgres-backed links, immutability, tombstones.
- **Rate limiting** — per-IP and per-key budgets, resolve always exempt.
- **Analytics** — resolve event capture, GeoIP enrichment, stats endpoint.
- **Auth** — API-key minting, bearer auth, owner-scoped operations.
- **Surface** — eventually a dashboard; CLI/API only for now.

## Notes
- Persistence must land before analytics (events reference stored links).
- Auth must land before owner-scoped stats/delete.
- GeoIP enrichment is deferred until a data source is chosen.
