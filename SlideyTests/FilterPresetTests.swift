import XCTest
@testable import Slidey

final class FilterPresetTests: XCTestCase {

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }

    // MARK: - Encode / decode round-trip

    func testCodableRoundTripPreservesAllFields() throws {
        let start = Date(timeIntervalSince1970: 1_600_000_000)
        let end = Date(timeIntervalSince1970: 1_600_500_000)
        let preset = FilterPreset(
            name: "Beach trip",
            searchText: "sunset",
            startDate: start,
            endDate: end,
            minRating: 3,
            favouritesOnly: true
        )

        let data = try JSONEncoder().encode(preset)
        let decoded = try JSONDecoder().decode(FilterPreset.self, from: data)

        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.name, "Beach trip")
        XCTAssertEqual(decoded.searchText, "sunset")
        XCTAssertEqual(decoded.startDate, start)
        XCTAssertEqual(decoded.endDate, end)
        XCTAssertEqual(decoded.minRating, 3)
        XCTAssertTrue(decoded.favouritesOnly)
    }

    func testCodableArrayRoundTrip() throws {
        let presets = [
            FilterPreset(name: "One", searchText: "a"),
            FilterPreset(name: "Two", minRating: 5),
            FilterPreset(name: "Three", favouritesOnly: true)
        ]

        let data = try JSONEncoder().encode(presets)
        let decoded = try JSONDecoder().decode([FilterPreset].self, from: data)

        XCTAssertEqual(decoded, presets)
    }

    func testNilDatesMeanAnyDate() throws {
        let preset = FilterPreset(name: "No dates", searchText: "x")
        let decoded = try JSONDecoder().decode(
            FilterPreset.self,
            from: try JSONEncoder().encode(preset)
        )
        XCTAssertNil(decoded.startDate)
        XCTAssertNil(decoded.endDate)
        XCTAssertFalse(decoded.searchCriteria.needsDate)
    }

    // MARK: - isActive

    func testEmptyPresetIsInactive() {
        let preset = FilterPreset(name: "Empty")
        XCTAssertFalse(preset.isActive)
    }

    func testWhitespaceOnlyQueryIsInactive() {
        let preset = FilterPreset(name: "Blank", searchText: "   ")
        XCTAssertFalse(preset.isActive)
    }

    func testSearchTextMakesActive() {
        XCTAssertTrue(FilterPreset(name: "Q", searchText: "cat").isActive)
    }

    func testRatingMakesActive() {
        XCTAssertTrue(FilterPreset(name: "R", minRating: 2).isActive)
    }

    func testFavouritesMakesActive() {
        XCTAssertTrue(FilterPreset(name: "F", favouritesOnly: true).isActive)
    }

    // MARK: - searchCriteria reconstruction (day widening)

    func testSearchCriteriaWidensDatesToWholeDays() {
        let calendar = Calendar.current
        let day = Date(timeIntervalSince1970: 1_600_000_000)
        let preset = FilterPreset(name: "Dates", startDate: day, endDate: day)
        let criteria = preset.searchCriteria

        XCTAssertEqual(criteria.startDate, calendar.startOfDay(for: day))
        // End bound is inclusive end-of-day (23:59:59), strictly after start-of-day.
        let expectedEnd = calendar.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: calendar.startOfDay(for: day)
        )
        XCTAssertEqual(criteria.endDate, expectedEnd)
        XCTAssertTrue(criteria.isActive)
        XCTAssertTrue(criteria.needsDate)
    }

    func testSearchCriteriaSingleDayMatchesThatDay() {
        let day = Date(timeIntervalSince1970: 1_600_000_000)
        let noonThatDay = Calendar.current.startOfDay(for: day).addingTimeInterval(12 * 3600)
        let preset = FilterPreset(name: "D", startDate: day, endDate: day)
        XCTAssertTrue(preset.searchCriteria.matches(url: url("a.jpg"), captureDate: noonThatDay))
    }

    // MARK: - makeURLFilter predicate reconstruction

    func testMakeURLFilterNilWhenInactive() {
        let preset = FilterPreset(name: "Empty")
        XCTAssertNil(preset.makeURLFilter(favouriteURLStrings: [], ratings: [:], captureDates: [:]))
    }

    func testMakeURLFilterFilenameQuery() throws {
        let preset = FilterPreset(name: "Q", searchText: "cat")
        let filter = try XCTUnwrap(
            preset.makeURLFilter(favouriteURLStrings: [], ratings: [:], captureDates: [:])
        )
        XCTAssertTrue(filter(url("black-cat.jpg")))
        XCTAssertTrue(filter(url("CATNIP.png")))   // case-insensitive
        XCTAssertFalse(filter(url("dog.jpg")))
    }

    func testMakeURLFilterFavouritesOnly() throws {
        let fav = url("keep.jpg")
        let other = url("skip.jpg")
        let preset = FilterPreset(name: "F", favouritesOnly: true)
        let filter = try XCTUnwrap(
            preset.makeURLFilter(
                favouriteURLStrings: [fav.absoluteString],
                ratings: [:],
                captureDates: [:]
            )
        )
        XCTAssertTrue(filter(fav))
        XCTAssertFalse(filter(other))
    }

    func testMakeURLFilterMinimumRating() throws {
        let high = url("great.jpg")
        let low = url("meh.jpg")
        let unrated = url("none.jpg")
        let preset = FilterPreset(name: "R", minRating: 3)
        let filter = try XCTUnwrap(
            preset.makeURLFilter(
                favouriteURLStrings: [],
                ratings: [high: 4, low: 2],
                captureDates: [:]
            )
        )
        XCTAssertTrue(filter(high))
        XCTAssertFalse(filter(low))
        XCTAssertFalse(filter(unrated))
    }

    func testMakeURLFilterCombinesConstraintsWithAND() throws {
        let match = url("cat-fav.jpg")
        let wrongName = url("dog-fav.jpg")
        let notFav = url("cat-plain.jpg")
        let preset = FilterPreset(name: "Both", searchText: "cat", favouritesOnly: true)
        let filter = try XCTUnwrap(
            preset.makeURLFilter(
                favouriteURLStrings: [match.absoluteString, wrongName.absoluteString],
                ratings: [:],
                captureDates: [:]
            )
        )
        XCTAssertTrue(filter(match))
        XCTAssertFalse(filter(wrongName))   // fails filename
        XCTAssertFalse(filter(notFav))      // fails favourite
    }

    func testMakeURLFilterDateBoundExcludesMissingCaptureDate() throws {
        let day = Date(timeIntervalSince1970: 1_600_000_000)
        let inRange = url("dated.jpg")
        let undated = url("nodate.jpg")
        let preset = FilterPreset(name: "D", startDate: day, endDate: day)
        let noon = Calendar.current.startOfDay(for: day).addingTimeInterval(12 * 3600)
        let filter = try XCTUnwrap(
            preset.makeURLFilter(
                favouriteURLStrings: [],
                ratings: [:],
                captureDates: [inRange: noon]
            )
        )
        XCTAssertTrue(filter(inRange))
        XCTAssertFalse(filter(undated))   // nil capture date fails an active date bound
    }
}
