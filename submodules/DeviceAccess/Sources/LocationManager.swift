import Foundation
import CoreLocation

public final class LocationManager: NSObject, CLLocationManagerDelegate {
    public let manager = CLLocationManager()
    var pendingCompletion: ((CLAuthorizationStatus) -> Void, CLAuthorizationStatus)?
    
    public override init() {
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    func requestWhenInUseAuthorization(completion: @escaping (CLAuthorizationStatus) -> Void) {
        let status = self.manager.authorizationStatus
        if status == .notDetermined {
            self.manager.requestWhenInUseAuthorization()
            self.pendingCompletion = (completion, .authorizedWhenInUse)
        } else {
            completion(status)
        }
    }
    
    func requestPreciseLocationIfReduced() {
        if #available(iOS 14.0, *) {
            let status = self.manager.authorizationStatus
            guard status == .authorizedAlways || status == .authorizedWhenInUse else {
                return
            }
            guard self.manager.accuracyAuthorization != .fullAccuracy else {
                return
            }
            self.manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "PreciseLocation") { _ in }
        }
    }

    func requestAlwaysAuthorization(completion: @escaping (CLAuthorizationStatus) -> Void) {
        let status = self.manager.authorizationStatus
        if status == .notDetermined {
            self.manager.requestWhenInUseAuthorization()
            self.pendingCompletion = (completion, .authorizedAlways)
        } else {
            completion(status)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if #available(iOS 14.0, *) {
            if status == .authorizedAlways || status == .authorizedWhenInUse, manager.accuracyAuthorization != .fullAccuracy {
                manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: "PreciseLocation") { _ in }
            }
        }
        if let (pendingCompletion, _) = self.pendingCompletion {
            pendingCompletion(status)
            self.pendingCompletion = nil
        }
    }
}
