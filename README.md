# Cinema Showcase for info-beamer

## Display rotation

Choose **Display rotation** in the info-beamer setup to rotate the complete output clockwise by 0°, 90°, 180°, or 270°. The setting uses info-beamer's native screen transform, and the Hosted device preview follows the selected orientation.

For 90° and 270° rotation, Cinema Showcase swaps the logical canvas dimensions before laying out content. A 1920×1080 HDMI output therefore uses a 1080×1920 portrait canvas, keeping posters, embedded playlist media, QR codes, and the offline indicator centered in the visible output.

## Portrait renderer fix

The renderer now uses documented info-beamer colored textures instead of unsupported gl.color/gl.rect calls. Movie slides use the approved portrait composition: poster above a compact status footer, with the ticket caption and QR fully inside the footer. Showtimes, auditorium and repeated movie titles are omitted when artwork is available. Missing artwork displays the movie title and "Poster unavailable"; startup without a catalog displays "Waiting for schedule content".

Local verification: 15 tests including Lua 5.1 rendering smoke tests (requires the development-only Python lupa package). The smoke tests reproduce the old drawing-call failure and exercise missing/loaded posters, ticket-caption position, and offline-indicator recovery. Actual info-beamer device playback remains to be verified.

## Local poster sharing and offline indicator

Enable **Share posters over local network** and enter nearby Cinema Showcase devices' private IPv4 addresses, separated by commas. Use DHCP reservations. Devices must belong to the same info-beamer account and allow TCP 18742 between them. Discovery is manual and separate from info-beamer's built-in asset P2P setting. Run one Cinema Showcase service per device on this port.

Downloads check the local file first, then up to eight configured peers, then the source image server. Poster filenames hash the exact source URL to distinguish artwork revisions. An unchanged URL is downloaded only once per device and reused for offline playback. Requests and response bodies are authenticated with the info-beamer account secret; credentials and schedules are never served. Transfers use authenticated HTTP, not encryption. Without the account secret, normal internet downloads continue. Uncached metadata or artwork still requires internet.

The menu package's offline-logo.png appears at bottom left when a schedule refresh fails, including over child packages, and disappears after a successful refresh. It indicates unavailable/stale feed data rather than independently testing internet access. Detection follows the refresh interval and retry backoff. Cached playback continues.

Cinema Showcase promotes current and upcoming movies using the venue's INDY schedule, INDY artwork, Campaign Manager entries, ticket QR codes, and content from embedded info-beamer playlists.

## Installation

Import this directory into info-beamer Hosted as a package, then create a setup from it. Configure the INDY site ID. Enter the Lovable endpoint in **Campaign Manager feed URL** to add manually curated Coming Soon movies. No TMDB token is required for movies supplied by INDY or Campaign Manager. Choose a native info-beamer playlist in **Primary info-beamer playlist** to interleave its media with movie slides.

The package service is compatible with the Python 2.7 runtime used by current info-beamer Hosted OS packages and with Python 3 for local testing. It is intentionally unprivileged and requests only the info-beamer `network` permission.

## INDY schedule feed

The default endpoint is INDY's `upcoming_showings.xml` TMS feed. Set the numeric INDY site ID for the venue; Palmyra is site `352`. `sample-upcoming-showings.xml` demonstrates the consumed fields. The service groups performances by INDY feature ID and retains title, runtime, rating, screen, first performance date, and today's showtimes.

Classification uses `first_show_date`, `start_date`, `release_date`, or `opens`, in that order. Dates on or before today are **Now Showing**, tomorrow is **Starts Tomorrow**, and later dates are **Coming Soon**. If a feed supplies dated performance objects, the earliest performance date is used automatically.

When **Catch It on the Big Screen enabled** is on, the callout is evaluated only on Tuesdays. A current movie receives **CATCH IT ON THE BIG SCREEN NOW!** when it has no performance scheduled from the upcoming Friday onward, but at least one other movie does. Requiring another Friday-or-later movie confirms that INDY has published the new weekend schedule. On every other day, current films remain labeled **NOW SHOWING**.

## Campaign Manager roster

Coming Soon movies are managed in Lovable and returned by the configured JSON endpoint. The package requests `site_id`, `orientation`, and `channel=cinema_showcase`. It accepts a top-level `campaigns` array matching `sample-campaign-feed.json`. Entries can target all locations or list the matching INDY site ID in `location_ids`.

In **Auto** artwork mode, display rotations 90° and 270° request `vertical` and use `vertical_image_url`; rotations 0° and 180° request `horizontal` and use `horizontal_image_url`. The opposite variant is only a fallback when the requested one is absent. Campaigns are static images only. `active_from` and `active_until` control campaign availability, while `release_date` controls the **Now Showing**, **Starts Tomorrow**, or **Coming Soon** label.

The feed may require an optional Bearer token. Keep image URLs stable for the life of an artwork revision. When artwork changes, publish a new versioned URL such as `vertical-v2.jpg`; this gives the device reliable download-once caching without serving stale artwork.

## Ticket QR codes

Every movie with an upcoming INDY performance is considered on sale. The service uses each XML feature ID to query INDY's public GraphQL endpoint for the movie's authoritative `urlSlug`. Its QR code points to the circuit-wide route `https://flagshipcinemas.com/movie/{url-slug}/`, without a location name, allowing the destination page to offer all participating locations. If the slug lookup is temporarily unavailable, a title-based slug is used as an offline fallback.

Campaign Manager movies display a QR only when **On sale** is enabled. The full circuit-wide `movie_url` takes priority; otherwise the configured slug and ticket base URL are used.

For production, INDY is the schedule, ticket slug, and primary artwork authority for scheduled films. Campaign Manager supplies manually curated Coming Soon artwork and URLs. TMDB remains only an optional last-resort artwork fallback.

## Embedded info-beamer playlist

Choose an existing Hosted playlist with the **Primary info-beamer playlist** picker. Use **Additional info-beamer playlists** to add any number of other Hosted playlists. Their active items are combined round-robin, preserving the order within each source playlist, then interleaved with the poster roster. This prevents a large playlist from crowding out smaller ones.

Hosted expands each selection into its images, videos, durations, and schedules, matching the playlist mechanism used by info-beamer's HDv2 player. Cinema Showcase keeps the configured playback durations. Video audio is disabled by default and can be enabled with **Playlist video audio**. Create and maintain the source playlists in the account's **Playlists** section; no nested child packages are required.

**Playlist media scaling** defaults to **Fit and center**. The complete image or video is proportionally scaled into the display and centered, with black letterboxing where its aspect ratio differs from the screen. **Fill screen (crop)** is available when edge-to-edge playback is preferred.

After importing this version, update the package used by the setup before looking for the selector; older imported package revisions do not gain new configuration fields automatically.

## INDY posters and optional TMDB fallback

Cinema Showcase queries INDY's public movie details using each schedule feature ID. The returned `posterImage` is downloaded from INDY's signage image CDN at a portrait-friendly resolution and cached locally for offline playback. Nearby Cinema Showcase devices can share these cached files using the package's peer-download feature.

TMDB is not contacted when INDY or Campaign Manager supplies artwork. A TMDB read token can still be configured to fill artwork gaps.

## TMDB terms

Commercial cinema use may require a TMDB commercial agreement. Include the approved TMDB logo and this notice in your operator-facing About/Credits material:

> This product uses the TMDB API but is not endorsed or certified by TMDB.

## Reliability

Posters, campaign artwork, QR codes, and TMDB search matches are cached. Content stops playing as soon as it leaves the active catalog, but its local file is retained for two days after it was last active before deletion. This limits repeat downloads when a campaign briefly disappears while reclaiming space from genuinely expired content. The last valid catalog stays on screen when refreshes fail. Network errors retry with exponential backoff. Keep the feed on HTTPS and avoid placing credentials in its URL.
