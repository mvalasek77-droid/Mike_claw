"""Tests for the free data pipeline.

Every parser is exercised against a recorded response shape, so the
whole suite runs with no network and no API keys.
"""
from __future__ import annotations

import datetime as dt
import json
import pathlib
import sys

import pytest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))

from boxcall_pipeline import sentiment  # noqa: E402
from boxcall_pipeline.sources import bluesky, boxoffice, schedule, tmdb, wikipedia, youtube  # noqa: E402

UTC = dt.timezone.utc
NOW = dt.datetime(2026, 9, 8, 12, 0, tzinfo=UTC)


# --------------------------------------------------------------------
# Sentiment
# --------------------------------------------------------------------

class TestSentiment:
    def test_clean_strips_links_and_handles_but_keeps_hashtag_words(self):
        got = sentiment.clean("@someone this is https://x.co/abc #masterpiece truly")
        assert "someone" not in got
        assert "https" not in got
        assert "masterpiece" in got

    def test_domain_lexicon_reads_film_slang(self):
        # Plain VADER has no idea these are opinions about a movie.
        assert sentiment.score_text("absolute banger, peak cinema") > 0.3
        assert sentiment.score_text("this is going to flop, total cashgrab") < -0.3

    def test_mid_is_negative_in_film_context(self):
        assert sentiment.score_text("honestly it looked mid") < 0

    def test_discourse_hedges_do_not_read_as_praise(self):
        """Stock VADER lists 'honestly' at +2.0 and 'pretty' at +2.2, so
        a hedged criticism scored positive. That is a systematic upward
        bias, because hedges preface complaints at least as often as
        compliments."""
        for phrase in [
            "honestly it looked mid",
            "pretty bad honestly",
            "seriously this looks like a flop",
            "arguably the worst trailer this year",
        ]:
            assert sentiment.score_text(phrase) < 0, phrase

    def test_neutralised_words_carry_no_opinion_alone(self):
        for word in ["honestly", "pretty", "clearly", "definitely"]:
            assert sentiment.score_text(word) == 0.0, word

    def test_genuine_praise_still_registers(self):
        """Neutralising hedges must not flatten real sentiment."""
        assert sentiment.score_text("honestly this looks incredible") > 0.3
        assert sentiment.score_text("pretty amazing trailer") > 0.3

    def test_trailer_vocabulary_vader_does_not_know(self):
        """Stock VADER scores none of these — they are absent from its
        lexicon entirely, so a whole register of trailer criticism read
        as perfectly neutral."""
        for phrase in ["completely forgettable", "soulless and bloated",
                       "totally uninspired", "so predictable", "pure cringe"]:
            assert sentiment.score_text(phrase) < 0, phrase
        for phrase in ["absolutely phenomenal", "gripping and immersive",
                       "this is a must-see", "spectacular stuff"]:
            assert sentiment.score_text(phrase) > 0, phrase

    def test_booster_words_were_released_so_they_can_carry_valence(self):
        """VADER zeroes any token in BOOSTER_DICT before reading the
        lexicon, so a word shipped as a booster can never hold an
        opinion no matter what we score it."""
        from vaderSentiment.vaderSentiment import BOOSTER_DICT

        assert "incredible" in sentiment.RELEASED_BOOSTERS
        assert "incredible" not in BOOSTER_DICT
        assert sentiment.score_text("this looks incredible") > 0.3

    def test_insane_is_praise_in_film_talk(self):
        """VADER lists it at -1.7; "this looks insane" is a rave."""
        assert sentiment.score_text("that trailer looks insane") > 0

    def test_empty_input_is_neutral_not_an_error(self):
        assert sentiment.score_text("") == 0.0
        assert sentiment.summarize([]) is sentiment.EMPTY
        assert sentiment.summarize([]).is_empty

    def test_summary_direction(self):
        positive = sentiment.summarize(
            [{"text": "masterpiece, best thing all year"}, {"text": "absolutely loved it"}]
        )
        negative = sentiment.summarize(
            [{"text": "total flop incoming"}, {"text": "unwatchable garbage"}]
        )
        assert positive.score > 0.2
        assert negative.score < -0.2
        assert positive.positive == 2
        assert negative.negative == 2

    def test_split_room_reads_as_dispersed(self):
        united = sentiment.summarize([{"text": "masterpiece"}] * 6)
        split = sentiment.summarize(
            [{"text": "masterpiece"}, {"text": "unwatchable"}] * 3
        )
        assert split.dispersion > united.dispersion
        assert abs(split.score) < abs(united.score)

    def test_engagement_weighting_favours_reach(self):
        """A post nobody saw should not outvote one thousands liked."""
        loud_positive = sentiment.summarize(
            [
                {"text": "masterpiece, incredible", "likes": 5000},
                {"text": "unwatchable garbage", "likes": 0},
            ]
        )
        assert loud_positive.score > 0

    def test_viral_post_cannot_fully_own_the_score(self):
        """Log weighting caps how much one post can dominate."""
        with_viral = sentiment.summarize(
            [
                {"text": "masterpiece", "likes": 10_000_000},
                {"text": "unwatchable"},
                {"text": "unwatchable"},
                {"text": "unwatchable"},
            ]
        )
        only_viral = sentiment.summarize(
            [{"text": "masterpiece", "likes": 10_000_000}]
        )
        assert with_viral.score < only_viral.score

    def test_scores_stay_in_range(self):
        summary = sentiment.summarize(
            [{"text": "masterpiece " * 50, "likes": 10**9}] * 20
        )
        assert -1.0 <= summary.score <= 1.0
        assert 0.0 <= summary.dispersion <= 1.0


# --------------------------------------------------------------------
# Bluesky
# --------------------------------------------------------------------

SEARCH_FIXTURE = {
    "posts": [
        {
            "uri": "at://did:plc:aaa/app.bsky.feed.post/1",
            "likeCount": 120,
            "repostCount": 14,
            "replyCount": 3,
            "record": {"text": "Dune Part Three trailer is peak cinema",
                       "createdAt": "2026-09-08T09:00:00.000Z"},
        },
        {
            "uri": "at://did:plc:bbb/app.bsky.feed.post/2",
            "likeCount": 2,
            "repostCount": 0,
            "record": {"text": "not sure about this one honestly",
                       "createdAt": "2026-09-08T11:30:00Z"},
        },
        {   # Outside the 24h window — must be dropped.
            "uri": "at://did:plc:ccc/app.bsky.feed.post/3",
            "likeCount": 900,
            "record": {"text": "old chatter from last month",
                       "createdAt": "2026-08-01T09:00:00Z"},
        },
        {   # No text — must be skipped, not crash.
            "uri": "at://did:plc:ddd/app.bsky.feed.post/4",
            "record": {"createdAt": "2026-09-08T10:00:00Z"},
        },
    ]
}


class TestBluesky:
    def test_query_is_quoted_so_words_stay_adjacent(self):
        assert bluesky.build_query("Dune: Part Three") == '"Dune Part Three"'

    def test_query_survives_punctuation_and_empties(self):
        assert bluesky.build_query("Wicked: For Good") == '"Wicked For Good"'
        assert bluesky.build_query("   ") == ""
        assert bluesky.build_query("!!!") == ""

    def test_parse_keeps_recent_posts_only(self):
        since = NOW - dt.timedelta(hours=24)
        posts = bluesky.parse_search_response(SEARCH_FIXTURE, since=since)
        texts = [p["text"] for p in posts]
        assert len(posts) == 2
        assert "old chatter from last month" not in texts

    def test_parse_extracts_engagement(self):
        since = NOW - dt.timedelta(hours=24)
        posts = bluesky.parse_search_response(SEARCH_FIXTURE, since=since)
        assert posts[0]["likes"] == 120
        assert posts[0]["reposts"] == 14

    def test_parse_tolerates_missing_and_malformed_fields(self):
        since = NOW - dt.timedelta(hours=24)
        assert bluesky.parse_search_response({}, since=since) == []
        assert bluesky.parse_search_response({"posts": []}, since=since) == []
        weird = {"posts": [{"record": {"text": "hi", "createdAt": "not-a-date"}}]}
        # Unparseable date means we cannot prove it is old, so keep it.
        assert len(bluesky.parse_search_response(weird, since=since)) == 1

    def test_search_returns_empty_on_transport_failure(self):
        class Boom:
            def get(self, *a, **k):
                raise __import__("httpx").HTTPError("down")

        assert bluesky.search_posts(Boom(), "Dune", now=NOW) == []

    def test_search_returns_empty_on_error_status(self):
        class Resp:
            status_code = 503

            def json(self):
                raise AssertionError("must not parse a failed response")

        class Client:
            def get(self, *a, **k):
                return Resp()

        assert bluesky.search_posts(Client(), "Dune", now=NOW) == []

    def test_failures_are_counted_and_reported_with_a_fix(self):
        import collections

        class Resp:
            status_code = 403

        class Client:
            def get(self, *a, **k):
                return Resp()

        stats = collections.Counter()
        for title in ("Dune", "Clayface"):
            bluesky.search_posts(Client(), title, now=NOW, stats=stats)
        assert stats == {403: 2}
        line = bluesky.describe(stats, 0, 2, signed_in=False)
        assert line.startswith("no data (403 x2)") and "BLUESKY_APP_PASSWORD" in line
        assert bluesky.describe(collections.Counter({200: 2}), 2, 2, signed_in=True) == "ok (2/2 titles, signed in)"

    def test_signed_in_search_uses_the_account_host_and_token(self):
        seen = {}

        class Resp:
            status_code = 200

            def json(self):
                return {"posts": []}

        class Client:
            def get(self, url, headers=None, **k):
                seen["url"], seen["headers"] = url, headers
                return Resp()

        bluesky.search_posts(Client(), "Dune", now=NOW, token="abc")
        assert seen["url"].startswith(bluesky.AUTH_HOST)
        assert seen["headers"] == {"Authorization": "Bearer abc"}

    def test_login_without_credentials_does_not_call_out(self):
        class Client:
            def post(self, *a, **k):
                raise AssertionError("no credentials, no request")

        assert bluesky.login(Client(), "", "") is None


# --------------------------------------------------------------------
# Wikipedia
# --------------------------------------------------------------------

PAGEVIEWS_FIXTURE = {
    "items": [
        {"timestamp": f"202608{day:02d}00", "views": 1000} for day in range(18, 25)
    ] + [
        {"timestamp": f"202609{day:02d}00", "views": 3000} for day in range(1, 8)
    ]
}


class TestWikipedia:
    def test_path_encodes_the_title_as_one_segment(self):
        path = wikipedia.daily_views_path(
            "Dune: Part Three", dt.date(2026, 8, 1), dt.date(2026, 8, 8)
        )
        assert "Dune%3A_Part_Three" in path
        assert path.endswith("/20260801/20260808")

    def test_parse_sorts_oldest_first(self):
        series = wikipedia.parse_daily_views(PAGEVIEWS_FIXTURE)
        assert series[0][0] < series[-1][0]
        assert len(series) == 14

    def test_velocity_detects_building_interest(self):
        views, vel = wikipedia.velocity(wikipedia.parse_daily_views(PAGEVIEWS_FIXTURE))
        assert views == 21000
        assert vel == pytest.approx(3.0)

    def test_velocity_of_flat_interest_is_one(self):
        flat = [(f"2026090{d}", 500) for d in range(1, 9)][:14]
        series = [(f"20260{d:03d}", 500) for d in range(801, 815)]
        _, vel = wikipedia.velocity(series)
        assert vel == pytest.approx(1.0)

    def test_no_prior_week_reports_flat_not_infinity(self):
        series = [("20260901", 100), ("20260902", 200)]
        views, vel = wikipedia.velocity(series)
        assert views == 300
        assert vel == 1.0

    def test_empty_series_is_safe(self):
        assert wikipedia.velocity([]) == (0, 1.0)
        assert wikipedia.parse_daily_views({}) == []

    def test_fetch_velocity_degrades_on_failure(self):
        class Client:
            def get(self, *a, **k):
                raise __import__("httpx").HTTPError("nope")

        assert wikipedia.fetch_velocity(Client(), "Dune") == (0, 1.0)


# --------------------------------------------------------------------
# YouTube
# --------------------------------------------------------------------

class TestYouTube:
    def test_trailer_matching_accepts_the_real_thing(self):
        assert youtube.is_plausible_trailer(
            "Dune: Part Three | Official Trailer", "Warner Bros. Pictures",
            "Dune: Part Three")

    def test_trailer_matching_rejects_reactions_and_fan_edits(self):
        assert not youtube.is_plausible_trailer(
            "Dune Part Three Trailer REACTION", "Fan Channel", "Dune: Part Three")
        assert not youtube.is_plausible_trailer(
            "Superman Concept Trailer (Fan Made)", "Edits", "Superman")

    def test_trailer_matching_rejects_a_different_film(self):
        assert not youtube.is_plausible_trailer(
            "Wicked: For Good | Official Trailer", "Universal", "Dune: Part Three")

    def test_matcher_agrees_with_the_swift_client(self):
        """Both sides must accept and reject the same videos, or the
        server and the app will price different trailers."""
        assert youtube.is_plausible_trailer(
            "THE LEGEND OF ZELDA — Official Trailer (2027)", "Sony Pictures",
            "The Legend of Zelda")
        assert not youtube.is_plausible_trailer(
            "Dune: Part Three — Behind The Scenes", "Warner Bros.", "Dune: Part Three")

    def test_view_curve_matches_the_swift_implementation(self):
        assert youtube.trailing_week_fraction(1) == 1.0
        assert youtube.trailing_week_fraction(7) == 1.0
        assert youtube.trailing_week_fraction(30) < youtube.trailing_week_fraction(7)
        assert youtube.trailing_week_fraction(180) < 0.01

    def test_view_curve_is_monotonic(self):
        previous = 1.1
        for age in range(1, 366, 3):
            fraction = youtube.trailing_week_fraction(age)
            assert 0.0 <= fraction <= 1.0
            assert fraction <= previous + 1e-9
            previous = fraction

    def test_trailing_views_separate_fresh_from_stale(self):
        fresh = youtube.trailing_week_views(
            50_000_000, NOW - dt.timedelta(days=5), now=NOW)
        stale = youtube.trailing_week_views(
            50_000_000, NOW - dt.timedelta(days=180), now=NOW)
        assert fresh == 50_000_000
        assert stale < 1_000_000

    def test_hidden_counts_parse_as_none_not_zero(self):
        payload = {"items": [{"id": "abc", "statistics": {"viewCount": "500"},
                              "snippet": {"publishedAt": "2026-09-01T00:00:00Z"}}]}
        stats = youtube.parse_video_stats(payload)
        assert stats["abc"]["views"] == 500
        assert stats["abc"]["likes"] is None

    def test_parse_stats_reads_publish_date(self):
        payload = {"items": [{"id": "xyz",
                              "statistics": {"viewCount": "10", "likeCount": "2"},
                              "snippet": {"publishedAt": "2026-09-01T10:30:00Z"}}]}
        stats = youtube.parse_video_stats(payload)
        assert stats["xyz"]["published_at"].year == 2026
        assert stats["xyz"]["likes"] == 2

    def test_pick_trailer_skips_bad_hits_and_takes_the_good_one(self):
        payload = {"items": [
            {"id": {"videoId": "bad"},
             "snippet": {"title": "Dune Part Three Trailer Reaction",
                         "channelTitle": "Fans"}},
            {"id": {"videoId": "good"},
             "snippet": {"title": "Dune: Part Three | Official Trailer",
                         "channelTitle": "Warner Bros. Pictures"}},
        ]}
        assert youtube.pick_trailer(payload, "Dune: Part Three") == "good"

    def test_pick_trailer_returns_none_when_nothing_matches(self):
        payload = {"items": [{"id": {"videoId": "x"},
                              "snippet": {"title": "unrelated vlog",
                                          "channelTitle": "someone"}}]}
        assert youtube.pick_trailer(payload, "Dune") is None


# --------------------------------------------------------------------
# Box Office
# --------------------------------------------------------------------

BOM_FIXTURE = """
<table>
<tr><th>Rank</th><th>LW</th><th>Release</th><th>Gross</th><th>%\u00b1 LW</th><th>Theaters</th>
<th>Change</th><th>Average</th><th>Total Gross</th><th>Weeks</th><th>Distributor</th>
<th>New This Week</th><th>Estimated</th></tr>
<tr><td>1</td><td>-</td><td><a href="/release/rl1">Avengers: Endgame Encore</a></td>
<td>$26,000,000</td><td>-</td><td>3,900</td><td>-</td><td>$6,666</td><td>$26,000,000</td>
<td>1</td><td>Walt Disney</td><td>true</td><td>true</td></tr>
<tr><td>2</td><td>1</td><td><a href="/release/rl2">Resident Evil</a></td>
<td>$23,300,000</td><td>-61.2%</td><td>3,600</td><td>-</td><td>$6,472</td><td>$103,400,000</td>
<td>2</td><td>Sony</td><td>false</td><td>true</td></tr>
<tr><td>3</td><td>-</td><td><a href="/release/rl3">Heart of the Beast</a></td>
<td>$20,000,000</td><td>-</td><td>3,100</td><td>-</td><td>$6,451</td><td>$20,000,000</td>
<td>1</td><td>Paramount</td><td>true</td><td>true</td></tr>
</table>
"""

NUMBERS_FIXTURE = """
<table>
<tr><th></th><th></th><th>Movie Title</th><th>Distributor</th><th>Gross</th><th>Change</th>
<th>Thtrs.</th><th>Change</th><th>Per Thtr.</th><th>Total Gross</th><th>Week</th></tr>
<tr><td>1</td><td>new</td><td><b><a href="/movie/x">Resident Evil</a></b></td><td>Sony</td>
<td>$60,100,000</td><td></td><td>3,500</td><td></td><td>$17,171</td><td>$60,100,000</td><td>1</td></tr>
<tr><td>2</td><td>1</td><td><b><a href="/movie/y">Practical Magic 2</a></b></td><td>Warner Bros.</td>
<td>$12,200,000</td><td>-59%</td><td>3,700</td><td></td><td>$3,297</td><td>$50,000,000</td><td>2</td></tr>
</table>
"""


class TestBoxOffice:
    def test_bom_columns_are_found_by_header(self):
        results = boxoffice.parse_chart(BOM_FIXTURE, source="boxofficemojo")
        assert [r.title for r in results] == [
            "Avengers: Endgame Encore", "Resident Evil", "Heart of the Beast"]
        assert results[0].gross_millions == 26.0
        assert results[0].is_estimate is True

    def test_only_first_weekends_count_as_openings(self):
        results = boxoffice.parse_chart(BOM_FIXTURE, source="boxofficemojo")
        opening = {r.title for r in results if r.is_opening_weekend}
        assert opening == {"Avengers: Endgame Encore", "Heart of the Beast"}

    def test_the_numbers_layout_parses_the_same_way(self):
        results = boxoffice.parse_chart(NUMBERS_FIXTURE, source="the-numbers")
        assert results[0].title == "Resident Evil"
        assert results[0].gross_millions == 60.1
        assert results[0].is_opening_weekend is True
        assert results[1].is_opening_weekend is False

    def test_a_page_without_a_header_row_yields_nothing(self):
        assert boxoffice.parse_chart("<table><tr><td>1</td></tr></table>", source="x") == []

    def test_weekend_friday(self):
        assert boxoffice.weekend_friday(dt.date(2026, 9, 27)) == dt.date(2026, 9, 25)  # Sunday
        assert boxoffice.weekend_friday(dt.date(2026, 9, 25)) == dt.date(2026, 9, 25)  # Friday
        assert boxoffice.weekend_friday(dt.date(2026, 9, 30)) == dt.date(2026, 9, 25)  # Wednesday

    def test_sunday_asks_for_this_weekend_friday_does_not(self):
        assert boxoffice.weekends_to_check(dt.date(2026, 9, 27))[0] == dt.date(2026, 9, 25)
        assert boxoffice.weekends_to_check(dt.date(2026, 9, 25))[0] == dt.date(2026, 9, 18)

    def test_bom_url_uses_the_iso_week_of_the_friday(self):
        year, week, _ = dt.date(2026, 9, 25).isocalendar()
        assert boxoffice.BOM_WEEKEND_URL.format(year=year, week=week).endswith("/weekend/2026W39/")

    def test_parse_gross_handles_formats(self):
        assert boxoffice._parse_gross("$75,200,000") == 75200000.0
        assert boxoffice._parse_gross("") is None
        assert boxoffice._parse_gross("N/A") is None

    def test_franchise_entries_start_higher(self):
        assert schedule.franchise_factor("Violent Night 2") == 1.6
        assert schedule.franchise_factor("Dune: Part Three") == 1.6
        assert schedule.franchise_factor("Frozen III") == 1.6
        assert schedule.franchise_factor("The Hunger Games: Sunrise on the Reaping") == 1.3
        assert schedule.franchise_factor("Avengers: Doomsday") == 1.3
        assert schedule.franchise_factor("Ali G: Who Iz I?") == 1.0
        assert schedule.franchise_factor("Digger") == 1.0
        assert schedule.estimate_opening(20.0, None, "Violent Night 2") == 32.0

    def test_fetch_degrades_on_failure(self):
        class Boom:
            def get(self, *a, **k):
                raise __import__("httpx").HTTPError("down")

        assert boxoffice.fetch_actuals(Boom(), today=dt.date(2026, 9, 27)) == []


CALENDAR_FIXTURE = """
<h3>October 2, 2026</h3>
<table>
<tr><th>Release</th><th>Distributor</th><th>Scale</th></tr>
<tr><td><a href="/release/rl9/">Verity</a></td><td>Amazon MGM Studios</td><td>Wide</td></tr>
<tr><td><a href="/release/rl8/">Neon Nights</a></td><td>Tiny Pictures</td><td>Limited</td></tr>
<tr><td><a href="/release/rl7/">Small Film</a></td><td>A24</td><td>Limited</td></tr>
</table>
<h3>October 16, 2026</h3>
<table>
<tr><td><a href="/release/rl6/">Street Fighter</a></td><td>Paramount Pictures</td><td>Wide</td></tr>
<tr><td><a href="/release/rl5/">Far Future (2027)</a></td><td>Walt Disney Studios</td><td>Wide</td></tr>
</table>
<h3>March 5, 2027</h3>
<table>
<tr><td><a href="/release/rl4/">Too Far Out</a></td><td>Universal Pictures</td><td>Wide</td></tr>
</table>
"""


class TestSchedule:
    TODAY = dt.date(2026, 9, 28)

    def _parse(self):
        return schedule.parse_calendar(CALENDAR_FIXTURE, source="boxofficemojo",
                                       today=self.TODAY, horizon_days=90)

    def test_wide_studio_releases_are_picked_up_with_their_dates(self):
        films = {f["title"]: f for f in self._parse()}
        assert films["Verity"]["releaseDate"] == "2026-10-02"
        assert films["Street Fighter"]["releaseDate"] == "2026-10-16"
        assert films["Street Fighter"]["distributor"] == "Paramount"

    def test_limited_and_unknown_distributors_are_skipped(self):
        titles = {f["title"] for f in self._parse()}
        assert "Neon Nights" not in titles     # title must not count as the distributor
        assert "Small Film" not in titles      # limited release

    def test_year_suffix_is_stripped_and_horizon_respected(self):
        titles = {f["title"] for f in self._parse()}
        assert "Far Future" in titles
        assert "Too Far Out" not in titles     # beyond 90 days

    def test_estimate_scales_with_attention_within_bounds(self):
        assert schedule.estimate_opening(20.0, None) == 20.0
        assert schedule.estimate_opening(20.0, 40_000) == 20.0
        assert schedule.estimate_opening(20.0, 10_000_000) == 50.0
        assert schedule.estimate_opening(20.0, 1) == 10.0

    def test_fetch_degrades_on_failure(self):
        class Boom:
            def get(self, *a, **k):
                raise __import__("httpx").HTTPError("down")

        films, status = schedule.fetch_upcoming(Boom(), today=self.TODAY)
        assert films == [] and "HTTPError" in status


# Row shapes as the live pages returned them (September 2026).
BOM_CALENDAR_REAL = """
<table>
<tr><th colspan="4">Friday, October 2, 2026</th></tr>
<tr><td><a href="/title/tt1/"><img src="p.jpg"></a></td>
<td><a href="/release/rl1/">Digger</a> Comedy Drama With: Tom Cruise, Riz Ahmed 2 hr 8 min
<a href="/title/tt1/credits/">Cast, Crew, and Company Info</a></td><td>Warner Bros.</td><td>Wide</td></tr>
<tr><td><a href="/title/tt2/"><img src="p.jpg"></a></td>
<td><a href="/release/rl2/">Moonlight 10th Anniversary</a> Drama With: Mahershala Ali
<a href="/title/tt2/credits/">Cast, Crew, and Company Info</a></td><td>A24</td><td>Limited</td></tr>
</table>
"""

NUMBERS_CALENDAR_REAL = """
<table>
<tr><td>September 30</td><td><a href="/movie/a">Begotten</a> (Limited, re-release)</td><td>Kino Lorber</td></tr>
<tr><td></td><td><a href="/movie/b">Linkin Park: Unshatter</a> (Limited)</td><td>CJ4DPlex</td></tr>
<tr><td>Summer 2026</td><td><a href="/movie/c">The Last Temptation of Becky</a> (Limited)</td><td>Quiver</td></tr>
<tr><td></td><td><a href="/movie/c2">Mystery Date Film</a> (Wide)</td><td>Universal</td></tr>
<tr><td>October 2</td><td><a href="/movie/d">April X</a> (Wide)</td><td>Ahoy Associates Entertainment</td></tr>
<tr><td></td><td><a href="/movie/e">Beware Boiúna</a> (Wide)</td><td>Lionsgate Premiere</td></tr>
<tr><td></td><td><a href="/movie/f">Digger</a> (Wide)</td><td>Warner Bros.</td></tr>
<tr><td></td><td><a href="/movie/g">Verity</a> (Wide)</td><td>Amazon MGM Studios</td></tr>
</table>
"""


class TestScheduleOnRealLayouts:
    TODAY = dt.date(2026, 9, 28)

    def _titles(self, page, source):
        return {f["title"]: f for f in schedule.parse_calendar(page, source=source,
                                                               today=self.TODAY, horizon_days=90)}

    def test_bom_poster_link_is_skipped_and_title_found(self):
        films = self._titles(BOM_CALENDAR_REAL, "boxofficemojo")
        assert set(films) == {"Digger"}
        assert films["Digger"]["releaseDate"] == "2026-10-02"
        assert films["Digger"]["distributor"] == "Warner"

    def test_numbers_dates_without_a_year_and_vague_dates(self):
        films = self._titles(NUMBERS_CALENDAR_REAL, "the-numbers")
        assert set(films) == {"Digger", "Verity"}
        assert films["Verity"]["releaseDate"] == "2026-10-02"

    def test_fetch_reads_every_page_and_merges_both_sites(self):
        later = BOM_CALENDAR_REAL.replace("October 2, 2026", "November 20, 2026") \
            .replace(">Digger<", ">The Hunger Games: Sunrise on the Reaping<") \
            .replace("Warner Bros.", "Lionsgate")

        class Response:
            def __init__(self, text, code=200):
                self.text, self.status_code = text, code

        class Client:
            def __init__(self):
                self.urls = []

            def get(self, url, **_):
                self.urls.append(url)
                if "the-numbers" in url:
                    return Response(NUMBERS_CALENDAR_REAL)
                if url.endswith("/calendar/"):
                    return Response(BOM_CALENDAR_REAL)
                if "2026-10-26" in url:
                    return Response(later)
                return Response("", 404)

        client = Client()
        films, status = schedule.fetch_upcoming(client, today=self.TODAY)
        by_title = {f["title"]: f for f in films}
        # BOM's first page, a later BOM page, and The Numbers all count.
        assert set(by_title) == {"Digger", "Verity", "The Hunger Games: Sunrise on the Reaping"}
        assert by_title["Digger"]["source"] == "boxofficemojo"   # first site wins a tie
        assert by_title["Verity"]["source"] == "the-numbers"
        assert [f["releaseDate"] for f in films] == sorted(f["releaseDate"] for f in films)
        assert any(u.endswith("/calendar/2026-12-21/") for u in client.urls)   # out to the horizon
        assert status.startswith("ok (3 wide releases") and "HTTP 404" in status

    def test_placeholders_and_renamed_duplicates_are_dropped(self):
        page = """<table>
<tr><td>November 6</td><td><a href="/movie/a">Ramayana</a> (Wide)</td><td>Sony Pictures</td></tr>
<tr><td></td><td><a href="/movie/b">Untitled Disney Film</a> (Wide)</td><td>Walt Disney</td></tr>
</table>"""
        other = page.replace(">Ramayana<", ">Ramayana Part 1<")

        class Response:
            status_code = 200

            def __init__(self, text):
                self.text = text

        class Client:
            def get(self, url, **_):
                return Response(other if "the-numbers" in url else page)

        films, _ = schedule.fetch_upcoming(Client(), today=self.TODAY)
        assert [f["title"] for f in films] == ["Ramayana"]

    def test_year_less_dates_later_in_the_page_belong_to_later_years(self):
        page = """<table>
<tr><td>December 18</td><td><a href="/movie/a">Dune: Part Three</a> (Wide)</td><td>Warner Bros.</td></tr>
<tr><td>January 8</td><td><a href="/movie/b">Early Film</a> (Wide)</td><td>Universal</td></tr>
<tr><td>November 24</td><td><a href="/movie/c">Frozen III</a> (Wide)</td><td>Walt Disney</td></tr>
<tr><td>December 17</td><td><a href="/movie/d">Avengers: Secret Wars</a> (Wide)</td><td>Walt Disney</td></tr>
</table>"""
        films = {f["title"]: f for f in schedule.parse_calendar(
            page, source="the-numbers", today=self.TODAY, horizon_days=500)}
        assert films["Dune: Part Three"]["releaseDate"] == "2026-12-18"
        assert films["Early Film"]["releaseDate"] == "2027-01-08"
        assert films["Frozen III"]["releaseDate"] == "2027-11-24"
        assert films["Avengers: Secret Wars"]["releaseDate"] == "2027-12-17"
        near = schedule.parse_calendar(page, source="the-numbers", today=self.TODAY, horizon_days=90)
        assert {f["title"] for f in near} == {"Dune: Part Three"}

    def test_year_rolls_over_for_early_months(self):
        assert schedule._parse_date("January 8", dt.date(2026, 11, 20)) == dt.date(2027, 1, 8)
        assert schedule._parse_date("September 30", dt.date(2026, 9, 28)) == dt.date(2026, 9, 30)


class TestMergeCatalog:
    def test_one_entry_per_title_first_source_wins_later_fill_gaps(self):
        from boxcall_pipeline.build import merge_catalog
        tmdb_movies = [{"id": "tmdb_1", "title": "Verity", "releaseDate": "2026-10-02", "popularity": 50}]
        calendar = [{"id": "sched_verity", "title": "VERITY", "releaseDate": "2026-10-02",
                     "distributor": "Amazon"}]
        merged = merge_catalog(tmdb_movies, calendar, today=dt.date(2026, 9, 28))
        assert len(merged) == 1
        assert merged[0]["id"] == "tmdb_1" and merged[0]["distributor"] == "Amazon"

    def test_films_that_already_opened_are_dropped(self):
        from boxcall_pipeline.build import merge_catalog
        seed = [{"id": "s", "title": "Resident Evil", "releaseDate": "2026-09-18"}]
        assert merge_catalog(seed, today=dt.date(2026, 9, 28)) == []


class TestActualsHistory:
    NOW = dt.datetime(2026, 9, 27, 20, tzinfo=dt.timezone.utc)

    def _collect(self, monkeypatch, results, previous=None, movies=None):
        from boxcall_pipeline import build as build_module
        monkeypatch.setattr(boxoffice, "fetch_actuals", lambda client, today=None: results)
        return build_module.collect_actuals(movies or [], self.NOW, previous)

    def _opening(self, title, gross, *, opening=True, estimate=True):
        return boxoffice.OpeningResult(title, gross, opening, "boxofficemojo", "2026-09-25", estimate)

    def test_openings_are_keyed_by_catalog_id_when_known(self, monkeypatch):
        actuals = self._collect(monkeypatch, [self._opening("Resident Evil", 60.1)],
                                movies=[{"id": "seed_resident_evil", "title": "Resident Evil"}])
        assert actuals["seed_resident_evil"]["domesticOpeningMillions"] == 60.1

    def test_films_outside_the_catalog_are_published_by_title(self, monkeypatch):
        actuals = self._collect(monkeypatch, [self._opening("Heart of the Beast", 20.0)])
        assert actuals["title:heart-of-the-beast"]["title"] == "Heart of the Beast"

    def test_second_weekends_never_become_an_opening(self, monkeypatch):
        actuals = self._collect(monkeypatch, [self._opening("Resident Evil", 23.3, opening=False)])
        assert actuals == {}

    def test_a_published_opening_is_frozen(self, monkeypatch):
        previous = {"seed_resident_evil": {"title": "Resident Evil", "domesticOpeningMillions": 60.1,
                                           "weekendOf": "2026-09-18"}}
        actuals = self._collect(monkeypatch, [self._opening("Resident Evil", 61.0, estimate=False)],
                                previous=previous)
        assert actuals["seed_resident_evil"]["domesticOpeningMillions"] == 60.1

    def test_same_title_on_a_later_weekend_is_a_new_film(self, monkeypatch):
        previous = {"title:the-mummy": {"title": "The Mummy", "domesticOpeningMillions": 12.0,
                                        "weekendOf": "2026-05-01"}}
        later = boxoffice.OpeningResult("The Mummy", 40.0, True, "boxofficemojo", "2026-10-16", True)
        actuals = self._collect(monkeypatch, [later], previous=previous,
                                movies=[{"id": "sched_the-mummy", "title": "The Mummy",
                                         "releaseDate": "2026-10-16"}])
        assert actuals["title:the-mummy"]["domesticOpeningMillions"] == 12.0
        assert actuals["sched_the-mummy"]["domesticOpeningMillions"] == 40.0

    def test_an_older_same_title_opening_is_not_keyed_to_the_new_film(self, monkeypatch):
        old = boxoffice.OpeningResult("The Mummy", 12.0, True, "boxofficemojo", "2026-05-01", False)
        actuals = self._collect(monkeypatch, [old],
                                movies=[{"id": "sched_the-mummy", "title": "The Mummy",
                                         "releaseDate": "2026-10-16"}])
        assert "sched_the-mummy" not in actuals and "title:the-mummy" in actuals

    def test_a_film_that_already_opened_limited_is_not_listed(self):
        from boxcall_pipeline.build import already_opened
        actuals = {"title:your-mother": {"title": "Your Mother, Your Mother, Your Mother",
                                         "weekendOf": "2026-09-25"}}
        movies = [{"id": "sched_ym", "title": "Your Mother, Your Mother, Your Mother",
                   "releaseDate": "2026-10-09"},
                  {"id": "sched_fresh", "title": "Digger", "releaseDate": "2026-10-02"},
                  {"id": "sched_wed", "title": "Hexed", "releaseDate": "2026-11-25"}]
        actuals["title:hexed"] = {"title": "Hexed", "weekendOf": "2026-11-27"}  # its own opening
        assert already_opened(movies, actuals) == {"sched_ym"}

    def test_history_is_carried_forward_and_pruned_after_six_months(self, monkeypatch):
        previous = {
            "recent": {"title": "Recent", "domesticOpeningMillions": 10, "weekendOf": "2026-09-11"},
            "ancient": {"title": "Ancient", "domesticOpeningMillions": 10, "weekendOf": "2026-01-02"},
        }
        actuals = self._collect(monkeypatch, [], previous=previous)
        assert "recent" in actuals and "ancient" not in actuals

    def test_title_key_ignores_case_and_punctuation(self):
        from boxcall_pipeline.build import title_key
        assert title_key("Spider-Man: Brand New Day") == title_key("spider man brand new day")
        assert title_key("Amélie") == "amelie"


# --------------------------------------------------------------------
# TMDB
# --------------------------------------------------------------------

class TestTMDB:
    def test_parse_drops_already_released_films(self):
        today = dt.date(2026, 9, 8)
        raw = {"id": 1, "title": "Old One", "release_date": "2026-01-01"}
        assert tmdb.parse_movie(raw, today=today) is None

    def test_parse_drops_undated_films(self):
        today = dt.date(2026, 9, 8)
        assert tmdb.parse_movie({"id": 1, "title": "TBD"}, today=today) is None
        assert tmdb.parse_movie(
            {"id": 1, "title": "Bad", "release_date": "not-a-date"}, today=today
        ) is None

    def test_parse_builds_our_shape(self):
        today = dt.date(2026, 9, 8)
        movie = tmdb.parse_movie(
            {"id": 42, "title": "Future Film", "release_date": "2026-11-20",
             "poster_path": "/abc.jpg", "genre_ids": [878], "popularity": 91.2,
             "overview": "Something happens."},
            today=today,
        )
        assert movie["id"] == "tmdb_42"
        assert movie["genre"] == "Sci-Fi"
        assert movie["posterURL"].endswith("/abc.jpg")
        assert movie["overview"] == "Something happens."

    def test_parse_upcoming_respects_the_window(self):
        today = dt.date(2026, 9, 8)
        payload = {"results": [
            {"id": 1, "title": "Soon", "release_date": "2026-09-25"},
            {"id": 2, "title": "Way Out", "release_date": "2028-01-01"},
        ]}
        titles = [m["title"] for m in
                  tmdb.parse_upcoming(payload, today=today, window_days=90)]
        assert titles == ["Soon"]

    def test_fetch_without_a_key_is_empty_not_an_error(self):
        assert tmdb.fetch_upcoming(None, "") == []


# --------------------------------------------------------------------
# End-to-end build with every network call stubbed
# --------------------------------------------------------------------

class StubClient:
    """Serves recorded payloads by URL substring."""

    def __init__(self):
        self.calls: list[str] = []

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def get(self, url, **kwargs):
        url = str(url)
        params = kwargs.get("params") or {}
        self.calls.append(url)

        class Resp:
            status_code = 200

            def __init__(self, payload):
                self._payload = payload
                self.text = json.dumps(payload) if payload else ""

            def json(self):
                return self._payload

        if "searchPosts" in url:
            return Resp(SEARCH_FIXTURE)
        if "api.php" in url:
            return Resp({"query": {"search": [{"title": "Dune: Part Three"}]}})
        if "pageviews" in url:
            return Resp(PAGEVIEWS_FIXTURE)
        if "youtube/v3/search" in url:
            return Resp({"items": [{"id": {"videoId": "vid1"},
                                    "snippet": {"title": "Dune: Part Three | Official Trailer",
                                                "channelTitle": "Warner Bros."}}]})
        if "youtube/v3/videos" in url:
            return Resp({"items": [{"id": "vid1",
                                    "statistics": {"viewCount": "20000000",
                                                   "likeCount": "600000"},
                                    "snippet": {"publishedAt": "2026-09-05T00:00:00Z"}}]})
        if "movie/upcoming" in url:
            if params.get("page", 1) > 1:
                return Resp({"results": []})
            return Resp({"results": [
                {"id": 42, "title": "Dune: Part Three", "release_date": "2026-11-20",
                 "genre_ids": [878], "poster_path": "/d.jpg", "popularity": 88.0},
            ]})
        return Resp({})


@pytest.fixture()
def stub_httpx(monkeypatch):
    from boxcall_pipeline import build as build_module

    client = StubClient()
    monkeypatch.setattr(build_module.httpx, "Client", lambda **kw: client)
    return client


class TestBuild:
    def _run(self, tmp_path, stub_httpx, **overrides):
        from boxcall_pipeline import build as build_module

        kwargs = dict(
            seed_path=tmp_path / "seed.json",
            cache_path=tmp_path / "cache.json",
            tmdb_key="fake",
            youtube_key="fake",
            max_movies=5,
            youtube_search_budget=8,
            now=NOW,
        )
        kwargs.update(overrides)
        return build_module.build(tmp_path / "api", **kwargs)

    def test_build_writes_all_four_documents(self, tmp_path, stub_httpx):
        manifest = self._run(tmp_path, stub_httpx)
        out = tmp_path / "api"
        assert (out / "index.json").exists()
        assert (out / "upcoming.json").exists()
        assert (out / "signals.json").exists()
        assert (out / "actuals.json").exists()
        assert manifest["version"] == 1
        assert manifest["movieCount"] == 1

    def test_signals_carry_every_source(self, tmp_path, stub_httpx):
        self._run(tmp_path, stub_httpx)
        signals = json.loads((tmp_path / "api" / "signals.json").read_text())
        entry = signals["signals"]["tmdb_42"]
        assert entry["socialMentions24h"] == 2
        assert entry["socialSentiment"] is not None
        assert entry["wikipediaViews7d"] == 21000
        assert entry["wikipediaVelocity"] == pytest.approx(3.0)
        assert entry["youtubeViews7d"] == 20_000_000
        assert entry["youtubeEngagementRate"] == pytest.approx(0.03)

    def test_internal_fields_do_not_leak_into_the_published_json(self, tmp_path, stub_httpx):
        self._run(tmp_path, stub_httpx)
        raw = (tmp_path / "api" / "signals.json").read_text()
        assert "_trailerVideoId" not in raw

    def test_trailer_ids_are_cached_so_search_runs_once(self, tmp_path, stub_httpx):
        self._run(tmp_path, stub_httpx)
        cache = json.loads((tmp_path / "cache.json").read_text())
        assert cache["tmdb_42"] == "vid1"

        second = StubClient()
        from boxcall_pipeline import build as build_module
        build_module.httpx.Client = lambda **kw: second  # type: ignore[assignment]
        self._run(tmp_path, second)
        assert not any("youtube/v3/search" in c for c in second.calls), \
            "a cached trailer id must not trigger another 100-unit search"

    def test_without_a_youtube_key_fields_are_null_not_zero(self, tmp_path, stub_httpx):
        self._run(tmp_path, stub_httpx, youtube_key="")
        signals = json.loads((tmp_path / "api" / "signals.json").read_text())
        entry = signals["signals"]["tmdb_42"]
        assert entry["youtubeViews7d"] is None
        assert entry["youtubeEngagementRate"] is None

    def test_falls_back_to_the_seed_when_tmdb_is_unconfigured(self, tmp_path, stub_httpx):
        seed = tmp_path / "seed.json"
        seed.write_text(json.dumps([
            {"id": "seed_a", "title": "Seeded Film", "releaseDate": "2026-12-01"}
        ]))
        manifest = self._run(tmp_path, stub_httpx, tmdb_key="")
        assert manifest["movieCount"] == 1
        assert manifest["sources"]["tmdb"] == "not configured"
        signals = json.loads((tmp_path / "api" / "signals.json").read_text())
        assert "seed_a" in signals["signals"]

    def test_actuals_json_is_written(self, tmp_path, stub_httpx):
        self._run(tmp_path, stub_httpx)
        actuals = json.loads((tmp_path / "api" / "actuals.json").read_text())
        assert actuals["version"] == 1
        assert "actuals" in actuals

    def test_manifest_reports_per_source_coverage(self, tmp_path, stub_httpx):
        manifest = self._run(tmp_path, stub_httpx)
        assert "bluesky" in manifest["sources"]
        assert "wikipedia" in manifest["sources"]
        assert "youtube" in manifest["sources"]
        assert "boxoffice" in manifest["sources"]
        assert manifest["generatedAt"].endswith("Z")
