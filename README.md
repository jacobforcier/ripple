# Ripple

**Word of mouth, finally rewarded.**

Ripple turns the product links people already share with friends into a small
affiliate commission — no influencer account, no extra steps. You share a
product the way you normally would; Ripple quietly upgrades the link, and you
earn a small cut when someone buys through it. Every Ripple link shows a clear
disclosure to whoever clicks it.

The product spans a marketing site, a browser extension, native iOS/macOS apps
with share extensions, and a backend API.

---

## Repository layout

```
.
├── index.html              Landing page (sharewithripple.com)
├── s.html                  Ripple link redirect page (/s/[id]) — FTC disclosure + redirect
├── privacy.html            Privacy policy (/privacy)
├── vercel.json             Static-site routing (filesystem-first, then SPA fallback)
│
├── extension/              Chrome / Safari Web Extension (source of truth)
│   ├── manifest.json       Manifest V3
│   ├── content.js          Product detection + silent clipboard interception
│   ├── popup.js / .html    Toolbar popup — generate & copy a Ripple link
│   ├── background.js       Minimal MV3 service worker
│   └── icons/
│
├── Ripple/                 Xcode project — apps + Safari extension + share extensions
│   ├── Shared (App)/        Container-app screen (extension status) + assets
│   ├── Shared (Extension)/  Safari Web Extension handler (+ synced content.js)
│   ├── iOS (App)/           iOS app — SwiftUI experience lives in RippleUI/
│   ├── macOS (App)/         macOS container app
│   ├── iOS (Extension)/     Safari Web Extension target (iOS)
│   ├── macOS (Extension)/   Safari Web Extension target (macOS)
│   ├── Ripple Share/        iOS Share Extension
│   └── Ripple Share Mac/    macOS Share Extension
│
├── backend/                Node + Express + Supabase API
│   ├── src/                Routes, lib, server entry
│   ├── supabase/schema.sql Database schema
│   └── test/               Test suite (node --test)
│
└── scripts/
    └── generate_icons.py   Generates every icon size from one design
```

---

## How the pieces fit together

1. **Capture** — on a product page, the user generates a Ripple link one of
   three ways: the browser extension popup, the extension's silent clipboard
   interception (copy a product URL → it's swapped for a Ripple link), or the
   iOS/macOS system share sheet via the Share Extensions.
2. **Share** — the user sends the `sharewithripple.com/s/[id]` link however
   they normally would (group chat, Slack, text, email).
3. **Redirect** — a recipient clicks the link and lands on `s.html`: a branded
   interstitial showing the FTC disclosure, then a redirect to the
   affiliate-tracked retailer URL.
4. **Track** — the backend records the click and (once a sale clears the
   affiliate network) attributes a commission to the sharer.
5. **Earn** — the sharer sees their links, clicks, and pending/confirmed/paid
   earnings in the iOS app.

---

## Component status

| Component | State |
|---|---|
| Landing site | Live at sharewithripple.com (Vercel) |
| Browser extension | Built — runs in demo mode |
| iOS app | Built — SwiftUI, 5 tabs, demo mode; needs device QA |
| macOS app | Container app built; needs device QA |
| iOS / macOS Share Extensions | Built, targets wired, compile verified |
| Backend API | Scaffolded + unit-tested; not yet deployed |
| Affiliate network | Sovrn Commerce — application pending |

**Demo mode** means link generation produces a placeholder
`sharewithripple.com/s/[id]` without real affiliate tracking. Going live is
a small, well-marked set of swaps (below).

---

## Demo → production swap points

Each surface generates links through a single, clearly-commented function.
When the backend is deployed and the affiliate network is approved, swap these:

| File | Function | Becomes |
|---|---|---|
| `backend/src/lib/affiliate.js` | `generateAffiliateUrl()` | Real Sovrn API call |
| `extension/popup.js` | `generateRippleLink()` | `POST /v1/links` |
| `extension/content.js` | `generateRippleLink()` | `POST /v1/links` |
| `Ripple/Ripple Share/ShareViewController.swift` | `generateRippleLink()` | `POST /v1/links` |
| `Ripple/Ripple Share Mac/ShareViewController.swift` | `generateRippleLink()` | `POST /v1/links` |
| `s.html` | `resolveLink()` | `GET /v1/links/:id` |
| `Ripple/iOS (App)/RippleUI/RippleAPI.swift` | `MockRippleAPI` | `LiveRippleAPI` (one line in `RootView`) |

> Note: `extension/content.js` is the source of truth; a synced copy lives at
> `Ripple/Shared (Extension)/Resources/content.js`. Keep them in sync.

---

## Working on each piece

### Landing site
Plain static HTML/CSS. Deploy with `npx vercel --prod` from the repo root.

### Browser extension
Load `extension/` as an unpacked extension in Chrome, or build the Safari
targets in the Xcode project. After editing `extension/content.js`, copy it to
`Ripple/Shared (Extension)/Resources/content.js`.

### Apps & extensions (Xcode)
Open `Ripple/Ripple.xcodeproj`. Targets: `Ripple (iOS)`, `Ripple (macOS)`,
the two Safari extension targets, and the two Share Extension targets. The iOS
app's UI is SwiftUI under `iOS (App)/RippleUI/`.

### Backend
See `backend/README.md` — create a Supabase project, run `supabase/schema.sql`,
copy `.env.example` to `.env`, then `npm install && npm run dev`. Tests:
`npm test`.

### Icons
`python3 scripts/generate_icons.py` regenerates every icon size (app icons,
extension toolbar icons, container-app icon) from one design.
