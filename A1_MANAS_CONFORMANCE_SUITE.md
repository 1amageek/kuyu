# A1 Manas Training and Evaluation Suite Specification (v2.4)

## Scope
Defines required training and evaluation runs for **Manas v2.4** under the **Kuyu** training world. Focus is quadcopter attitude stabilization with same-type swappability and high-frequency (HF) stress.

## Required Declarations (per run)
- Scenario suite ID (Suite-0..Suite-5) and seeds
- World step size `dt`, sensor/update periods, CUT update period
- Sensor swap parameter ranges (gain, bias, noise, delay, bandwidth, dropout)
- Actuator swap parameter ranges (max_output, time_const, deadzone, gain, rate_limit, asymmetry)
- HF stress event set (impulse, vibration, brief glitches)
- NerveBundle/Gating/Trunks definition (type + version)
- Core and Reflex learning enabled/disabled flags
- DAL protection limits

## Required Suites
- **Suite-0 Warmup**: no swaps, no HF stress (smoke, stability baseline)
- **Suite-1 Sensor Swappability**: sensor swaps injected mid-run
- **Suite-2 Actuator Swappability**: actuator swaps injected mid-run
- **Suite-3 Reflex HF Training**: impulse/vibration/glitch emphasis
- **Suite-4 Bundle/Gating Stress**: abrupt salience shifts + normalization stress
- **Suite-5 Combined**: swaps + HF + bundle/gating stress together

## Required Metrics
- No sustained failure (safety envelope)
- Recovery time after each swap event
- Transient overshoot (max tilt/omega)
- Violation budget (time above thresholds)
- HF stability score (oscillation/chatter indicators)
- Bundle/Gating stability proxy (avoid runaway gating or collapse)

## Required Logs
- Raw sensor streams (post-emulation)
- NerveBundle outputs and Gating coefficients
- Trunks (energy/phase/quality)
- Core DriveIntent outputs
- Reflex corrections (clamp/damping/micro-intent)
- DAL actuator commands
- Plant attitude/omega traces
- Event schedule + seed

## Reporting
Each run must publish:
- Suite + seed list
- Metric summary per scenario
- Aggregate summary (avg recovery, worst overshoot, avg HF score)
- Learning flags (Core/Reflex)
