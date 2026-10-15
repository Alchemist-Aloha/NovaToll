# Ramp map coverage

Audit date: 2026-10-15.

The outside-Beltway I-66 planner catalog was available for manual selection but was absent from the map inventory. The map now includes every catalog entry and route-specific exit. Interchanges with several entry ramps offer a ramp picker so the selected operator ID remains unambiguous.

| Corridor | Entries | Exits | Audit scope |
| --- | ---: | ---: | --- |
| I-495 | 16 | 24 | Exact road, direction, type and ID comparison with bundled Express Lanes catalog |
| I-95 | 25 | 23 | Same comparison |
| I-395 | 8 | 11 | Same comparison |
| I-66 inside the Beltway | 16 | 14 | Directional map records compared with bundled catalog and VDOT entry/exit responses |
| I-66 outside the Beltway | 22 | 172 route-specific records | All supported Ride66Express catalog combinations; 17 distinct exit labels |

No additional omissions were found within these supported catalogs. This audit does not establish that the bundled snapshots include every later roadway change.

Outside I-66 has 12 eastbound and 10 westbound entries. Its entry and exit variants share 12 physical interchange markers. `assets/outside66_map.json` explicitly maps all 22 entry IDs and all 17 exit labels to those markers. The locations are approximate image coordinates on the supplied schematic artwork, not surveyed positions or GPS coordinates. No GPS locations were invented.

`PricingService.load` checks that every outside entry and exit has a valid mapping. Connected-road destinations retain their original route IDs and receive the same map positions. `test/map_coverage_test.dart` verifies catalog completeness, all 172 outside entry-to-exit selections and gantry totals using mocked rates, selection among shared Beltway entries, and the rendered marker positions and search results. These fixture checks do not establish current live toll prices.

Operator references: [Ride66Express planner](https://ride66express.com/pricing/plan-your-trip/), [Express Lanes planner](https://www.expresslanes.com/map-your-trip), and [VDOT I-66 tolls](https://vai66tolls.com/).
