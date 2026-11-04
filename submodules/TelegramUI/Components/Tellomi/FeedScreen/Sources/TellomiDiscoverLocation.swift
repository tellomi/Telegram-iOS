import CoreLocation
import Foundation
import Geocoding
import SwiftSignalKit
import TellomiDiscover

let tellomiDiscoverCityDefaultsKey = "tellomi.discover.city"

func tellomiDiscoverStoredCity() -> String? {
    guard let stored = UserDefaults.standard.string(forKey: tellomiDiscoverCityDefaultsKey) else {
        return nil
    }
    return tellomiDiscoverNormalizedCity(stored)
}

func tellomiDiscoverStoreCity(_ city: String?) {
    if let city = city.flatMap(tellomiDiscoverNormalizedCity) {
        UserDefaults.standard.set(city, forKey: tellomiDiscoverCityDefaultsKey)
    } else {
        UserDefaults.standard.removeObject(forKey: tellomiDiscoverCityDefaultsKey)
    }
}

/// One-shot city lookup. `DeviceLocationManager` asks for Always and full accuracy;
/// a city only needs When In Use and kilometer accuracy, then the coordinate is dropped.
final class TellomiDiscoverCityLocator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var askedForAuthorization = false
    private var askedForFix = false
    private var finished = false
    private var geocodeDisposable: Disposable?
    var onCity: ((String?) -> Void)?
    var onDenied: (() -> Void)?

    func start() {
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyKilometer
        self.consumeAuthorization()
    }

    func stop() {
        self.finished = true
        self.geocodeDisposable?.dispose()
        self.manager.stopUpdatingLocation()
    }

    private func consumeAuthorization() {
        guard !self.finished else {
            return
        }
        switch self.manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            guard !self.askedForFix else {
                return
            }
            self.askedForFix = true
            self.manager.requestLocation()
        case .notDetermined:
            guard !self.askedForAuthorization else {
                return
            }
            self.askedForAuthorization = true
            self.manager.requestWhenInUseAuthorization()
        default:
            self.finishDenied()
        }
    }

    private func finishDenied() {
        guard !self.finished else {
            return
        }
        self.finished = true
        self.onDenied?()
    }

    private func finish(city: String?) {
        guard !self.finished else {
            return
        }
        self.finished = true
        self.manager.stopUpdatingLocation()
        self.onCity?(city)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let _ = manager
        self.consumeAuthorization()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let _ = manager
        guard let location = locations.first else {
            self.finish(city: nil)
            return
        }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        self.geocodeDisposable?.dispose()
        self.geocodeDisposable = reverseGeocodeLocation(latitude: latitude, longitude: longitude).start(next: { [weak self] placemark in
            let city = tellomiDiscoverCity(street: placemark?.street, city: placemark?.city, state: placemark?.state)
            Queue.mainQueue().async {
                self?.finish(city: city)
            }
        })
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let _ = manager
        if (error as NSError).code == CLError.denied.rawValue {
            self.finishDenied()
        } else {
            self.finish(city: nil)
        }
    }
}
