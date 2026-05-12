# HelioPulse

HelioPulse is a premium, dark-first iOS energy cockpit for Victron SmartSolar MPPT systems.

## Goal

Provide better live insight than the default app, with:
- rich trends and beautiful charts
- modeled battery state of charge (SOC) with confidence band
- runtime forecast in conservative, realistic, and optimistic scenarios

## Scope (MVP)

- iOS first
- Bluetooth data path for SmartSolar telemetry
- dark theme with chart-centric UI
- alternator-aware confidence handling for drive sessions

## Accuracy Notes

If all consumers run through the MPPT load output, SOC modeling is viable without a shunt.
If additional charge or load paths bypass the MPPT measurement, confidence is reduced automatically.

## Repository Layout

- `App` app entry and root navigation
- `DesignSystem` theme tokens and reusable components
- `Features` live dashboard, trends, forecast
- `Data` telemetry models and bluetooth abstraction
- `Persistence` local storage interfaces
- `docs` architecture and design documentation

## Local Setup

1. Install Xcode 16 or newer.
2. Install XcodeGen:
   - `brew install xcodegen`
3. Generate project:
   - `xcodegen generate`
4. Open and run:
   - `open HelioPulse.xcodeproj`

## GitHub Quick Start

1. `git init`
2. `git add .`
3. `git commit -m "chore: bootstrap HelioPulse"`
4. `git branch -M main`
5. `git remote add origin <your-repo-url>`
6. `git push -u origin main`

## Internal Test Checklist

- Connect to a real Victron SmartSolar MPPT and verify live values update every few seconds.
- Toggle Bluetooth off/on while app is running and confirm reconnect without app restart.
- Put app in background for 2 minutes, return to foreground, and verify data flow resumes.
- Validate charts and forecast update with changing solar input.
- Verify orientation behavior on iPhone and iPad in all supported orientations.
