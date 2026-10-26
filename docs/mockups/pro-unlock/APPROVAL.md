# Whistler Pro unlock: UI approval

- **Status:** Approved by Alex Suarez on Oct 26, 2026, exactly as shown in the screenshots below.
- **Build captured:** main at `8a5fd2d` (the PR #2 merge), iPhone 17 Pro Max simulator.
- **Staged states:** a local DEBUG hook set the $2.99 price and the free/Pro state, and the cap screen was triggered directly. The hook was never committed.

| File | Shows |
|---|---|
| 1-paywall.png | Pro paywall: features, the Unlock Pro button with the price from StoreKit, Restore, Redeem Code |
| 2-free-locked.png | Free main screen with locked Staff/Tab panels and lock badges on Copy tab, Share MIDI, Hum, Any |
| 3-recording-cap.png | Paywall shown when a free take hits 15 seconds |
| 4-header-menu.png | Header menu: Whistler Pro, Restore Purchases, Redeem Code |
| 5-pro-unlocked.png | Pro main screen, nothing locked |
| 6-redeem-code.png | Apple's Redeem Offer sheet |

Any future UI change to these screens needs a new mockup approval before code is written.
