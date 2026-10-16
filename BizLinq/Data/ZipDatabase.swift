import CoreLocation
import Foundation

struct ZipLocation {
    let zip: String
    let city: String
    let state: String
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var placeLabel: String {
        "\(city), \(state) \(zip)"
    }
}

/// Built-in ZIP lookup so the prototype works offline for major US metros.
/// Any other valid 5-digit ZIP is resolved with CLGeocoder at runtime.
enum ZipDatabase {
    static let all: [String: ZipLocation] = [
        "10001": ZipLocation(zip: "10001", city: "New York", state: "NY", latitude: 40.7506, longitude: -73.9972),
        "11215": ZipLocation(zip: "11215", city: "Brooklyn", state: "NY", latitude: 40.6782, longitude: -73.9857),
        "02108": ZipLocation(zip: "02108", city: "Boston", state: "MA", latitude: 42.3588, longitude: -71.0636),
        "02903": ZipLocation(zip: "02903", city: "Providence", state: "RI", latitude: 41.8240, longitude: -71.4128),
        "06103": ZipLocation(zip: "06103", city: "Hartford", state: "CT", latitude: 41.7658, longitude: -72.6734),
        "19103": ZipLocation(zip: "19103", city: "Philadelphia", state: "PA", latitude: 39.9526, longitude: -75.1657),
        "20001": ZipLocation(zip: "20001", city: "Washington", state: "DC", latitude: 38.9101, longitude: -77.0171),
        "21201": ZipLocation(zip: "21201", city: "Baltimore", state: "MD", latitude: 39.2904, longitude: -76.6167),
        "23219": ZipLocation(zip: "23219", city: "Richmond", state: "VA", latitude: 37.5407, longitude: -77.4360),
        "27601": ZipLocation(zip: "27601", city: "Raleigh", state: "NC", latitude: 35.7796, longitude: -78.6382),
        "28202": ZipLocation(zip: "28202", city: "Charlotte", state: "NC", latitude: 35.2271, longitude: -80.8431),
        "30301": ZipLocation(zip: "30301", city: "Atlanta", state: "GA", latitude: 33.7490, longitude: -84.3880),
        "32801": ZipLocation(zip: "32801", city: "Orlando", state: "FL", latitude: 28.5421, longitude: -81.3790),
        "32825": ZipLocation(zip: "32825", city: "Orlando", state: "FL", latitude: 28.5469, longitude: -81.2571),
        "32827": ZipLocation(zip: "32827", city: "Orlando", state: "FL", latitude: 28.4317, longitude: -81.3430),
        "32828": ZipLocation(zip: "32828", city: "Orlando", state: "FL", latitude: 28.5523, longitude: -81.1795),
        "32829": ZipLocation(zip: "32829", city: "Orlando", state: "FL", latitude: 28.4671, longitude: -81.2417),
        "32832": ZipLocation(zip: "32832", city: "Orlando", state: "FL", latitude: 28.3774, longitude: -81.1888),
        "32833": ZipLocation(zip: "32833", city: "Orlando", state: "FL", latitude: 28.5088, longitude: -81.0703),
        "33101": ZipLocation(zip: "33101", city: "Miami", state: "FL", latitude: 25.7753, longitude: -80.2102),
        "33139": ZipLocation(zip: "33139", city: "Miami Beach", state: "FL", latitude: 25.7825, longitude: -80.1301),
        "33602": ZipLocation(zip: "33602", city: "Tampa", state: "FL", latitude: 27.9506, longitude: -82.4572),
        "37203": ZipLocation(zip: "37203", city: "Nashville", state: "TN", latitude: 36.1508, longitude: -86.7844),
        "38103": ZipLocation(zip: "38103", city: "Memphis", state: "TN", latitude: 35.1431, longitude: -90.0489),
        "40202": ZipLocation(zip: "40202", city: "Louisville", state: "KY", latitude: 38.2530, longitude: -85.7590),
        "43215": ZipLocation(zip: "43215", city: "Columbus", state: "OH", latitude: 39.9655, longitude: -83.0007),
        "44113": ZipLocation(zip: "44113", city: "Cleveland", state: "OH", latitude: 41.4852, longitude: -81.6876),
        "45202": ZipLocation(zip: "45202", city: "Cincinnati", state: "OH", latitude: 39.1031, longitude: -84.5120),
        "46204": ZipLocation(zip: "46204", city: "Indianapolis", state: "IN", latitude: 39.7684, longitude: -86.1581),
        "48226": ZipLocation(zip: "48226", city: "Detroit", state: "MI", latitude: 42.3314, longitude: -83.0458),
        "50309": ZipLocation(zip: "50309", city: "Des Moines", state: "IA", latitude: 41.5868, longitude: -93.6250),
        "53203": ZipLocation(zip: "53203", city: "Milwaukee", state: "WI", latitude: 43.0389, longitude: -87.9065),
        "55101": ZipLocation(zip: "55101", city: "Saint Paul", state: "MN", latitude: 44.9537, longitude: -93.0900),
        "55401": ZipLocation(zip: "55401", city: "Minneapolis", state: "MN", latitude: 44.9797, longitude: -93.2662),
        "60601": ZipLocation(zip: "60601", city: "Chicago", state: "IL", latitude: 41.8864, longitude: -87.6186),
        "60607": ZipLocation(zip: "60607", city: "Chicago", state: "IL", latitude: 41.8781, longitude: -87.6513),
        "63103": ZipLocation(zip: "63103", city: "St. Louis", state: "MO", latitude: 38.6460, longitude: -90.2610),
        "64106": ZipLocation(zip: "64106", city: "Kansas City", state: "MO", latitude: 39.0997, longitude: -94.5786),
        "68102": ZipLocation(zip: "68102", city: "Omaha", state: "NE", latitude: 41.2565, longitude: -95.9345),
        "72201": ZipLocation(zip: "72201", city: "Little Rock", state: "AR", latitude: 34.7486, longitude: -92.2901),
        "73102": ZipLocation(zip: "73102", city: "Oklahoma City", state: "OK", latitude: 35.4676, longitude: -97.5164),
        "74103": ZipLocation(zip: "74103", city: "Tulsa", state: "OK", latitude: 36.1540, longitude: -95.9928),
        "75201": ZipLocation(zip: "75201", city: "Dallas", state: "TX", latitude: 32.7877, longitude: -96.7989),
        "77002": ZipLocation(zip: "77002", city: "Houston", state: "TX", latitude: 29.7558, longitude: -95.3620),
        "78701": ZipLocation(zip: "78701", city: "Austin", state: "TX", latitude: 30.2711, longitude: -97.7437),
        "78704": ZipLocation(zip: "78704", city: "Austin", state: "TX", latitude: 30.2461, longitude: -97.7490),
        "80202": ZipLocation(zip: "80202", city: "Denver", state: "CO", latitude: 39.7525, longitude: -104.9995),
        "84101": ZipLocation(zip: "84101", city: "Salt Lake City", state: "UT", latitude: 40.7608, longitude: -111.8910),
        "85003": ZipLocation(zip: "85003", city: "Phoenix", state: "AZ", latitude: 33.4486, longitude: -112.0773),
        "87102": ZipLocation(zip: "87102", city: "Albuquerque", state: "NM", latitude: 35.0853, longitude: -106.6504),
        "89101": ZipLocation(zip: "89101", city: "Las Vegas", state: "NV", latitude: 36.1700, longitude: -115.1398),
        "90012": ZipLocation(zip: "90012", city: "Los Angeles", state: "CA", latitude: 34.0614, longitude: -118.2385),
        "90028": ZipLocation(zip: "90028", city: "Hollywood", state: "CA", latitude: 34.1002, longitude: -118.3267),
        "90210": ZipLocation(zip: "90210", city: "Beverly Hills", state: "CA", latitude: 34.0901, longitude: -118.4065),
        "92101": ZipLocation(zip: "92101", city: "San Diego", state: "CA", latitude: 32.7157, longitude: -117.1611),
        "94103": ZipLocation(zip: "94103", city: "San Francisco", state: "CA", latitude: 37.7749, longitude: -122.4194),
        "95113": ZipLocation(zip: "95113", city: "San Jose", state: "CA", latitude: 37.3352, longitude: -121.8947),
        "95814": ZipLocation(zip: "95814", city: "Sacramento", state: "CA", latitude: 38.5816, longitude: -121.4944),
        "97209": ZipLocation(zip: "97209", city: "Portland", state: "OR", latitude: 45.5271, longitude: -122.6858),
        "98101": ZipLocation(zip: "98101", city: "Seattle", state: "WA", latitude: 47.6101, longitude: -122.3331),
        "96813": ZipLocation(zip: "96813", city: "Honolulu", state: "HI", latitude: 21.3099, longitude: -157.8581),
        "99501": ZipLocation(zip: "99501", city: "Anchorage", state: "AK", latitude: 61.2181, longitude: -149.9003),
    ]

    static func lookup(_ zip: String) -> ZipLocation? {
        let digits = zip.filter { $0.isNumber }
        guard digits.count >= 5 else { return nil }
        return all[String(digits.prefix(5))]
    }

    static func isValidFormat(_ zip: String) -> Bool {
        let digits = zip.filter { $0.isNumber }
        return digits.count == 5
    }
}
