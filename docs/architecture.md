# Architecture

## Data Flow

1. Bluetooth scanner receives telemetry payloads.
2. Decoder normalizes raw values to typed snapshots.
3. Snapshot pipeline enriches values with quality metadata.
4. Persistence stores snapshots in minute buckets.
5. Feature view models derive live KPIs, trend lines, and forecasts.

## Forecast Model

- Input: battery voltage, battery current, load current, solar input power.
- Output: runtime estimate for conservative, realistic, optimistic scenarios.
- Confidence: lowered when alternator charge is detected without measured alternator current.

## SOC Model

- Primary: coulomb-counting style modeled SOC from known load and charge paths.
- Drift correction: recharge anchor, low-voltage anchor, and idle smoothing.
- Confidence band shown in UI at all times.

## Future Extensions

- optional SmartShunt calibration channel
- optional cloud sync
- widget and lock screen glance cards
