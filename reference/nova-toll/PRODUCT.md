# Nova Toll

## Purpose and audience
A practical Northern Virginia trip planner for commuters and passengers checking operator toll estimates before entering express lanes. Choose an original entry and destination, then review a route-specific estimate. Use while parked or have a passenger operate it.

## Primary workflow
Three exclusive panels organize the task: Map, Manual / GPS, and Toll estimate. Selecting one hides the others. The map starts with entry selection, then destination selection; A and B identify the chosen ramps. Reachable matches are validated against operator route metadata, including both directions rather than inferring direction from image geometry. Ambiguous destinations or nearby markers offer explicit choices. The Manual / GPS panel provides highway, direction, entry, and reachable destination selectors. Results appear in their own panel with amount, component legs, freshness context, and save/refresh/edit actions.

## Coverage
I-495, I-95, and I-395 origins use the full official origin/destination catalog with supported connections. I-66 inside the Beltway supports eastbound and westbound routes through VDOT's calculator. Catalog inclusion does not prove a ramp is open or a current price is available.

Connected routes to I-66 east combine current component estimates where a verified connection exists. I-66 outside-Beltway entries and exits are available in Manual / GPS. Native trips and supported I-495 → I-66 west connections request the operator planner estimate directly from the visitor browser. Combined results are labeled estimates; failures show an incomplete total and any known subtotal. Supported regular-lane alternatives add a zero-priced regular-lane leg; no outside-Beltway express toll is included. Never infer an unavailable toll from distance, historical rates, or another corridor.

## Supplied map and coordinates
The full background is the user-supplied map image, retained as artwork rather than generated road geometry. Interactive ramp positions are hand-calibrated approximately along its drawn highways; they are not surveyed coordinates or a navigation map. The printed construction, study, and Opitz annotations are historical artwork, not current road-status information. Ramp names, supported routes, and prices come from operator metadata and responses. The map depicts supported ramps and highway connections, not exhaustive geographic street intersections.

Drag to pan, pinch or use plus/minus to zoom, and Full map to fit. Modifier-wheel and keyboard controls are available. Gesture movement or cancellation suppresses selection. A tap considers nearby markers within 26 viewport pixels; close candidates show a choice list. Marker hit areas remain approximately screen-sized while zooming. Search provides ramp-name lookup. Verify ramp names and actual signs before traveling.

## GPS and storage
GPS performs a one-time browser location request. Accuracy must be at most 200m and a supported entry within 5km. A finite heading at speed at least 2m/s constrains direction; otherwise confirm direction manually. The suggestion populates manual fields; select a destination and calculate to confirm the trip. Coordinates stay in the browser and are not sent to pricing APIs. Proximity cannot distinguish express from regular lanes, establish ramp access, or recover an original entry after joining express lanes.

Common trips, including origin and destination route identifiers, are stored in browser local storage under `nova-toll-trips`. They can be loaded and deleted. Storage failure falls back to the current session with a notice. There is no account or cross-device sync; old exit-only saved data is not the current trip format.

## Pricing and freshness
Express Lanes prices use `https://expresslanes.com/maps-api/infra-price-confirmed-all`; I-66 inside uses `https://vai66tolls.com` current calculator requests. Numeric nonnegative Express Lanes prices are summed only for open component statuses. Errors, unconfirmed lane status, missing prices, and partial totals remain explicit. Displayed amounts describe a standard vehicle paid E-ZPass trip, not HOV eligibility or a guaranteed charge. Posted roadside prices govern and may change before entry or before a later component of a connected trip.

Fetched time records request processing timing and does not prove a newly updated rate. Express Lanes component timestamps older than five minutes, missing, invalid, or over one minute in the future produce a warning. Eastern time is used. Inside-Beltway I-66 responses do not supply a rate timestamp. Outside-Beltway responses expose original rate-end strings, but their timezone and freshness remain unverified. Neither uses Express Lanes freshness verification. Auto-refresh runs every 60 seconds only while the Toll estimate panel is visible, the document is visible, a trip exists, and no request is busy. Manual refresh is available.

## Implementation and verification boundaries
`ui/index.html` owns layout and styles, `ui/app.js` owns interaction, and `server/pricing.js` owns catalog/pricing endpoints. `scripts/assemble.py` embeds the UI, ramp inventory, supplied image, and self-hosted fonts into the worker. `assets/provenance.json` records source provenance. This documentation was checked against source; browser visual and physical-device gesture QA were unavailable.

## I-66 current-source verification (October 14, 2026)
Inside-Beltway trips now share a strictly validated current-calculator adapter with one retry for transient failures. Outside-Beltway browser integration uses the supplied operator script contract as of October 15. Calculation and failure handling pass fixture tests; successful production browser transport remains to be confirmed. Results are explicitly operator planner estimates, with the historical-average disclosure, rather than verified realtime rates. See docs/i66-pricing-sources.md for sources and tested coverage.
