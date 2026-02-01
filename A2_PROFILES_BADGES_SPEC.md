# A2 Profiles and Badges Specification (Local Copy)

## Purpose
Badges classify implementation guarantees and scope. **All conformance/validation claims must declare badges**; claims without badges are incomplete.

## Badges
### B0 Manas‑Baseline (required)
- Numeric channelIndex only; no semantic labels or tokens
- Continuity and total variation constraints satisfied
- Phase anti‑token checks pass

### B1 Manas‑Profile IMU6 Fixed Mapping
- Assumes Kuyukai IMU6 channel mapping (indices 0..5)
- No requirement for permutation robustness
- Intended for milestone M1

### B2 Manas‑Strict Permutation Robust
- Must pass permutation scenarios that reassign channelIndex mappings
- Demonstrates reduced reliance on fixed index semantics

## Declaration Format (per report)
Each report MUST include:
- Implementation identifier and version
- Badge list (B0/B1/B2)
- Any fixed mapping assumptions
- OED identifier and version
- Test suite or scenario suite identifiers

## Change Control
Any change that alters badge requirements or test criteria is a breaking change and must be reflected in the compatibility matrix.

