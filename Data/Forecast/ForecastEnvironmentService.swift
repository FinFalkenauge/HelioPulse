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
    let updatedAt: Date

    var hasWeather: Bool { !hourly.isEmpty }
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
            let hourly = await self.fetchWeather(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)

            let context = ForecastEnvironmentContext(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.altitude,
                hourly: hourly,
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
    static func elevationFactor(date: Date, latitude: Double, longitude: Double) -> Double {
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
        return max(0, sinElevation)
    }
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
