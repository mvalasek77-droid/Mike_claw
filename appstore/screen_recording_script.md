# App Review screen recording — shot list

Apple wants one continuous recording on a **physical iPhone on the latest iOS**,
starting from tapping the app icon. Total length: about 3–4 minutes.

## Plan the week (the settled trade needs a Sunday)

A trade only settles after its film's opening weekend is reported on Sunday, so
record in two sessions:

| When | What |
|---|---|
| Any day before the film's opening day | **Session A**: steps 1–8 and 10–14, which includes buying the trade that settles |
| Sunday after about 3 PM ET (or any later day) | **Session B**: step 9, showing that trade settled with its payout |

Example for this week: films opening Fri Oct 9 include *The Social Reckoning*
and *Avatar Aang: The Last Airbender*. Trading on them locks at midnight
Thursday night, so buy in Session A by **Thu Oct 8**. Results arrive Sunday
Oct 11, so record Session B that evening or later.

Join the two clips in the Photos app (or iMovie) and **don't cut anything from
steps 1–3**: Apple wants to see the launch.

## Before Session A

1. Install the exact TestFlight build you're submitting.
2. Delete any old copy of BoxCall so the recording starts at the age check.
3. Settings › App Store › Sandbox Account: sign in with a sandbox tester
   (create one in App Store Connect › Users and Access › Sandbox).
4. Settings › General › Background App Refresh: on, and on for BoxCall.
5. Settings › Control Center: add Screen Recording. Turn on Do Not Disturb.
6. Charge the phone and close other apps.

## Session A

| # | Screen | What to do | Proves |
|---|---|---|---|
| 1 | Home screen | Start the recording, then tap the BoxCall icon | Recording starts at launch |
| 2 | Age check | Enter a birth year (13+), tap Confirm | 13+ age gate |
| 3 | App tour | Swipe slowly through all 9 pages, tap **Start trading** | Purpose, play money only |
| 4 | Now Showing | Scroll the list, tap a film opening this Friday | Browsing real films |
| 5 | Movie detail | Pick **BIGGER**, tap a strike, read the first-time explainer, set quantity 2, tap **Buy** | Buying a Call |
| 6 | Movie detail | Switch to **SMALLER**, buy a Put on another strike | Buying a Put |
| 7 | Positions | Show both trades and live P&L, then tap **Close** on the Put | Managing trades |
| 8 | Force-quit and reopen | Swipe BoxCall away, reopen it, go to Positions: the Call is still there | Trades are saved |
| 10 | Box Office, then Marquee | Scroll the profit leaderboard (rivals are marked SIM), then show the Featured critics spotlight on Marquee | Leaderboard, review spotlight |
| 11 | Marquee | On another trader's post open the ••• menu: show Report, Block, Not interested; report one post. Open a comment and show the same menu | User content moderation |
| 12 | Profile › Upgrade | Show the paywall, buy **Backstage** with the sandbox account, show the ticket badge next to your name and the limit-order count rising to 3 (coins stay the same), then tap **Restore purchases** | Paid content |
| 13 | Profile | Tap **Sign in with Apple**, complete it, show "Signed in with Apple" | Login |

Stop the recording here. **Don't do step 14 yet**: deleting the account would
also delete the Call you need for Session B.

## Session B (Sunday afternoon or later)

| # | Screen | What to do | Proves |
|---|---|---|---|
| 9 | Positions | Open BoxCall, show the settled Call with the opening figure and its payout (and the payout notification, if it arrived) | Automatic settlement |
| 14 | Profile | Tap **Delete account and data** › **Delete**. The app returns to the age check | Account deletion |

## After recording

- Join Session A, then Session B. Trim dead time, but don't cut between steps 1 and 3.
- Keep the file under 500 MB: AirDrop it to a Mac and export at 1080p if needed.
- Reply to Apple's message in App Store Connect: paste `review_notes.txt` and attach the video.
- Paste the same text into App Store Connect › your version › App Review Information › Notes.
