# Current implementation — October 15, 2026

The user-supplied operator `plan-your-trip.js` version 1.4.8 established the request and calculation contract. Earlier investigation notes below describe the previous state and are superseded by this implementation.

The visitor browser POSTs URL-encoded form data to `https://ride66express.com/wp-content/themes/i66/theme-ajax.php`: `action=api_call`, `data[starting_gantry_id]`, `data[ending_gantry_id]`, optional `data[middle_ending_gantry_id]` and `data[first_ending_gantry_id]`, `data[xvWr]=1`, and an empty `data[response]`. For a chain of three exits, the last is ending, the preceding is middle, and the first is first. The literal xvWr value is from the public script, not a credential. Requests omit cookies and referrer; no GPS coordinates are transmitted. A 15-second timeout and 2 MB response limit apply.

Rates come from `data.curl_response.rates`. For each distinct required gantry (start and all ending gantries), select the latest `rateEndDate`, take `gantry.vehicleClasses[0].rateAmountTag`, and sum. Never double-count a repeated start/end gantry. Missing components, malformed values, or invalid dates prevent a full quote; zero remains valid. Original timestamps are shown without a claim of freshness.

The 22 entry groups and their reachable exit chains in `ui/outside66.json` come from the supplied HTML entry selectors and script exit options. Manual selection supports both directions. Existing I-495 → I-66 west destinations map northbound Express to entry 415 and southbound Express to 414; Route 50 ends at the entry gantry, Monument/Stringfellow/Route 28 at 420, and Gainesville Route 29 at 420,423,425. Combined trips retain known component subtotals when either provider fails.

The operator's planner disclosure describes standard-vehicle, historical-average estimates. Accordingly, successful amounts are labeled operator planner estimates, never verified realtime prices. This request still returned HTTP 403 from our server. Successful production response via the visitor browser remains unconfirmed. This implementation tests the browser transport rather than guaranteeing that it resolves IP blocking or CORS.

`verify-browser66.mjs` covers request fields, route validation, newest-rate selection, sums, duplicate gantries, zero and invalid amounts, missing rates, HTTP/JSON/CORS/timeout errors, response limits, and report download. `verify-ui.mjs` covers native and connected trips plus partial failures. Tests use fixtures; they do not establish a successful live feed. Pricing report v3 records the local request and response, calculation components, and timestamps for user-assisted diagnosis. It always retains `livePriceVerified: false` and is not automatically uploaded. The third-party script itself is neither executed nor bundled.

## Historical investigation — October 14, 2026


Inside the Beltway: the current VDOT calculator endpoint returned a valid JSON estimate in direct testing. The adapter now retries once for transient transport, HTTP, parsing, or invalid-rate failures. Native I-66 trips and connected I-495 → I-66 east trips use the same strict validator. Zero is accepted only when supplied as a numeric operator rate.

Outside the Beltway: no reusable live endpoint was verified. This is an integration limitation, not proof that no private feed exists. Both ride66express.com planner paths and the app's public WordPress content endpoint returned CloudFront HTTP 403 from this environment. The official planner's indexed disclosure says its estimates are based on historical averages. Those estimates must not be labeled real-time or used to complete an otherwise incomplete trip total.

The official Ride66Express app advertises checking current rates. Its Android package exposes a public WordPress content API and embedded web content; no independently verified timestamped live toll endpoint was obtained. Express Saver also advertises outside-Beltway support, but an accessible API could not be verified.

Virginia 511's own public layer configuration points to https://data.511-atis-ttrip-prod.iteriscloud.com/datasets/tolls/toll_pricing.geojson . The retrieved feed contained 74 features, including eight I-66 zone origins entirely inside the Beltway (Capital Beltway Beginning, Lee Highway, Fairfax Drive, Spout Run Parkway, Glebe Road, Sycamore Street, Leesburg Pike, Capital Beltway End). It did not supply outside-Beltway destinations. Its interval timestamps were older than current direct calculator responses. It is not used as an outside-Beltway substitute.

Public source references:
- https://vai66tolls.com/
- https://ride66express.com/pricing/plan-your-trip/
- https://play.google.com/store/apps/details?id=com.ferrovial.i66
- https://apps.apple.com/us/app/ride66express/id6503947943
- https://apps.apple.com/us/app/express-saver/id1356633588
- https://511.vdot.virginia.gov/services/511/map/layers/map

The UI exposes operator app links when an outside-Beltway express leg has no connected live source, keeps the known subtotal distinct, and never invents a total.

## Visitor-browser connection test
The Toll estimate panel includes an explicit browser-only GET to the exact public planner URL. It uses CORS with credentials omitted and no referrer, a 15-second timeout, and a 2 MB response limit. No route identifiers or GPS coordinates are transmitted. There is no server proxy or automatic retry. The result distinguishes readable pages, HTTP errors, timeout, oversized responses, and browser-level failures (where CORS versus networking cannot be determined). A local JSON download preserves the anonymous public response for endpoint inspection; fetched markup is never rendered or executed. Success does not establish a live pricing feed or change a trip total. The pricing endpoint remains unidentified.

Visitor report at 2026-10-15T00:19:13Z confirmed HTTP 200, CORS-readable HTML (112,678 bytes) through the visitor browser. The page explicitly states historical-average estimates. Its `planYourTripObject.ajaxUrl` points to `https://ride66express.com/wp-content/themes/i66/theme-ajax.php`; request actions and parameters are not in the HTML. The observed planner script is `https://ride66express.com/wp-content/themes/i66/assets/js/modules/plan-your-trip.js?ver=1.4.8`, still HTTP 403 from the server. Report v2 captures that exact planner asset through the visitor browser when the page references it, without executing it. Script failure preserves the successful page response. No AJAX action is guessed or invoked until the script can be inspected.
