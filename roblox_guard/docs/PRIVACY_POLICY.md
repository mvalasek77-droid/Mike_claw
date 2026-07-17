# RobloxGuard Privacy Policy (DRAFT)

> **This is a draft, not legal advice.** It is written to accurately describe
> what the current codebase actually collects and stores (cross-checked
> against `backend/app/db.py`, `evidence.py`, and `main.py`), so it should be
> directionally correct — but have counsel review it before publishing, and
> update the effective date and contact details before it goes live. This
> must be hosted at a stable URL matching what you enter as the "Privacy
> Policy URL" in App Store Connect's App Privacy section, and linked from
> `PaywallView.swift`'s `privacyPolicyURL` constant.

**Effective date:** [fill in before publishing]

## Who this is for

RobloxGuard is used by **parents and legal guardians**, not children. The
child never installs or logs into the app. This policy describes what we
collect from the parent using the app and, necessarily, a limited amount of
information about the linked child's public Roblox account.

## What we collect

| Data | Why | Linked to you |
|---|---|---|
| Your name | Recorded as the parental consent attestation (who confirmed they are the parent/guardian) | Yes |
| Your child's public Roblox username, display name, and Roblox account ID | To monitor the account's public footprint | Yes |
| Public friend-list changes, account-age signals, and presence/activity timestamps for the linked account | Core detection functionality | Yes |
| Generated safety alerts and your feedback on them (confirmed/dismissed) | To show you alerts and tune future ones | Yes |
| Evidence you upload (screenshots) and automatically captured public profile screenshots | To preserve what was observed if you need to report something | Yes |
| Bug reports you submit (description, optional reply email) | To fix problems you report | Yes, if you provide contact info |
| Device push-notification token and platform (e.g. "ios") | To deliver real-time alerts to your device via Apple Push Notification service (APNs) | No (not linked to your identity) |
| Subscription status | Apple's StoreKit tells us which plan is active; App Store handles all payment details — **we never see your card number** | Yes |

We do **not** collect: your child's Roblox password (there is no password
field anywhere in the app), private chat content (no outside app can access
Roblox private messages — see the app's "What this app can't do" onboarding
screen), your location, your device's advertising identifier, or health,
financial, or biometric data.

## What we don't do

- **No third-party analytics or advertising SDKs.** Nothing here is shared
  with ad networks or data brokers, and RobloxGuard does not track you across
  other companies' apps or websites.
- **No selling of data**, ever, to anyone, for any purpose.
- **No reading of private Roblox chats.** Detection runs entirely on
  Roblox's public, unauthenticated web APIs.

## How long we keep it

Data for a linked child is retained for as long as the account stays linked.
Unlinking a child from Settings **permanently and immediately deletes**
everything associated with that child — alerts, evidence, screenshots, and
snapshot history — from our database. Device push-notification tokens are
retained until the app unregisters them or Apple reports the token as
expired; they are automatically pruned when delivery fails.

## Who can see it

Only you, as the linked account's parent/guardian. Backend access is
restricted to the operator via a bearer-token API key; there is no admin
dashboard exposing your data to anyone else. If you submit a bug report, that
report (and any contact email you provide) is visible to the developer for
the purpose of fixing the issue.

## Your rights

You can request deletion at any time by unlinking the child's account in the
app, which erases all associated data immediately. If you have questions
about your data, contact us at [support email — see Settings → Support].

## Children's privacy (COPPA)

RobloxGuard is not directed at children and is not available in Apple's Kids
Category — it is installed and operated exclusively by the parent/guardian.
Information about a linked child is limited to what's necessary for the
service (public username, derived safety signals) and is provided under the
parent's own consent, recorded at the time the account is linked.

## Changes to this policy

If this policy changes materially, we'll update the effective date above.
