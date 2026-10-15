# Nova Toll project download

Source revision: 9866ed0f477a24571c55301b182f5aff502f3da7

## Requirements
- Node.js 20 or newer
- Python 3 (available as `python` for the build script)
- Bash for scripts/build.sh

No npm dependencies are needed for the current implementation.

## Build and check
From this directory:

```bash
bash scripts/build.sh
node scripts/validate-artifact.mjs
node scripts/verify-ui.mjs
node scripts/verify-i66.mjs
node scripts/verify-browser66.mjs
```

The deployable Worker ESM entry point is `dist/server/index.js`. It exports the standard Worker fetch handler. `worker/index.js` is the checked-in assembled version. The UI is assembled from `ui/`, `server/`, and `assets/`; edit those sources and rebuild. The HTML contains build placeholders, so opening ui/index.html directly is not a working preview. Run the assembled Worker in a compatible Worker runtime.

## Current I-66 outside-Beltway status
The current source includes the visitor-browser POST adapter, official entry/exit catalog, connected I-495 route pricing, and downloadable diagnostic reports. The browser request has not produced a readable pricing response from Nova Toll. A successful official-site response supplied by the user allows origin https://ride66express.com, consistent with CORS blocking the separate Nova Toll origin. No browser extension or userscript bridge is included. The operator planner labels its estimates as based on historical averages; realtime accuracy is unverified. Earlier README wording about the adapter being unconnected predates this revision.

This ZIP contains the tracked project files, including the supplied map, fonts, documentation and tests. It excludes Git history, local runtime state, credentials and uploaded diagnostic files. The hosting manifest retains the original Site project identifier; use a new identifier if deploying an independent Site.
