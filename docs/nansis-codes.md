# NANSIS reference codes in Nansen biotic files

Nansen programme biotic files (NMDBiotic v3.1) use NANSIS-specific values in some coded
fields. BAIT's reference tables list these codes, but do not explain the `samplequality`
ones, so they are recorded here. This note holds code meanings only (class C3); it contains
no survey data.

## `samplequality`

Source: the project lead, 3 October 2026, from the programme's coding conventions.

| Code | Meaning | Convention |
| --- | --- | --- |
| 12 | Station can be used for species identification and biomass analysis (Nansis) | Default for demersal surveys, and for bottom trawls in ecosystem or combined surveys |
| 13 | Station can be used for species identification and catch/effort analysis (Nansis) | Not used on standard pelagic, demersal or combined surveys |
| 14 | Station can be used for species identification of target (Nansis) | Default for pelagic surveys, whichever gear is used (pelagic or demersal trawl) |

Codes 1 to 6 keep their general NMD meanings (BAIT, `knowledge/quality-codes.md`); code 5
means that the gear did not fish correctly.

## Related codes

From BAIT's reference tables (`knowledge/quality-codes.md`):

| Field | Code | Meaning |
| --- | --- | --- |
| `stationtype` | 11 | Station to identify an acoustic registration (Nansis) |
| `stationtype` | 12 | Preselected station for swept-area analysis (Nansis) |
| `gearcondition` | 8 | Rigging or deployment problems (NANSIS) |
| `gearcondition` | 9 | Fishing operation aborted (NANSIS) |

## What the first real files show

Counts reported from the laptop, without survey names:

- **Real survey A (pelagic).** Every station is `stationtype` 11 and `samplequality` 14:
  identification stations only, none for biomass analysis. Outside version 1's scope.
- **Real survey B (combined demersal and pelagic).** The three fields agree on every
  station: all `stationtype` 11 stations are `samplequality` 14; `stationtype` 12 stations are
  `samplequality` 12 with `gearcondition` 1, or `samplequality` 5 with `gearcondition` 9
  (aborted tows).

- **Real survey B, further codes** (rerun at commit `03988a1`). `haulvalidity` is 1 on 120
  stations and 3 on one station, one of the three aborted tows; the other two aborted tows
  carry 1. `lengthmeasurement` codes A, B, E, H and Y occur, E on most catch samples with
  lengths; their NMD meanings are still to be confirmed. `catchproducttype` and
  `sampleproducttype` are 1 throughout.

## Consequence for the inclusion rules (D-09, M2)

A swept-area estimate would select stations with `samplequality` 12 and a normal
`gearcondition`, possibly also requiring `stationtype` 12. D-09 requires the rules behind the
official estimates to be replicated, so the final rule is confirmed against them at M2,
including whether `haulvalidity` (which BAIT describes as conflated with `samplequality`)
plays any part. In survey B it flags only one of the three aborted tows, so on its own it
would not be a sufficient exclusion rule.

The synthetic generator uses `stationtype` 12, `samplequality` 12 and `gearcondition` 1 for
its stations.
