import Foundation
import CoreLocation

struct ForecastHourlyPoint: Sendable {
    let date: Date
    let cloudCover: Double
    let shortwaveRadiation: Double
    let directRadiation: Double
    let diffuseRadiation: Double
}

struct ForecastEnvironmentContext: Sendable {
    let latitude: Double
    let longitude: Double
    let altitude: Double
    let hourly: [ForecastHourlyPoint]
    let horizonProfile: HorizonProfile?
    let updatedAt: Date

    var hasWeather: Bool { !hourly.isEmpty }
    var hasTerrain: Bool { horizonProfile != nil }
}

struct HorizonProfile: Sendable {
    let sectorStepDegrees: Double
    let obstructionBySectorDegrees: [Double]

    func obstructionAngle(forAzimuth azimuthDegrees: Double) -> Double {
        guard !obstructionBySectorDegrees.isEmpty else { return 0 }
        let normalized = (azimuthDegrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let sector = Int((normalized / sectorStepDegrees).rounded()) % obstructionBySectorDegrees.count
        return obstructionBySectorDegrees[sector]
    }
}

final class ForecastEnvironmentService: NSObject {
    var onUpdate: ((ForecastEnvironmentContext) -> Void)?

    private let locationManager = CLLocationManager()
    private var currentTask: Task<Void, Never>?
    private var lastWeatherFetch: Date?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 250
    }

    func start() {
        switch locationManager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.startUpdatingLocation()
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        currentTask?.cancel()
        currentTask = nil
    }

    private func shouldFetchWeather(now: Date) -> Bool {
        guard let lastWeatherFetch else { return true }
        return now.timeIntervalSince(lastWeatherFetch) > 900
    }

    private func updateContext(for location: CLLocation) {
        let now = Date()
        guard shouldFetchWeather(now: now) else { return }
        lastWeatherFetch = now

        currentTask?.cancel()
        currentTask = Task { [weak self] in
            guard let self else { return }
            async let hourlyTask = self.fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            async let horizonTask = self.fetchTerrainHorizon(location: location)

            let hourly = await hourlyTask
            let horizonProfile = await horizonTask

            let context = ForecastEnvironmentContext(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                hourly: hourly,
                horizonProfile: horizonProfile,
                updatedAt: .now
            )

            await MainActor.run {
                self.onUpdate?(context)
            }
        }
    }

    private func fetchWeather(latitude: Double, longitude: Double) async -> [ForecastHourlyPoint] {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "hourly", value: "cloud_cover,shortwave_radiation,direct_radiation,diffuse_radiation")
        ]

        guard let url = components?.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            return response.hourly.toPoints()
        } catch {
            return []
        }
    }

    private func fetchTerrainHorizon(location: CLLocation) async -> HorizonProfile? {
        let sectorCount = 16
        let sectorStep = 360.0 / Double(sectorCount)
        let distances: [Double] = [500, 1000, 2000, 3500]

        var samplePoints: [(lat: Double, lon: Double, sector: Int, distance: Double)] = []
        samplePoints.reserveCapacity(sectorCount * distances.count)

        for sector in 0..<sectorCount {
            let bearing = Double(sector) * sectorStep
            for distance in distances {
                let coordinate = destinationCoordinate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    bearingDegrees: bearing,
                    distanceMeters: distance
                )
                samplePoints.append((coordinate.latitude, coordinate.longitude, sector, distance))
            }
        }

        let latList = samplePoints.map { String(format: "%.6f", $0.lat) }.joined(separator: ",")
        let lonList = samplePoints.map { String(format: "%.6f", $0.lon) }.joined(separator: ",")

        var components = URLComponents(string: "https://api.open-meteo.com/v1/elevation")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: latList),
            URLQueryItem(name: "longitude", value: lonList)
        ]

        guard let url = components?.url else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(OpenMeteoElevationResponse.self, from: data)
            guard response.elevation.count == samplePoints.count else { return nil }

            var obstructionAngles = Array(repeating: 0.0, count: sectorCount)
            let baseAltitude = location.altitude

            for index in response.elevation.indices {
                let sample = samplePoints[index]
                let elevationDelta = max(0, response.elevation[index] - baseAltitude)
                let angleDegrees = atan2(elevationDelta, sample.distance) * 180 / .pi
                obstructionAngles[sample.sector] = max(obstructionAngles[sample.sector], angleDegrees)
            }

            return HorizonProfile(sectorStepDegrees: sectorStep, obstructionBySectorDegrees: obstructionAngles)
        } catch {
            return nil
        }
    }

    private func destinationCoordinate(latitude: Double, longitude: Double, bearingDegrees: Double, distanceMeters: Double) -> CLLocationCoordinate2D {
        let earthRadius = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let angularDistance = distanceMeters / earthRadius

        let lat2 = asin(sin(lat1) * cos(angularDistance) + cos(lat1) * sin(angularDistance) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angularDistance) * cos(lat1),
            cos(angularDistance) - sin(lat1) * sin(lat2)
        )

        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}

extension ForecastEnvironmentService: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .notDetermined:
            break
        default:
            manager.stopUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        updateContext(for: latest)
    }
}

struct SolarGeometry {
    struct SolarPosition: Sendable {
        let elevationDegrees: Double
        let azimuthDegrees: Double

        var elevationFactor: Double {
            max(0, sin(elevationDegrees * .pi / 180))
        }
    }

    static func elevationFactor(date: Date, latitude: Double, longitude: Double) -> Double {
        position(date: date, latitude: latitude, longitude: longitude).elevationFactor
    }

    static func position(date: Date, latitude: Double, longitude: Double) -> SolarPosition {
        let dayOfYear = Calendar(identifier: .gregorian).ordinality(of: .day, in: .year, for: date) ?? 1
        let gamma = 2 * Double.pi / 365 * (Double(dayOfYear) - 1)

        let declination = 0.006918
            - 0.399912 * cos(gamma)
            + 0.070257 * sin(gamma)
            - 0.006758 * cos(2 * gamma)
            + 0.000907 * sin(2 * gamma)
            - 0.002697 * cos(3 * gamma)
            + 0.00148 * sin(3 * gamma)

        let equationOfTime = 229.18 * (0.000075
            + 0.001868 * cos(gamma)
            - 0.032077 * sin(gamma)
            - 0.014615 * cos(2 * gamma)
            - 0.040849 * sin(2 * gamma))

        let timezoneOffsetHours = Double(TimeZone.current.secondsFromGMT(for: date)) / 3600
        let minutes = Double(Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date))
        let trueSolarMinutes = minutes + equationOfTime + 4 * longitude - 60 * timezoneOffsetHours
        let hourAngle = (trueSolarMinutes / 4 - 180) * .pi / 180

        let latRad = latitude * .pi / 180
        let sinElevation = sin(latRad) * sin(declination) + cos(latRad) * cos(declination) * cos(hourAngle)
        let elevation = asin(max(-1, min(1, sinElevation)))

        let azimuthFromSouth = atan2(
            sin(hourAngle),
            cos(hourAngle) * sin(latRad) - tan(declination) * cos(latRad)
        )
        let azimuthDegrees = (azimuthFromSouth * 180 / .pi + 180).truncatingRemainder(dividingBy: 360)

        return SolarPosition(elevationDegrees: elevation * 180 / .pi, azimuthDegrees: azimuthDegrees)
    }
}

private struct OpenMeteoElevationResponse: Decodable {
    let elevation: [Double]
}

private struct OpenMeteoResponse: Decodable {
    let hourly: Hourly

    struct Hourly: Decodable {
        let time: [String]
        let cloud_cover: [Double]
        let shortwave_radiation: [Double]
        let direct_radiation: [Double]
        let diffuse_radiation: [Double]

        func toPoints() -> [ForecastHourlyPoint] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            formatter.timeZone = .current

            let count = min(
                time.count,
                cloud_cover.count,
                shortwave_radiation.count,
                direct_radiation.count,
                diffuse_radiation.count
            )

            return (0..<count).compactMap { index in
                guard let date = formatter.date(from: time[index]) else { return nil }
                return ForecastHourlyPoint(
                    date: date,
                    cloudCover: max(0, min(1, cloud_cover[index] / 100.0)),
                    shortwaveRadiation: max(0, shortwave_radiation[index]),
                    directRadiation: max(0, direct_radiation[index]),
                    diffuseRadiation: max(0, diffuse_radiation[index])
                )
            }
        }
    }
}
