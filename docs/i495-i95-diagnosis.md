# I-495 to I-95 Quantico diagnosis

Checked October 15, 2026 using the official Express Lanes planner catalog, its pricing JavaScript, and its public `infra-price-confirmed-all` response. Raw evidence is under `output/i495-i95-investigation/`.

The requested trip is southbound entry `180SO` (495 Express Lanes Start / George Washington Memorial Parkway) to exit `218SD` (I-95 near Joplin Road / Quantico). Both the bundled and freshly fetched official catalogs assign component ODs `1040` and `1386` to this trip. All 148 bundled I-495 to I-95/I-395 cross-corridor mappings checked also match the fetched official catalog.

| Component | Feed road field | Direction | Status | Returned amount | Source timestamp |
| --- | --- | --- | --- | ---: | --- |
| `od_1040` | `495` | S | open | $7.85 | 2026-10-15 03:00:00 |
| `od_1386` | `395` | S | closed | $7.75 | 2026-10-15 03:00:00 |

The top-level `direction_95` is `N`. The operator's official JavaScript normalizes road `395` to `95` for displaying the combined 95/395 corridor and explicitly displays Closed when that component has closed status. The `395` field on the Quantico component is therefore also present in the operator implementation; it is not an app-generated route substitution.

`PricingService._directQuote` requires all components to have valid amounts and status `open`. It correctly refuses this total because `od_1386` is closed, even though the feed still supplies a numeric amount. Adding the two amounts would present a total for a component the operator marks closed.

The app's wording is imprecise: it returns the same “Lane status unconfirmed or closed” error for explicit closure and unknown status. This response is a confirmed operator-reported closure, not an unconfirmed status, missing route, or transport failure. No application code was changed during this diagnosis.

These findings describe the captured response, not guaranteed present road conditions. The feed advertises a cache maximum age of 3600 seconds and carries the source timestamp above. The operator describes the weekday 95/395 reversible lanes as normally northbound from 2:30 a.m. to 11 a.m., with exceptions for incidents, construction and other events.

Sources: [official planner](https://www.expresslanes.com/map-your-trip), [official entry/exit catalog](https://www.expresslanes.com/themes/custom/transurbangroup/js/on-the-road/entry_exit.js), [official pricing script](https://www.expresslanes.com/themes/custom/transurbangroup/js/on-the-road/on-the-road.js), [pricing feed](https://expresslanes.com/maps-api/infra-price-confirmed-all), and [reversible lane schedule](https://www.expresslanes.com/learn-the-lanes).
