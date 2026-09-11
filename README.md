# Cinema Showcase for info-beamer

## Local poster sharing and offline indicator

Enable **Share posters over local network** and enter nearby Cinema Showcase devices' private IPv4 addresses, separated by commas. Use DHCP reservations. Devices must belong to the same info-beamer account and allow TCP 18742 between them. Discovery is manual and separate from info-beamer's built-in asset P2P setting. Run one Cinema Showcase service per device on this port.

Downloads check the local file first, then up to eight configured peers, then TMDB. Poster filenames hash the exact source URL to distinguish artwork revisions. Requests and response bodies are authenticated with the info-beamer account secret; credentials and schedules are never served. Transfers use authenticated HTTP, not encryption. Without the account secret, normal internet downloads continue. Uncached TMDB metadata still requires internet.

The menu package's offline-logo.png appears at bottom left when a schedule refresh fails, including over child packages, and disappears after a successful refresh. It indicates unavailable/stale feed data rather than independently testing internet access. Detection follows the refresh interval and retry backoff. Cached playback continues.

Cinema Showcase promotes current and upcoming movies using the venue's INDY schedule, TMDB posters, ticket QR codes, a manual movie roster, and content from attached info-beamer packages.

## Installation

Import this directory into info-beamer Hosted as a package, then create a setup from it. Configure the INDY site ID and TMDB API read token. Attach any other info-beamer packages beneath Cinema Showcase; they are discovered automatically and interleaved with movie slides.

The package service is compatible with the Python 2.7 runtime used by current info-beamer Hosted OS packages and with Python 3 for local testing. It is intentionally unprivileged and requests only the info-beamer `network` permission.

## INDY schedule feed

The default endpoint is INDY's `upcoming_showings.xml` TMS feed. Set the numeric INDY site ID for the venue; Palmyra is site `352`. `sample-upcoming-showings.xml` demonstrates the consumed fields. The service groups performances by INDY feature ID and retains title, runtime, rating, screen, first performance date, and today's showtimes.

Classification uses `first_show_date`, `start_date`, `release_date`, or `opens`, in that order. Dates on or before today are **Now Showing**, tomorrow is **Starts Tomorrow**, and later dates are **Coming Soon**. If a feed supplies dated performance objects, the earliest performance date is used automatically.

## Manual roster

Use **Manual movie roster** in Hosted to enter a movie title and `YYYY-MM-DD` start/release date. Manual records are merged with INDY titles by normalized title, so they can fill gaps or override the release date, rating, and TMDB ID without duplicating a film. Use the optional TMDB ID when title search selects the wrong version.

## Ticket QR codes

Every movie with an upcoming INDY performance is considered on sale. Its QR code points to the circuit-wide route `https://flagshipcinemas.com/movie/{url-slug}/`, without a location name, allowing the destination page to offer all participating locations. Manual movies display a QR only when **On sale** is enabled. Their slug can be entered explicitly, and a full ticket URL override is available for exceptional routes.

For production, use the cinema POS/TMS/booking system as the schedule authority. TMDB is used only to enrich those records with metadata and poster art.

## Child packages

Add packages as children of Cinema Showcase in the setup editor. All direct children are sorted by node name and mixed evenly between movie slides. Child packages should render correctly when called through `resource.render_child()` and should not assume they permanently own the screen.

## TMDB terms

Commercial cinema use may require a TMDB commercial agreement. Include the approved TMDB logo and this notice in your operator-facing About/Credits material:

> This product uses the TMDB API but is not endorsed or certified by TMDB.

## Reliability

Posters and TMDB search matches are cached. The last valid catalog stays on screen when refreshes fail. Network errors retry with exponential backoff. Keep the feed on HTTPS and avoid placing credentials in its URL.
