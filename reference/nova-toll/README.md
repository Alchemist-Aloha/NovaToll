# Nova Toll

An image-backed, three-panel trip planner for Northern Virginia express lanes.

- **Map:** original user-supplied PNG, approximately calibrated ramp dots, two-dot entry/exit flow, both-direction route validation, ambiguous-ramp and lane choices, drag/pinch/keyboard navigation, search.
- **Manual / GPS:** road, direction, entry and connected destination selectors; one-shot GPS entry suggestion with explicit route confirmation.
- **Toll:** complete estimate or clearly incomplete subtotal, priced legs, operator freshness warnings, refresh, saved common trips. Saved trips remain available without first selecting a new route.

The page uses self-hosted DM Sans and Manrope with navy, coral, teal and ivory surfaces. Only one main panel is visible at a time. Old saved-exit records migrate to common trips when their endpoints resolve.

## Sources and limits

`server/pricing.js` retains the official Express Lanes OD catalog and pricing endpoint for I-495, I-95 and I-395, plus VDOT’s I-66 inside-Beltway calculator. I-66 outside-Beltway express pricing is unavailable and never inferred. The background image includes historical construction/study notes; it does not provide live road status. Dot coordinates are interpolated along hand-calibrated image highway lines and are approximate because the map is not to scale.

`assets/map.png` is the supplied image unchanged. `assets/provenance.json` records image and font provenance. Source fonts are served locally.

## Build and verify

Run `bash scripts/build.sh`, `node scripts/validate-artifact.mjs`, and `node scripts/verify-ui.mjs` from the project root. The build runs `scripts/assemble.py`, which embeds UI, data, image and fonts into the dependency-free Worker ESM artifact.

Behavioral verification covers two-dot cross-highway selection, exclusive panels, endpoint coordinate bounds, retained SVG focus, saved trips in empty state, manual I-95 selection, response race handling and GPS denial. Server catalog and exit checks cover all three Express Lanes corridors. The image endpoint was checked against the original SHA-256. A static overlay diagnostic was visually checked for image alignment. Device/browser visual QA is unavailable in the current environment.

I-66 source investigation: see docs/i66-pricing-sources.md. Run `node scripts/verify-i66.mjs` to verify retry and invalid-rate handling. Outside-Beltway live pricing remains unconnected; official operator app links are provided rather than fabricated or historical totals.
