# I-66 outside-Beltway pricing investigation — October 15, 2026

The native app successfully retrieves operator planner estimates. The previous HTTP 403 was caused by the missing AJAX request header, not a missing pricing endpoint.

## Public website contract

The official planner page at https://ride66express.com/pricing/plan-your-trip/ publishes `planYourTripObject.ajaxUrl` as:

`https://ride66express.com/wp-content/themes/i66/theme-ajax.php`

It references `/wp-content/themes/i66/assets/js/modules/plan-your-trip.js?ver=1.4.8`. Both HTML and script were retrieved with HTTP 200 during this investigation. Browser navigation from this environment still encountered a CloudFront 403; that is distinct from the endpoint's plain-text rejection of requests without its AJAX header.

POST a URL-encoded form with the following fields:

| Field | Example: I-495 northbound Express to Route 28 |
| --- | --- |
| `action` | `api_call` |
| `data[starting_gantry_id]` | `415` |
| `data[ending_gantry_id]` | `420` |
| `data[middle_ending_gantry_id]` | empty |
| `data[first_ending_gantry_id]` | empty |
| `data[xvWr]` | `1` |
| `data[response]` | empty |

The required transport header is `X-Requested-With: XMLHttpRequest`. A controlled comparison with the same route/body returned HTTP 403 without it and HTTP 200 JSON with it. Cookies, GPS coordinates, browser impersonation headers, and a referer are not required by the successful native request. Evidence is in `output/i66-investigation/transport-comparison.json` and its response files.

For ending chains, use the final gantry as ending, the preceding one as middle, and the first of a three-gantry chain as first. The response includes `data.curl_response.rates`; `curl_response` can be a JSON object or JSON string.

For each distinct required gantry, select its newest `rateEndDate` and take `gantry.vehicleClasses[0].rateAmountTag`. Sum each gantry once, including when start and end are the same. Reject missing rates, invalid timestamps, negative/non-numeric values, and non-successful responses. Do not complete a connected-road total if either provider is unavailable.

## Native app verification

`flutter test tool/live_i66_probe_test.dart` explicitly opts into real native Dart HTTP, outside Flutter's normal mocked network transport. It calls the actual `PricingService` implementation with the bundled route catalog, validates returned amounts and components, and writes a timestamped JSON report. It is deliberately outside the default `test/` suite so ordinary tests do not rely on internet availability.

The October 15 probe returned:

| Route | Required gantries | Observed amount |
| --- | --- | --- |
| Western Entry → Walney Road / Route 28 | 401, counted once | $5.05 |
| Western Entry → Vaden Drive | 401 + 407 + 411 | $11.90 |
| I-495 northbound Express Lanes → Century Park | 415 + 420 + 423 + 425 | $12.45 |

The full quote, component amounts, and original rate timestamps are recorded in `output/i66-investigation/native-probe.json`. These are observed planner responses, not guaranteed current prices. The operator page labels its planner as based on standard-vehicle historical averages. Rate-end strings do not establish verified freshness or a timezone. Posted roadside prices govern.

The fixture tests now require the AJAX header and verify gantry form fields, preventing regression to the HTTP 403 transport. The implementation change is restricted to the outside-Beltway POST header.

Native Android is not subject to browser CORS. A successful native request does not establish that a separate-origin website can read this endpoint. Physical-device GPS and gestures were outside this investigation.
