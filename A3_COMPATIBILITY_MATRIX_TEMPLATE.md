# A3 Compatibility Matrix Template (Local Copy)

## Required Fields
Every release that claims compatibility MUST declare the following:
- Manas version
- Kuyukai version
- Manas conformance suite version
- Kuyukai scenario suite ID
- Determinism tier and tolerances
- Badge claims (B0/B1/B2)
- OED identifier and version

## Template (Markdown Table)
| Manas | Kuyukai | Conformance Suite | Scenario Suite | Determinism Tier | Tolerances | Badges | OED |
|------|---------|-------------------|----------------|------------------|------------|--------|-----|
| <version> | <version> | <version> | <id> | <tier> | <declared> | <B0/B1/B2> | <id> |

## Template (YAML Block)
```yaml
manas_version: <version>
kuyukai_version: <version>
conformance_suite_version: <version>
scenario_suite_id: <id>
determinism_tier: <Tier0|Tier1|Tier2>
tolerances: <declared>
badges: [<B0>, <B1>, <B2>]
oed_id: <id>
oed_version: <version>
```

