# A3 Compatibility Matrix Template

## Required Fields
Every release that claims compatibility MUST declare:
- Manas descriptor ID (or config hash)
- Kuyu descriptor ID (or config hash)
- Scenario suite ID and seed set
- Swappability parameter ranges (sensor + actuator)
- HF stress event set ID
- Profile ID (P0/P1/P2)
- Learning flags (Core/Reflex)

## Template (Markdown)
| Manas ID | Kuyu ID | Suite | Seeds | Swap Ranges | HF Set | Profile | Core/Reflex Learning |
|------|------|-------|-------|-------------|--------|---------|---------------------|
| <id> | <id> | <suite> | <seeds> | <id> | <id> | <P0/P1/P2> | <on/on> |

## Template (YAML)
```yaml
manas_descriptor_id: <id>
kuyu_descriptor_id: <id>
suite_id: <suite>
seed_set: <seeds>
swap_ranges_id: <id>
hf_event_set_id: <id>
profile_id: <P0|P1|P2>
core_learning: <on|off>
reflex_learning: <on|off>
```
