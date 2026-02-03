# A3 Compatibility Matrix Template (v2.4)

## Required Fields
Every release that claims compatibility MUST declare:
- Manas version
- Kuyu version
- Scenario suite ID and seed set
- Swappability parameter ranges (sensor + actuator)
- HF stress event set version
- Profile ID (P0/P1/P2)
- Learning flags (Core/Reflex)

## Template (Markdown)
| Manas | Kuyu | Suite | Seeds | Swap Ranges | HF Set | Profile | Core/Reflex Learning |
|------|------|-------|-------|-------------|--------|---------|---------------------|
| <ver> | <ver> | <suite> | <seeds> | <id> | <id> | <P0/P1/P2> | <on/on> |

## Template (YAML)
```yaml
manas_version: <ver>
kuyu_version: <ver>
suite_id: <suite>
seed_set: <seeds>
swap_ranges_id: <id>
hf_event_set_id: <id>
profile_id: <P0|P1|P2>
core_learning: <on|off>
reflex_learning: <on|off>
```
