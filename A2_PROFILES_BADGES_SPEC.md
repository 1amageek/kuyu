# A2 Capability Profiles and Declarations (v2.4)

## Purpose
Profiles communicate which **learning and interface capabilities** are enabled. All evaluation reports must declare a profile.

## Profiles
### P0 Integration-Only (non-learning)
- Core learning: disabled
- Reflex learning: disabled
- Used for smoke tests only (not M1-eligible)

### P1 M1-Ready (required for milestone M1)
- Core learning: enabled
- Reflex learning: enabled
- Passes Suite-1..Suite-5 under declared ranges

### P2 CMI-Experimental (optional)
- CMI enabled with low-bandwidth latent interaction
- Must remain ignorable and safety-bounded

## Declaration Format
Each report MUST include:
- Profile ID (P0/P1/P2)
- Core learning on/off
- Reflex learning on/off
- NerveBundle/Gating/Trunks version IDs
- DAL limits version
- Kuyu suite ID and seed set

## Change Control
Any change that alters profile requirements or evaluation criteria is a breaking change.
