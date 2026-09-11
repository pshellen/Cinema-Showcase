# Cinema Showcase for info-beamer

## Display rotation

Choose **Display rotation** in the info-beamer setup to rotate the complete output clockwise by 0°, 90°, 180°, or 270°. The setting uses info-beamer's native screen transform, and the Hosted device preview follows the selected orientation.

## Portrait renderer fix

The renderer now uses documented info-beamer colored textures instead of unsupported gl.color/gl.rect calls. Movie slides use the approved portrait composition: poster above a compact status footer, with the ticket caption and QR fully inside the footer. Showtimes, auditorium and repeated movie titles are omitted when artwork is available. Missing artwork displays the movie title and "Poster unavailable"; startup without a catalog displays "Waiting for schedule content".

Local verification: 15 tests including Lua 5.1 rendering smoke tests (requires the development-only Python lupa package). The smoke tests reproduce the old drawing-call failure and exercise missing/loaded posters, ticket-caption position, and offline-indicator recovery. Actual info-beamer device playback remains to be verified.

## Local poster sharing and offline indicator

Enable **Share posters over local network** and enter nearby Cinema Showcase devices' private IPv4 addresses, separated by commas. Use DHCP reservations. Devices must belong to the same info-beamer account and allow TCP 18742 between them. Discovery is manual and separate from info-beamer's built-in asset P2P setting. Run one Cinema Showcase service per device on this port.

Downloads check the local file first, then up to eight configured peers, then TMDB. Poster filenames hash the exact source URL to distinguish artwork revisions. Requests and response bodies are authenticated with the info-beamer account secret; credentials and schedules are never served. Transfers use authenticated HTTP, not encryption. Without the account secret, normal internet downloads continue. Uncached TMDB metadata still requires internet.

The menu package's offline-logo.png appears at bottom left when a schedule refresh fails, including over child packages, and disappears after a successful refresh. It indicates unavailable/stale feed data rather than independently testing internet access. Detection follows the refresh interval and retry backoff. Cached playback continues.

Cinema Showcase promotes current and upcoming movies using the venue's INDY schedule, TMDB posters, ticket QR codes, a manual movie roster, and content from an embedded info-beamer playlist.

## Installation

Import this directory into info-beamer Hosted as a package, then create a setup from it. Configure the INDY site ID and TMDB API read token. Choose a native info-beamer playlist in **Info-beamer playlist** to interleave its media with movie slides.

The package service is compatible with the Python 2.7 runtime used by current info-beamer Hosted OS packages and with Python 3 for local testing. It is intentionally unprivileged and requests only the info-beamer `network` permission.

## INDY schedule feed

The default endpoint is INDY's `upcoming_showings.xml` TMS feed. Set the numeric INDY site ID for the venue; Palmyra is site `352`. `sample-upcoming-showings.xml` demonstrates the consumed fields. The service groups performances by INDY feature ID and retains title, runtime, rating, screen, first performance date, and today's showtimes.

Classification uses `first_show_date`, `start_date`, `release_date`, or `opens`, in that order. Dates on or before today are **Now Showing**, tomorrow is **Starts Tomorrow**, and later dates are **Coming Soon**. If a feed supplies dated performance objects, the earliest performance date is used automatically.

## Manual roster

Use **Manual movie roster** in Hosted to enter a movie title and `YYYY-MM-DD` start/release date. Manual records are merged with INDY titles by normalized title, so they can fill gaps or override the release date, rating, and TMDB ID without duplicating a film. Use the optional TMDB ID when title search selects the wrong version.

## Ticket QR codes

Every movie with an upcoming INDY performance is considered on sale. Its QR code points to the circuit-wide route `https://flagshipcinemas.com/movie/{url-slug}/`, without a location name, allowing the destination page to offer all participating locations. Manual movies display a QR only when **On sale** is enabled. Their slug can be entered explicitly, and a full ticket URL override is available for exceptional routes.

For production, use the cinema POS/TMS/booking system as the schedule authority. TMDB is used only to enrich those records with metadata and poster art.

## Embedded info-beamer playlist

Choose an existing Hosted playlist with the **Primary info-beamer playlist** picker. Use **Additional info-beamer playlists** to add any number of other Hosted playlists. Their active items are combined round-robin, preserving the order within each source playlist, then interleaved with the poster roster. This prevents a large playlist from crowding out smaller ones.

Hosted expands each selection into its images, videos, durations, and schedules, matching the playlist mechanism used by info-beamer's HDv2 player. Cinema Showcase keeps the configured playback durations. Video audio is disabled by default and can be enabled with **Playlist video audio**. Create and maintain the source playlists in the account's **Playlists** section; no nested child packages are required.

**Playlist media scaling** defaults to **Fit and center**. The complete image or video is proportionally scaled into the display and centered, with black letterboxing where its aspect ratio differs from the screen. **Fill screen (crop)** is available when edge-to-edge playback is preferred.

After importing this version, update the package used by the setup before looking for the selector; older imported package revisions do not gain new configuration fields automatically.

## TMDB terms

Commercial cinema use may require a TMDB commercial agreement. Include the approved TMDB logo and this notice in your operator-facing About/Credits material:

> This product uses the TMDB API but is not endorsed or certified by TMDB.

## Reliability

Posters and TMDB search matches are cached. The last valid catalog stays on screen when refreshes fail. Network errors retry with exponential backoff. Keep the feed on HTTPS and avoid placing credentials in its URL.
