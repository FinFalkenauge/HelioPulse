import Foundation

/// Parses Victron SmartSolar MPPT register values into readable telemetry.
struct VictronRegisterParser {
    
    // Victron VE.Direct register addresses
    enum Register: UInt16 {
        case batteryVoltage = 0xEDBC      // V (× 100)
        case panelVoltage = 0xEDBB        // V (× 100)
        case panelCurrent = 0xEDC0        // A (× 100)
        case loadCurrent = 0xEDBE         // A (× 100), synthetic fallback for text parsing
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
    
    /// Converts raw VE.Direct text field values to a TelemetrySnapshot.
    /// Text-mode uses mV/mA/permille units, so scaling differs from binary dumps.
    static func buildTextSnapshot(
        registers: [Register: Int],
        timestamp: Date = Date()
    ) -> TelemetrySnapshot? {
        let solarVoltage = Double(registers[.panelVoltage] ?? 0) / 1000.0
        let measuredSolarCurrent = Double(registers[.panelCurrent] ?? 0) / 1000.0
        let batteryVoltage = Double(registers[.batteryVoltage] ?? 0) / 1000.0
        let batteryCurrent = Double(registers[.batteryCurrent] ?? 0) / 1000.0
        let measuredSolarPower = Double(registers[.chargePower] ?? 0)
        let derivedSolarCurrent = solarVoltage > 0.1 ? max(0, measuredSolarPower / solarVoltage) : 0
        let solarCurrent = measuredSolarCurrent > 0 ? measuredSolarCurrent : derivedSolarCurrent
        let solarPower = measuredSolarPower > 0 ? measuredSolarPower : max(0, solarVoltage * max(0, measuredSolarCurrent))
        let stateValue = registers[.chargeState] ?? 0
        let modeledSOC = Double(registers[.stateOfCharge] ?? 0) / 10.0
        
        // Map charge state
        let chargeState: ChargeState
        if let state = ChargeStateValue(rawValue: UInt16(stateValue)) {
            chargeState = mapChargeState(state)
        } else {
            chargeState = .float
        }
        
        // IL is load current; do not infer load from PV or battery current.
        let loadCurrent = max(0, Double(registers[.loadCurrent] ?? 0) / 1000.0)
        
        guard (8.0...18.0).contains(batteryVoltage) else { return nil }

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

    /// Converts raw binary register values to a TelemetrySnapshot.
    static func buildBinarySnapshot(
        registers: [Register: Int],
        timestamp: Date = Date()
    ) -> TelemetrySnapshot? {
        let solarVoltage = Double(registers[.panelVoltage] ?? 0) / 100.0
        let measuredSolarCurrent = Double(registers[.panelCurrent] ?? 0) / 100.0
        let batteryVoltage = Double(registers[.batteryVoltage] ?? 0) / 100.0
        let batteryCurrent = Double(registers[.batteryCurrent] ?? 0) / 100.0
        let measuredSolarPower = Double(registers[.chargePower] ?? 0)
        let derivedSolarCurrent = solarVoltage > 0.1 ? max(0, measuredSolarPower / solarVoltage) : 0
        let solarCurrent = measuredSolarCurrent > 0 ? measuredSolarCurrent : derivedSolarCurrent
        let solarPower = measuredSolarPower > 0 ? measuredSolarPower : max(0, solarVoltage * max(0, measuredSolarCurrent))
        let stateValue = registers[.chargeState] ?? 0
        let modeledSOC = Double(registers[.stateOfCharge] ?? 50)

        let chargeState: ChargeState
        if let state = ChargeStateValue(rawValue: UInt16(stateValue)) {
            chargeState = mapChargeState(state)
        } else {
            chargeState = .float
        }

        let loadCurrent = max(0, Double(registers[.loadCurrent] ?? 0) / 100.0)

        guard (8.0...18.0).contains(batteryVoltage) else { return nil }

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
            socConfidence: 0.85,
            driveMode: false,
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
        return parseFieldBlob(text)
    }

    /// Parse a loose Victron text fragment where separators may be corrupted or fragmented.
    static func parseLooseTextFrame(_ text: String) -> [Register: Int]? {
        return parseFieldBlob(text)
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

    private static func parseFieldBlob(_ text: String) -> [Register: Int]? {
        var registers: [Register: Int] = [:]

        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for line in normalized.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedLine.isEmpty else { continue }

            let separators = ["\t", "=", ":", " "]
            let splitParts: [String]
            if let separator = separators.first(where: { trimmedLine.contains($0) }) {
                let parts = trimmedLine.split(separator: Character(separator), maxSplits: 1, omittingEmptySubsequences: true)
                splitParts = parts.map(String.init)
            } else {
                continue
            }

            guard splitParts.count == 2 else { continue }

            let key = splitParts[0].trimmingCharacters(in: .whitespaces).uppercased()
            let valueStr = splitParts[1].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            if let value = parseInt(valueStr) {
                mapTextField(key: key, value: value, registers: &registers)
            }
        }

        return registers.isEmpty ? nil : registers
    }

    private static func parseInt(_ value: String) -> Int? {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned != "---", cleaned.uppercased() != "N/A" else { return nil }
        return Int(cleaned)
    }

    private static func mapTextField(key: String, value: Int, registers: inout [Register: Int]) {
        switch key {
        case "V": registers[.batteryVoltage] = value
        case "VPV": registers[.panelVoltage] = value
        case "IPV": registers[.panelCurrent] = value
        case "PPV", "P", "PV": registers[.chargePower] = value
        case "I": registers[.batteryCurrent] = value
        case "IL": registers[.loadCurrent] = value
        case "SOC": registers[.stateOfCharge] = value
        case "CS": registers[.chargeState] = value
        case "ERR": registers[.errorCode] = value
        default:
            break
        }
    }
}
