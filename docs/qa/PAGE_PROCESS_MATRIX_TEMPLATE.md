# Page Process Matrix Template

Copy this file to `docs/qa/PAGE_PROCESS_MATRIX.md` for each build or release
candidate. Every row must end with evidence before the release can be marked
green.

| ID | Surface | State | User Action | Expected Result | Owner Agent | Evidence | Status |
| --- | --- | --- | --- | --- | --- | --- | --- |
| HOME-001 | Home | Fresh install complete | Tap Try a sample | Sample picker opens; no auth or payment required | UI Tester | screenshot:path or test:name | not tested |
| BUILD-001 | Builder | Missing API key, BYOK selected | Tap Build it | Button is disabled or shows clear setup message | UI Tester | screenshot:path or test:name | not tested |
| SETTINGS-001 | Settings pricing | Hosted selected, no StoreKit products | Tap hosted plan | User sees unavailable state; free quota still visible | Reviewer | screenshot:path or test:name | not tested |
| RELEASE-001 | Submit to App Store | No Apple credentials | Tap Submit | Apple Developer setup opens; no fake upload begins | Security Auditor | screenshot:path or test:name | not tested |

## Coverage Summary

- Total rows:
- Passed rows:
- Blocked rows:
- Untested rows:
- Light mode screenshots:
- Dark mode screenshots:
- AX5 Dynamic Type pass:
- Reduce Motion pass:
- VoiceOver pass:
- Final Reviewer model:
- Final Security model:
- Final gate: blocked
