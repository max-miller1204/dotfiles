# linkfold — URL shortener

## Problem
Teams need short, branded links with click analytics. linkfold turns a long
URL into a short code, resolves it on GET, and reports usage.

## Capabilities

### 1. Shorten & resolve
- `POST /shorten {url}` → `{code, short_url}`. Codes are 7-char base62.
- `GET /:code` → 302 redirect to the original URL.
- Custom aliases: `POST /shorten {url, alias}` reserves a human alias;
  collisions return 409.

### 2. Storage
- Links persist in Postgres (table `links(code, url, created_at, owner_id)`).
- A code is immutable once issued; deleting a link tombstones it (410 Gone).

### 3. Rate limiting
- Anonymous: 10 shortens/hour/IP. Authenticated: 1000/hour/key.
- Resolution (`GET /:code`) is never rate limited.

### 4. Analytics
- Every resolve records `{code, ts, referrer, country}` (country via GeoIP).
- `GET /:code/stats` returns total + 7-day daily series. Owner-only.

### 5. Auth
- API keys minted per account; `Authorization: Bearer <key>`.
- Anonymous shorten allowed (rate-limited); stats and delete require the
  owning key.

## Constraints
- Python 3.11+, FastAPI, Postgres. No external link-shortener APIs.
- p99 resolve latency < 50ms.
