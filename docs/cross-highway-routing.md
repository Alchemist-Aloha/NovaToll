# Cross-highway route validation

Nova Toll treats cross-highway routes as directed operator-planner journeys. It
uses the native entry/exit catalog and component ODs; it does not invent a
general-purpose detour when the catalog has no directed route.

## Validation coverage

- The native I-495/I-95/I-395 catalog contains 685 Express-Lanes mappings,
  including 416 mappings whose entry and exit are on different roads.
- Generated tests cover all native mappings plus 1,364 synthetic/outside
  destinations. The I-66 fixture contains 9 eastbound entries with 61 exits
  and 7 westbound entries with 35 exits.
- Seven native probes are recorded in
  `output/cross-highway-investigation/native-probe.json`. Four completed and
  three were incomplete because the provider was closed or unavailable. This
  is evidence of observed behavior, not a live availability guarantee.

## Directed route rules

| Requested movement | Operator path used |
| --- | --- |
| I-66 outside EB → I-66 inside EB | Outside entry → EB GP exit → VDOT entry 1 |
| I-66 inside WB → I-66 outside WB | VDOT exit 1 → outside gantry 417 |
| I-66 outside EB → I-495 NB/SB | Outside EL exit → `187NO` / `187SO`; the official catalog supplies any 95/395 continuation |
| I-66 inside WB → I-495 SB | VDOT exit 5 → `187SO` |
| I-495/I-95/I-395 → I-66 outside WB | Allowed only when the catalog reaches an I-66 interchange |
| I-495 North | Use entry 415, including an I-395 southbound origin via `1879ND` |
| I-495 South | Use entry 414 |

Inside EB continuation is allowed only from the I-495 North interchange. An
inside-EB trip cannot return west to I-495, and an outside-WB trip cannot be
reversed. Preserve these directed restrictions rather than accepting a
same-road or reverse-road pair merely because both markers exist.

## Official references

[Express Lanes entry/exit catalog](https://www.expresslanes.com/themes/custom/transurbangroup/js/on-the-road/entry_exit.js), [I-66 East to I-495 Express](https://expresslanes.com/I66East-to-495Express), [VDOT I-66 tolls](https://vai66tolls.com/Index), and [I-66 Express plan-your-trip pricing](https://ride66express.com/pricing/plan-your-trip/).
