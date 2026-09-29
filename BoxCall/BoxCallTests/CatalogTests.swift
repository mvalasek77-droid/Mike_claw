import XCTest
@testable import BoxCall

private struct StubProvider: MovieDataProvider {
    let movies: [Movie]
    let isLive: Bool
    func fetchUpcoming(windowDays: Int) async throws -> [Movie] { movies }
}

@MainActor
final class CatalogTests: XCTestCase {
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func movie(_ id: String, _ title: String, on date: Date,
                       director: String? = nil, poster: String? = nil) -> Movie {
        Movie(id: id, title: title, studio: "Warner Bros.", releaseDate: date,
              posterEmoji: "🎬", posterURL: poster, tagline: title,
              consensusOpeningMillions: 30, impliedVolPct: 40, genre: "Drama",
              director: director)
    }

    // MARK: - Composite catalog

    func testLiveCalendarDate_beatsBundledDate_butBundledFactsStay() async throws {
        let feed = StubProvider(movies: [movie("sched_digger", "Digger", on: day(2026, 10, 9))], isLive: true)
        let bundled = StubProvider(movies: [movie("m_digger", "Digger", on: day(2026, 10, 2),
                                                  director: "Alejandro G. Iñárritu")], isLive: false)
        let merged = try await CompositeMovieProvider([feed, bundled]).fetchUpcoming(windowDays: 400)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].id, "m_digger")                  // positions keep their id
        XCTAssertEqual(merged[0].director, "Alejandro G. Iñárritu")
        XCTAssertEqual(merged[0].releaseDate, day(2026, 10, 9))   // the studio moved it
    }

    func testMissingPoster_isFilledFromAnotherSource() async throws {
        let feed = StubProvider(movies: [movie("tmdb_1", "Verity", on: day(2026, 10, 2),
                                               poster: "https://image.tmdb.org/p.jpg")], isLive: true)
        let bundled = StubProvider(movies: [movie("m_verity", "Verity", on: day(2026, 10, 2))], isLive: false)
        let merged = try await CompositeMovieProvider([feed, bundled]).fetchUpcoming(windowDays: 400)
        XCTAssertEqual(merged.first?.posterURL, "https://image.tmdb.org/p.jpg")
    }

    func testTitlesMatchAcrossPunctuationAndCase() async throws {
        let feed = StubProvider(movies: [movie("a", "Dr. Seuss’ The Cat in the Hat", on: day(2026, 11, 6))], isLive: true)
        let other = StubProvider(movies: [movie("b", "DR SEUSS THE CAT IN THE HAT", on: day(2026, 11, 6))], isLive: false)
        let merged = try await CompositeMovieProvider([feed, other]).fetchUpcoming(windowDays: 400)
        XCTAssertEqual(merged.count, 1)
    }

    // MARK: - Settlement matching

    func testOpening_fromAnOlderFilmWithTheSameTitle_doesNotSettle() {
        let film = movie("m_mummy", "The Mummy", on: day(2026, 10, 16))
        let old = SettlementService.PublishedOpening(millions: 12, weekendOf: day(2026, 5, 1))
        let own = SettlementService.PublishedOpening(millions: 40, weekendOf: day(2026, 10, 16))
        XCTAssertFalse(old.belongs(to: film))
        XCTAssertTrue(own.belongs(to: film))
    }

    func testOpening_forAWednesdayOpener_countsThatFridaysWeekend() {
        let film = movie("m_hexed", "Hexed", on: day(2026, 11, 25))
        let weekend = SettlementService.PublishedOpening(millions: 35, weekendOf: day(2026, 11, 27))
        XCTAssertTrue(weekend.belongs(to: film))
    }

    func testOpening_withoutAWeekend_stillCounts() {
        let film = movie("m_x", "Clayface", on: day(2026, 10, 23))
        XCTAssertTrue(SettlementService.PublishedOpening(millions: 20, weekendOf: nil).belongs(to: film))
    }

    // MARK: - Held contracts

    func testSingleContract_matchesTheChainsOwnPricing() {
        let film = movie("m_digger", "Digger", on: Date().addingTimeInterval(20 * 86_400))
        let tracking = Tracking(openingWeekendMillions: 30, impliedVolPct: 40)
        let setter = PriceSetter()
        for listed in setter.chain(for: film, tracking: tracking) {
            let single = setter.contract(for: film, side: listed.side,
                                         strike: listed.strikeMillions, tracking: tracking)
            XCTAssertEqual(single.id, listed.id)
            XCTAssertEqual(single.basePremium, listed.basePremium)
        }
    }

    func testMovieCopy_changesOnlyWhatWasAsked() {
        let film = movie("m_digger", "Digger", on: day(2026, 10, 2), director: "A. Director")
        let moved = film.with(releaseDate: day(2026, 10, 9))
        XCTAssertEqual(moved.releaseDate, day(2026, 10, 9))
        XCTAssertEqual(moved.id, film.id)
        XCTAssertEqual(moved.director, film.director)
        XCTAssertEqual(moved.consensusOpeningMillions, film.consensusOpeningMillions)
    }
}
