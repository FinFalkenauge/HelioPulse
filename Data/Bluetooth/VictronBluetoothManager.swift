import Foundation
import CoreBluetooth
import OSLog

/// Manages Bluetooth communication with Victron SmartSolar MPPT charge controllers.
/// Handles scanning, connection, and register reading via BLE.
class VictronBluetoothManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    enum ConnectionState {
        case idle
        case scanning
        case connecting
        case connected
        case disconnected(Error?)
    }
    
    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var continuation: AsyncStream<TelemetrySnapshot>.Continuation?
    private var onTerminate: (() -> Void)?
    var onConnectionStateChange: ((ConnectionState) -> Void)?
    var onHistoryPayload: ((VictronHistoryPayload) -> Void)?
    
    // Custom Victron VE.Direct BLE UUIDs
    private let victronServiceCustomUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    private let victronTxUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let victronRxUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var scanTimeoutTask: Task<Void, Never>?
    private var noDataTimeoutTask: Task<Void, Never>?
    private var readPollTask: Task<Void, Never>?
    private var hexPollTask: Task<Void, Never>?
    private var readableCharacteristics: [CBCharacteristic] = []
    private var writableCharacteristics: [CBCharacteristic] = []
    private var preferredWritableCharacteristic: CBCharacteristic?
    private var textBuffer = ""
    private var hexBuffer = ""
    private var hasReceivedAnyPayloadSinceConnect = false
    private var hasReceivedTelemetrySinceConnect = false
    private var payloadPreviewCount = 0
    private var parseMissCount = 0
    private var lastHistoryFingerprint = ""
    private let logger = Logger(subsystem: "com.heliopulse.app", category: "BLE")
    
    override init() {
        super.init()
        self.centralManager = CBCentralManager(delegate: self, queue: .main)
        logger.notice("VictronBluetoothManager initialized")
    }
    
    /// Start scanning for Victron MPPT devices and stream telemetry.
    func telemetryStream() -> AsyncStream<TelemetrySnapshot> {
        return AsyncStream { continuation in
            self.continuation = continuation
            self.onTerminate = { continuation.finish() }
            self.logger.notice("Telemetry stream opened")
            
            // Start scanning for Victron devices
            if let centralManager = centralManager, centralManager.state == .poweredOn {
                startScan(on: centralManager)
            }

            continuation.onTermination = { _ in
                self.logger.notice("Telemetry stream terminated")
                self.stopScanning()
            }
        }
    }
    
    /// Stop scanning and disconnect.
    func stopScanning() {
        logger.notice("Stop scanning/disconnect requested")
        centralManager?.stopScan()
        scanTimeoutTask?.cancel()
        scanTimeoutTask = nil
        noDataTimeoutTask?.cancel()
        noDataTimeoutTask = nil
        readPollTask?.cancel()
        readPollTask = nil
        hexPollTask?.cancel()
        hexPollTask = nil
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        readableCharacteristics.removeAll()
        writableCharacteristics.removeAll()
        preferredWritableCharacteristic = nil
        hasReceivedAnyPayloadSinceConnect = false
        hasReceivedTelemetrySinceConnect = false
        textBuffer.removeAll(keepingCapacity: true)
        hexBuffer.removeAll(keepingCapacity: true)
        payloadPreviewCount = 0
        parseMissCount = 0
        onConnectionStateChange?(.idle)
    }
    
    // MARK: - CBCentralManagerDelegate
    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        logger.notice("Central state changed: \(self.describe(state: central.state), privacy: .public)")
        if central.state == .poweredOn, continuation != nil {
            startScan(on: central)
        } else if central.state != .poweredOn {
            onConnectionStateChange?(.disconnected(nil))
        }
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: NSNumber
    ) {
        // Look for Victron MPPT devices (name typically contains "Victron" or has known UUIDs)
        // Match known Victron device name prefixes (SmartSolar, MPPT, BlueSolar, VE.Direct, Victron)
        let discoveredName = peripheral.name ?? "<unknown>"
        logger.debug("Discovered peripheral name=\(discoveredName, privacy: .public) rssi=\(rssi.intValue)")
        if let name = peripheral.name,
           name.localizedCaseInsensitiveContains("Victron") ||
           name.localizedCaseInsensitiveContains("MPPT") ||
           name.localizedCaseInsensitiveContains("SmartSolar") ||
           name.localizedCaseInsensitiveContains("BlueSolar") ||
           name.localizedCaseInsensitiveContains("VE.Direct") {
            logger.notice("Selected peripheral \(name, privacy: .public) id=\(peripheral.identifier.uuidString, privacy: .public)")
            central.stopScan()
            scanTimeoutTask?.cancel()
            scanTimeoutTask = nil
            connectedPeripheral = peripheral
            peripheral.delegate = self
            onConnectionStateChange?(.connecting)
            central.connect(peripheral, options: nil)
        }
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        reconnectAttempts = 0
        hasReceivedAnyPayloadSinceConnect = false
        hasReceivedTelemetrySinceConnect = false
        readableCharacteristics.removeAll()
        writableCharacteristics.removeAll()
        preferredWritableCharacteristic = nil
        textBuffer.removeAll(keepingCapacity: true)
        hexBuffer.removeAll(keepingCapacity: true)
        logger.notice("Connected to peripheral \(peripheral.identifier.uuidString, privacy: .public)")
        onConnectionStateChange?(.connected)
        // Discover all services for maximum compatibility across Victron firmware variants.
        peripheral.discoverServices(nil)
        scheduleNoDataTimeout(for: peripheral, on: central)
        startReadPolling(for: peripheral)
    }
    
    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown", privacy: .public)")
        onConnectionStateChange?(.disconnected(error))
        retryOrRescan(on: central)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        logger.warning("Disconnected from peripheral \(peripheral.identifier.uuidString, privacy: .public) reason=\(error?.localizedDescription ?? "none", privacy: .public)")
        onConnectionStateChange?(.disconnected(error))
        noDataTimeoutTask?.cancel()
        noDataTimeoutTask = nil
        readPollTask?.cancel()
        readPollTask = nil
        hexPollTask?.cancel()
        hexPollTask = nil
        hasReceivedAnyPayloadSinceConnect = false
        hasReceivedTelemetrySinceConnect = false
        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        readableCharacteristics.removeAll()
        writableCharacteristics.removeAll()
        preferredWritableCharacteristic = nil
        retryOrRescan(on: central)
    }
    
    // MARK: - CBPeripheralDelegate
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard error == nil else {
            logger.error("Service discovery error: \(error!.localizedDescription, privacy: .public)")
            return
        }
        logger.notice("Services discovered count=\(peripheral.services?.count ?? 0)")
        
        // Discover characteristics on all services. Some devices expose telemetry on unexpected UUIDs.
        if let services = peripheral.services {
            for service in services {
                logger.debug("Discovering characteristics service=\(service.uuid.uuidString, privacy: .public)")
                if service.uuid == victronServiceCustomUUID {
                    peripheral.discoverCharacteristics([victronTxUUID, victronRxUUID], for: service)
                } else {
                    peripheral.discoverCharacteristics(nil, for: service)
                }
            }
        }
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            logger.error("Characteristic discovery error for service=\(service.uuid.uuidString, privacy: .public): \(error!.localizedDescription, privacy: .public)")
            return
        }
        logger.notice("Characteristics discovered service=\(service.uuid.uuidString, privacy: .public) count=\(service.characteristics?.count ?? 0)")
        
        if let characteristics = service.characteristics {
            for characteristic in characteristics {
                logger.debug("Characteristic uuid=\(characteristic.uuid.uuidString, privacy: .public) props=\(characteristic.properties.rawValue)")
                if characteristic.uuid == victronTxUUID {
                    txCharacteristic = characteristic
                    // Request notifications for incoming data
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.uuid == victronRxUUID {
                    rxCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                } else {
                    // Fallback: subscribe/read any characteristic that can provide telemetry.
                    if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                        peripheral.setNotifyValue(true, for: characteristic)
                    }
                    if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse) {
                        writableCharacteristics.append(characteristic)
                        if preferredWritableCharacteristic == nil {
                            preferredWritableCharacteristic = characteristic
                        }
                        if characteristic.uuid.uuidString == "97580003-DDF1-48BE-B73E-182664615D8E" {
                            preferredWritableCharacteristic = characteristic
                        }
                    }
                    if characteristic.properties.contains(.read) {
                        readableCharacteristics.append(characteristic)
                        peripheral.readValue(for: characteristic)
                    }
                }
            }
        }
        
        // Start reading initial data
        readVictronRegisters()
        startHexPolling(for: peripheral)
    }
    
    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else {
            logger.error("Read/update error characteristic=\(characteristic.uuid.uuidString, privacy: .public): \(error?.localizedDescription ?? "unknown", privacy: .public)")
            return
        }

        hasReceivedAnyPayloadSinceConnect = true
        noDataTimeoutTask?.cancel()
        noDataTimeoutTask = nil

        self.payloadPreviewCount += 1
        if self.payloadPreviewCount <= 8 || self.payloadPreviewCount % 50 == 0 {
            let preview = self.payloadPreview(for: data)
            let hex = self.hexPreview(for: data)
            logger.debug("Payload #\(self.payloadPreviewCount) char=\(characteristic.uuid.uuidString, privacy: .public) bytes=\(data.count) ascii=\(preview, privacy: .public) hex=\(hex, privacy: .public)")
        }
        
        // Parse incoming Victron telemetry data
        if let snapshot = parseVictronData(data, characteristic: characteristic) {
            hasReceivedTelemetrySinceConnect = true
            self.parseMissCount = 0
            logger.notice("Telemetry parsed solarW=\(Int(snapshot.solarPower)) battV=\(String(format: "%.2f", snapshot.batteryVoltage), privacy: .public) loadA=\(String(format: "%.2f", snapshot.loadCurrent), privacy: .public)")
            continuation?.yield(snapshot)
        } else {
            self.parseMissCount += 1
            if self.parseMissCount <= 6 || self.parseMissCount % 25 == 0 {
                logger.debug("Payload parse miss count=\(self.parseMissCount)")
            }
        }
    }
    
    // MARK: - Private Helpers
    
    /// Simulate register read request for Victron MPPT.
    /// In production, this would construct proper VE.Direct protocol frames.
    private func readVictronRegisters() {
        // This is a placeholder for proper VE.Direct frame construction
        // In a real implementation, this would build register read requests
        // and send them via rxCharacteristic
    }
    
    /// Parse Victron VE.Direct BLE frame into TelemetrySnapshot.
    private func parseVictronData(_ data: Data, characteristic: CBCharacteristic) -> TelemetrySnapshot? {
        if let hexSnapshot = parseHexVictronData(data) {
            return hexSnapshot
        }

        if let binarySnapshot = parseObservedBinaryPayload(data, characteristic: characteristic) {
            return binarySnapshot
        }

        // Try to parse as Victron register frame
        if let registers = VictronRegisterParser.parseFrame(data) {
            return VictronRegisterParser.buildBinarySnapshot(registers: registers)
        }
        
        // Fall back to parsing as text frame
        let rawText = String(data: data, encoding: .utf8) ?? sanitizedASCIIString(from: data)
        if !rawText.isEmpty {
            textBuffer.append(rawText)
            if textBuffer.count > 4096 {
                textBuffer.removeFirst(textBuffer.count - 4096)
            }

            emitHistoryPayloadIfAvailable(from: rawText)

            if let registers = VictronRegisterParser.parseTextFrame(rawText) {
                return VictronRegisterParser.buildTextSnapshot(registers: registers)
            }

            let parts = textBuffer.components(separatedBy: .newlines)
            if parts.count > 1 {
                textBuffer = parts.last ?? ""
                let completeBlock = parts.dropLast().joined(separator: "\n")
                emitHistoryPayloadIfAvailable(from: completeBlock)
                if let registers = VictronRegisterParser.parseTextFrame(completeBlock) {
                    return VictronRegisterParser.buildTextSnapshot(registers: registers)
                }
            }

            if let registers = VictronRegisterParser.parseLooseTextFrame(rawText) {
                return VictronRegisterParser.buildTextSnapshot(registers: registers)
            }

            // Some VE.Direct payloads terminate with "Checksum". Parse eagerly when detected.
            if textBuffer.localizedCaseInsensitiveContains("CHECKSUM"),
               let registers = VictronRegisterParser.parseTextFrame(textBuffer) {
                textBuffer.removeAll(keepingCapacity: true)
                return VictronRegisterParser.buildTextSnapshot(registers: registers)
            }
        }
        
        return nil
    }

    private func emitHistoryPayloadIfAvailable(from text: String) {
        let payload = parseHistoryPayload(from: text)
        guard !payload.isEmpty else { return }

        let fingerprint = [
            optionalIntString(payload.todayYieldRaw),
            optionalIntString(payload.yesterdayYieldRaw),
            optionalIntString(payload.maxTodayPowerW),
            optionalIntString(payload.maxYesterdayPowerW),
            optionalIntString(payload.daysSinceLastFullCharge)
        ].joined(separator: "|")

        guard fingerprint != lastHistoryFingerprint else { return }
        lastHistoryFingerprint = fingerprint
        onHistoryPayload?(payload)
    }

    private func parseHistoryPayload(from text: String) -> VictronHistoryPayload {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var fields: [String: Int] = [:]
        for line in normalized.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let separatorChars: [Character] = ["\t", "=", ":"]
            guard let separatorIndex = trimmed.firstIndex(where: { separatorChars.contains($0) }) else { continue }
            let keyPart = String(trimmed[..<separatorIndex])
            let valueStart = trimmed.index(after: separatorIndex)
            let valuePart = String(trimmed[valueStart...])
            let parts = [keyPart, valuePart]
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let valueString = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Int(valueString) else { continue }
            fields[key] = value
        }

        // VE.Direct MPPT devices commonly expose history in these text fields:
        // H20=Yield today, H22=Yield yesterday, H21/H23=max power, HSDS=days since last full charge.
        // Some firmware variants shift the field set, therefore we keep H19 as fallback.
        return VictronHistoryPayload(
            todayYieldRaw: fields["H20"] ?? fields["H19"],
            yesterdayYieldRaw: fields["H22"] ?? nil,
            maxTodayPowerW: fields["H21"],
            maxYesterdayPowerW: fields["H23"],
            daysSinceLastFullCharge: fields["HSDS"]
        )
    }

    private func optionalIntString(_ value: Int?) -> String {
        guard let value else { return "-" }
        return String(value)
    }

    private func parseObservedBinaryPayload(_ data: Data, characteristic: CBCharacteristic) -> TelemetrySnapshot? {
        let bytes = Array(data)
        guard bytes.count == 20 else { return nil }
        guard bytes[0] == 0xFF, bytes[1] == 0x18 else { return nil }

        let words = stride(from: 0, to: bytes.count, by: 2).map { index -> UInt16 in
            UInt16(bytes[index]) | (UInt16(bytes[index + 1]) << 8)
        }
        guard words.count >= 7 else { return nil }

        let rawVoltage = Int(words[4])
        let rawCurrent = Int(words[6])
        let rawState = Int(words[3])

        let batteryVoltage: Double
        if (90...180).contains(rawVoltage) {
            batteryVoltage = Double(rawVoltage) / 10.0
        } else if (900...1800).contains(rawVoltage) {
            batteryVoltage = Double(rawVoltage) / 100.0
        } else if (9000...18000).contains(rawVoltage) {
            batteryVoltage = Double(rawVoltage) / 1000.0
        } else {
            return nil
        }

        let batteryCurrent: Double
        if (0...5000).contains(rawCurrent) {
            batteryCurrent = Double(rawCurrent) / 10.0
        } else {
            batteryCurrent = 0
        }

        let estimatedSoc = max(0, min(100, ((batteryVoltage - 11.8) / 2.6) * 100))
        let chargeState = mapHexChargeState(rawState)
        let solarPower = max(0, batteryVoltage * max(0, batteryCurrent))

        logger.debug("Binary fallback parsed from char=\(characteristic.uuid.uuidString, privacy: .public) rawV=\(rawVoltage) rawI=\(rawCurrent) state=\(rawState)")

        return TelemetrySnapshot(
            id: UUID(),
            timestamp: .now,
            solarPower: solarPower,
            solarVoltage: batteryVoltage,
            solarCurrent: max(0, batteryCurrent),
            batteryVoltage: batteryVoltage,
            batteryCurrent: batteryCurrent,
            loadCurrent: max(0, batteryCurrent * 0.2),
            chargeState: chargeState,
            modeledSOC: estimatedSoc,
            socConfidence: 0.35,
            driveMode: false,
            primarySource: .solar
        )
    }

    private func parseHexVictronData(_ data: Data) -> TelemetrySnapshot? {
        guard var text = String(data: data, encoding: .ascii) else {
            return nil
        }

        // Normalize and append to stream buffer.
        text = text.replacingOccurrences(of: "\r", with: "")
        hexBuffer.append(text)
        if hexBuffer.count > 8192 {
            hexBuffer.removeFirst(hexBuffer.count - 8192)
        }

        var snapshot: TelemetrySnapshot?
        let frames = hexBuffer.split(separator: "\n", omittingEmptySubsequences: false)
        guard frames.count > 1 else {
            return nil
        }

        hexBuffer = String(frames.last ?? "")
        for raw in frames.dropLast() {
            let frame = String(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            guard frame.hasPrefix(":"), frame.count >= 4 else { continue }
            if let parsed = decodeHexFrame(frame), let item = applyHexFrame(parsed) {
                snapshot = item
            }
        }
        return snapshot
    }

    private func decodeHexFrame(_ frame: String) -> (code: UInt8, bytes: [UInt8])? {
        let payload = String(frame.dropFirst())
        guard let code = UInt8(String(payload.prefix(1)), radix: 16) else { return nil }
        let hexPairs = String(payload.dropFirst())
        guard hexPairs.count % 2 == 0 else { return nil }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexPairs.count / 2)

        var idx = hexPairs.startIndex
        while idx < hexPairs.endIndex {
            let next = hexPairs.index(idx, offsetBy: 2)
            guard let byte = UInt8(hexPairs[idx..<next], radix: 16) else { return nil }
            bytes.append(byte)
            idx = next
        }

        guard let check = bytes.last else { return nil }
        let dataBytes = bytes.dropLast()
        let sum = Int(code) + dataBytes.reduce(0, { $0 + Int($1) }) + Int(check)
        guard (sum & 0xFF) == 0x55 else {
            return nil
        }
        return (code, bytes)
    }

    private func applyHexFrame(_ frame: (code: UInt8, bytes: [UInt8])) -> TelemetrySnapshot? {
        // Get response (7) or async (A) have register id + flags + value + check.
        guard frame.code == 0x07 || frame.code == 0x0A else { return nil }
        guard frame.bytes.count >= 5 else { return nil }

        let body = Array(frame.bytes.dropLast())
        guard body.count >= 4 else { return nil }
        let registerId = UInt16(body[0]) | (UInt16(body[1]) << 8)
        let valueBytes = Array(body.dropFirst(3))

        guard let value = littleEndianUnsigned(from: valueBytes) else { return nil }

        switch registerId {
        case 0xEDD5: // charger voltage (0.01V)
            latestHexBatteryVoltage = Double(value) / 100.0
        case 0xEDD7: // charger current (0.1A)
            latestHexBatteryCurrent = Double(value) / 10.0
        case 0xEDDB: // charger internal temperature (0.01C)
            latestHexTemperature = Double(Int16(bitPattern: UInt16(truncatingIfNeeded: value))) / 100.0
        case 0x0201: // device state
            latestHexChargeState = Int(value)
        case 0x0100: // product id
            logger.notice("HEX product id response value=0x\(String(value, radix: 16), privacy: .public)")
        default:
            break
        }

        guard latestHexBatteryVoltage > 0 else { return nil }
        let solarPower = max(0, latestHexBatteryVoltage * max(0, latestHexBatteryCurrent))
        let chargeState = mapHexChargeState(latestHexChargeState)

        return TelemetrySnapshot(
            id: UUID(),
            timestamp: .now,
            solarPower: solarPower,
            solarVoltage: latestHexBatteryVoltage,
            solarCurrent: max(0, latestHexBatteryCurrent),
            batteryVoltage: latestHexBatteryVoltage,
            batteryCurrent: latestHexBatteryCurrent,
            loadCurrent: max(0, latestHexBatteryCurrent * 0.2),
            chargeState: chargeState,
            modeledSOC: latestHexModeledSoc,
            socConfidence: 0.55,
            driveMode: false,
            primarySource: .solar
        )
    }

    private func littleEndianUnsigned(from bytes: [UInt8]) -> UInt32? {
        guard !bytes.isEmpty, bytes.count <= 4 else { return nil }
        var value: UInt32 = 0
        for (index, byte) in bytes.enumerated() {
            value |= UInt32(byte) << (UInt32(index) * 8)
        }
        return value
    }

    private func mapHexChargeState(_ state: Int) -> ChargeState {
        switch state {
        case 0: return .off
        case 3: return .bulk
        case 4: return .absorption
        case 5: return .float
        case 6: return .storage
        default: return .float
        }
    }

    private func sanitizedASCIIString(from data: Data) -> String {
        let mapped = data.map { byte -> Character in
            switch byte {
            case 9, 10, 13:
                return Character(UnicodeScalar(byte))
            case 32...126:
                return Character(UnicodeScalar(byte))
            default:
                return " "
            }
        }
        return String(mapped)
    }

    private func startScan(on central: CBCentralManager) {
        logger.notice("Start scanning for Victron peripherals")
        onConnectionStateChange?(.scanning)
        // Scan without UUID filter so Victron devices are discoverable regardless of firmware version.
        // Some MPPT models don't advertise the custom service UUID until connected.
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimeoutTask?.cancel()
        scanTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self else { return }
            if self.connectedPeripheral == nil {
                self.logger.warning("Scan timeout reached, restarting scan")
                central.stopScan()
                self.startScan(on: central)
            }
        }
    }

    private func retryOrRescan(on central: CBCentralManager) {
        self.reconnectAttempts += 1
        logger.notice("Retry/rescan attempt=\(self.reconnectAttempts)")
        guard self.reconnectAttempts <= maxReconnectAttempts else {
            self.reconnectAttempts = 0
            startScan(on: central)
            return
        }

        if let peripheral = connectedPeripheral {
            central.connect(peripheral, options: nil)
        } else {
            startScan(on: central)
        }
    }

    private func scheduleNoDataTimeout(for peripheral: CBPeripheral, on central: CBCentralManager) {
        noDataTimeoutTask?.cancel()
        noDataTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard let self else { return }
            guard self.connectedPeripheral?.identifier == peripheral.identifier else { return }
            guard !self.hasReceivedAnyPayloadSinceConnect else { return }
            self.logger.warning("No raw payloads within timeout; forcing reconnect")
            central.cancelPeripheralConnection(peripheral)
        }
    }

    private func startReadPolling(for peripheral: CBPeripheral) {
        readPollTask?.cancel()
        readPollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard self.connectedPeripheral?.identifier == peripheral.identifier else { continue }
                if !self.readableCharacteristics.isEmpty {
                    self.logger.debug("Polling readable characteristics count=\(self.readableCharacteristics.count)")
                }
                for characteristic in self.readableCharacteristics {
                    peripheral.readValue(for: characteristic)
                }
            }
        }
    }

    private func startHexPolling(for peripheral: CBPeripheral) {
        hexPollTask?.cancel()

        // Prime with discovery-style requests.
        sendHexCommand(command: 0x01, payload: [], to: peripheral) // ping
        sendHexCommand(command: 0x04, payload: [], to: peripheral) // product id

        hexPollTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard self.connectedPeripheral?.identifier == peripheral.identifier else { continue }

                // Poll key runtime registers from BlueSolar HEX protocol.
                self.sendHexGet(register: 0xEDD5, to: peripheral) // charger voltage
                self.sendHexGet(register: 0xEDD7, to: peripheral) // charger current
                self.sendHexGet(register: 0x0201, to: peripheral) // device state
            }
        }
    }

    private func sendHexGet(register: UInt16, to peripheral: CBPeripheral) {
        let payload: [UInt8] = [UInt8(register & 0xFF), UInt8((register >> 8) & 0xFF), 0x00]
        sendHexCommand(command: 0x07, payload: payload, to: peripheral)
    }

    private func sendHexCommand(command: UInt8, payload: [UInt8], to peripheral: CBPeripheral) {
        guard !writableCharacteristics.isEmpty else { return }

        let sum = (Int(command) + payload.reduce(0, { $0 + Int($1) })) & 0xFF
        let check = UInt8((0x55 - sum) & 0xFF)

        var frame = ":\(String(command, radix: 16).uppercased())"
        for byte in payload + [check] {
            frame += String(format: "%02X", byte)
        }
        frame += "\n"

        guard let data = frame.data(using: .ascii) else { return }

        let destinations: [CBCharacteristic]
        if let preferredWritableCharacteristic {
            destinations = [preferredWritableCharacteristic]
        } else {
            destinations = [writableCharacteristics[0]]
        }

        for characteristic in destinations {
            let type: CBCharacteristicWriteType = characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            peripheral.writeValue(data, for: characteristic, type: type)
        }
        logger.debug("Sent HEX frame=\(frame, privacy: .public)")
    }

    private func payloadPreview(for data: Data) -> String {
        let ascii = sanitizedASCIIString(from: data)
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let asciiPreview = String(ascii.prefix(120))
        return asciiPreview.isEmpty ? "<non-ascii payload>" : asciiPreview
    }

    private func hexPreview(for data: Data) -> String {
        data.prefix(24).map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func describe(state: CBManagerState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "other"
        }
    }

    private var latestHexBatteryVoltage: Double {
        get { _latestHexBatteryVoltage }
        set { _latestHexBatteryVoltage = newValue }
    }

    private var latestHexBatteryCurrent: Double {
        get { _latestHexBatteryCurrent }
        set { _latestHexBatteryCurrent = newValue }
    }

    private var latestHexTemperature: Double {
        get { _latestHexTemperature }
        set { _latestHexTemperature = newValue }
    }

    private var latestHexChargeState: Int {
        get { _latestHexChargeState }
        set { _latestHexChargeState = newValue }
    }

    private var latestHexModeledSoc: Double {
        get { _latestHexModeledSoc }
        set { _latestHexModeledSoc = newValue }
    }

    private static var _hexStorage = HexStorage()
    private var _latestHexBatteryVoltage: Double {
        get { Self._hexStorage.latestHexBatteryVoltage }
        set { Self._hexStorage.latestHexBatteryVoltage = newValue }
    }
    private var _latestHexBatteryCurrent: Double {
        get { Self._hexStorage.latestHexBatteryCurrent }
        set { Self._hexStorage.latestHexBatteryCurrent = newValue }
    }
    private var _latestHexTemperature: Double {
        get { Self._hexStorage.latestHexTemperature }
        set { Self._hexStorage.latestHexTemperature = newValue }
    }
    private var _latestHexChargeState: Int {
        get { Self._hexStorage.latestHexChargeState }
        set { Self._hexStorage.latestHexChargeState = newValue }
    }
    private var _latestHexModeledSoc: Double {
        get { Self._hexStorage.latestHexModeledSoc }
        set { Self._hexStorage.latestHexModeledSoc = newValue }
    }

    private struct HexStorage {
        var latestHexBatteryVoltage: Double = 0
        var latestHexBatteryCurrent: Double = 0
        var latestHexTemperature: Double = 0
        var latestHexChargeState: Int = 0
        var latestHexModeledSoc: Double = 0
    }
}
