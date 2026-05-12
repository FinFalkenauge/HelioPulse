import Foundation

/// Parses Victron SmartSolar MPPT register values into readable telemetry.
struct VictronRegisterParser {
    
    // Victron VE.Direct register addresses
    enum Register: UInt16 {
        case batteryVoltage = 0xEDBC      // V (× 100)
        case panelVoltage = 0xEDBB        // V (× 100)
        case panelCurrent = 0xEDC0        // A (× 100)
        case batteryCurrent = 0xEDBD      // A (× 100)
        case chargePower = 0xEDF0         // W
        case stateOfCharge = 0xEDE0       // % (0-100)
        case chargeState = 0xEDB9         // 0=off, 1=low, 2=fault, 3=bulk, 4=absorb, 5=float
        case errorCode = 0xEDB8           // Error code
        case signalStrength = 0xEDFF      // RSSI (dBm)
    }
    
    // Charge state mapping from register value
    enum ChargeStateValue: UInt16 {
        case off = 0
        case lowPower = 1
        case fault = 2
        case bulk = 3
        case absorbing = 4
        case floating = 5
    }
    
    /// Converts raw register values to a TelemetrySnapshot.
    static func buildSnapshot(
        registers: [Register: Int],
        timestamp: Date = Date()
    ) -> TelemetrySnapshot {
        let solarVoltage = Double(registers[.panelVoltage] ?? 0) / 100.0
        let solarCurrent = Double(registers[.panelCurrent] ?? 0) / 100.0
        let batteryVoltage = Double(registers[.batteryVoltage] ?? 0) / 100.0
        let batteryCurrent = Double(registers[.batteryCurrent] ?? 0) / 100.0
        let solarPower = Double(registers[.chargePower] ?? 0)
        let stateValue = registers[.chargeState] ?? 0
        let modeledSOC = Double(registers[.stateOfCharge] ?? 50)
        
        // Map charge state
        let chargeState: ChargeState
        if let state = ChargeStateValue(rawValue: UInt16(stateValue)) {
            chargeState = mapChargeState(state)
        } else {
            chargeState = .float
        }
        
        // Solar power → estimated load current (simplified)
        let loadCurrent = solarCurrent > 0 ? solarCurrent * 0.2 : 0.0
        
        return TelemetrySnapshot(
            id: UUID(),
            timestamp: timestamp,
            solarPower: solarPower,
            solarVoltage: solarVoltage,
            solarCurrent: solarCurrent,
            batteryVoltage: batteryVoltage,
            batteryCurrent: batteryCurrent,
            loadCurrent: loadCurrent,
            chargeState: chargeState,
            modeledSOC: modeledSOC,
            socConfidence: 0.85,  // Victron MPPT is generally accurate
            driveMode: false,      // MPPT doesn't know about vehicle state
            primarySource: .solar
        )
    }
    
    /// Parse a Victron VE.Direct frame (hex-encoded register dump).
    static func parseFrame(_ frameData: Data) -> [Register: Int]? {
        // Victron frames are typically formatted as:
        // <header><register_id><value><checksum>
        // This is a simplified parser; actual format depends on Victron protocol version
        
        guard frameData.count >= 4 else { return nil }
        
        var registers: [Register: Int] = [:]
        var offset = 0
        
        while offset + 3 < frameData.count {
            let registerId = UInt16(frameData[offset]) << 8 | UInt16(frameData[offset + 1])
            let value = Int(frameData[offset + 2]) << 8 | Int(frameData[offset + 3])
            
            if let register = Register(rawValue: registerId) {
                registers[register] = value
            }
            
            offset += 4
        }
        
        return registers.isEmpty ? nil : registers
    }
    
    /// Parse a flat Victron text frame (key=value pairs, LF-separated).
    static func parseTextFrame(_ text: String) -> [Register: Int]? {
        var registers: [Register: Int] = [:]
        
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else {
                continue
            }

            let parts: [String]
            if let tabIndex = trimmedLine.firstIndex(of: "\t") {
                let keyPart = String(trimmedLine[..<tabIndex])
                let valuePart = String(trimmedLine[trimmedLine.index(after: tabIndex)...])
                parts = [keyPart, valuePart]
            } else if let eqIndex = trimmedLine.firstIndex(of: "=") {
                let keyPart = String(trimmedLine[..<eqIndex])
                let valuePart = String(trimmedLine[trimmedLine.index(after: eqIndex)...])
                parts = [keyPart, valuePart]
            } else {
                continue
            }

            let key = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
            let valueStr = parts[1].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, let value = Int(valueStr) else {
                continue
            }
            
            // Map common Victron field names to registers
            switch key {
            case "V": registers[.batteryVoltage] = value
            case "VPV": registers[.panelVoltage] = value
            case "PPV": registers[.chargePower] = value
            case "I": registers[.batteryCurrent] = value
            case "IL": registers[.panelCurrent] = value
            case "SOC": registers[.stateOfCharge] = value
            case "CS": registers[.chargeState] = value
            case "ERR": registers[.errorCode] = value
            default: break
            }
        }
        
        return registers.isEmpty ? nil : registers
    }
    
    // MARK: - Private Helpers
    
    private static func mapChargeState(_ victronState: ChargeStateValue) -> ChargeState {
        switch victronState {
        case .off:
            return .off
        case .lowPower:
            return .float  // Not directly supported, use float
        case .fault:
            return .storage  // Error state, closest match
        case .bulk:
            return .bulk
        case .absorbing:
            return .absorption
        case .floating:
            return .float
        }
    }
}
