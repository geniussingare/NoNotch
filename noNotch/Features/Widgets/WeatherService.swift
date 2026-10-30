import CoreLocation
import Foundation
import Observation

/// Current conditions from Open-Meteo (free, no API key) for the user's location.
/// Refreshes every 30 minutes; one coarse location fix per refresh.
@MainActor
@Observable
final class WeatherService: NSObject {
    struct Conditions: Equatable {
        let temperature: Double
        let high: Double
        let low: Double
        let code: Int
        let isDay: Bool

        var symbol: String { WeatherService.symbol(code: code, isDay: isDay) }
        var summary: String { WeatherService.summary(code: code) }
    }

    private(set) var current: Conditions?

    @ObservationIgnored private let location = CLLocationManager()
    @ObservationIgnored private var timer: Timer?

    var usesFahrenheit: Bool { Locale.current.measurementSystem == .us }

    func start() {
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyKilometer
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 120
    }

    func refresh() {
        guard [.authorizedAlways, .authorized].contains(location.authorizationStatus) else { return }
        location.requestLocation()
    }

    func format(_ celsius: Double) -> String {
        let value = usesFahrenheit ? celsius * 9 / 5 + 32 : celsius
        return "\(Int(value.rounded()))°"
    }

    private func fetch(_ coordinate: CLLocationCoordinate2D) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.3f", coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.3f", coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        struct Response: Decodable {
            struct Current: Decodable { let temperature_2m: Double; let weather_code: Int; let is_day: Int }
            struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
            let current: Current
            let daily: Daily
        }
        guard let (data, _) = try? await URLSession.shared.data(from: components.url!),
              let response = try? JSONDecoder().decode(Response.self, from: data)
        else { return }
        current = Conditions(
            temperature: response.current.temperature_2m,
            high: response.daily.temperature_2m_max.first ?? response.current.temperature_2m,
            low: response.daily.temperature_2m_min.first ?? response.current.temperature_2m,
            code: response.current.weather_code,
            isDay: response.current.is_day == 1
        )
    }

    // WMO weather interpretation codes → SF Symbols.
    nonisolated static func symbol(code: Int, isDay: Bool) -> String {
        switch code {
        case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    nonisolated static func summary(code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1, 2: "Partly Cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67, 80...82: "Rain"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Thunderstorm"
        default: "—"
        }
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            await self.fetch(location.coordinate)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }
}
