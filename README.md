# SkillCapped Downloader

A local web app for browsing the [SkillCapped](https://www.skill-capped.com/lol/browse/all)
League of Legends library — courses, lessons and smurf commentaries — with bulk
selection and downloading. It compiles to a single executable: run it, and it
starts a server on `127.0.0.1` and opens your browser.

Everything downloaded lands in a `content/` folder **next to the executable**.

> **Personal use only.** This tool reads SkillCapped's public content API and its
> video CDN directly. It is not affiliated with SkillCapped, it does not bypass a
> paywall on any content that is not already served publicly, and it is intended
> for personal archival of material you already have access to. Respect their
> terms of service and your local law.

## Running it

1. Download the build for your platform (`dist/skillcapped-downloader-*.exe` / `-linux-*` / `-darwin-*`).
2. Run it. Your browser opens at `http://127.0.0.1:4780`.
3. Search or filter the catalogue, pick items, and press **Download**.

Files appear under `content/` beside the executable, so the folder travels with it:

```
content/
  Videos/<role>/<category>/<title> [<uuid>] <quality>.mp4
  Courses/<role>/<course>/<title> [<uuid>] <quality>.mp4
  Commentaries/<role>/<title> [<uuid>] <quality>.mp4
```

### ffmpeg

Segments are MPEG-TS. With **ffmpeg** available the download is remuxed to MP4
(`-c copy`, no re-encode) and verified before it is published. Without ffmpeg the
transport stream is kept as `.ts` under an honest name, so a missing ffmpeg costs
you a step, never a download.

ffmpeg is found in this order: `SKILLCAPPED_FFMPEG` → a `bin/` folder next to the
executable → your `PATH`. To ship one alongside the app, drop the binary in
`bin/` (that path is gitignored).

## Command line

| Flag | Default | Meaning |
| --- | --- | --- |
| `--port`, `-p` | `4780` | Port to serve on |
| `--host` | `127.0.0.1` | Bind address (loopback only, deliberately) |
| `--content-dir` | `<exe dir>/content` | Where downloads are written |
| `--quality`, `-q` | `2500` | Default rendition: `1500` (720p), `2500` (1080p), `4500` (2160p) |
| `--concurrency` | `3` | Simultaneous downloads (4K is serialised) |
| `--no-remux` | — | Keep raw `.ts` files |
| `--no-open` | — | Do not launch a browser |
| `--help`, `-h` | — | Usage |

Every flag has an environment equivalent (`PORT`, `HOST`, `SKILLCAPPED_CONTENT_DIR`,
`SKILLCAPPED_QUALITY`, `SKILLCAPPED_CONCURRENCY`, `SKILLCAPPED_REMUX`,
`SKILLCAPPED_NO_OPEN`). Flags win over the environment.

Running a second copy simply opens the first one's page: the port is claimed
first, and the newcomer recognises the API and hands off.

## How it works

SkillCapped publishes its catalogue as one static JSON dump whose URL is recorded
in a Firestore document, so the catalogue is discovered — not hardcoded:

1. `content-location/lol-content-location` (Firestore, no token needed) → the
   versioned dump URL.
2. The dump (`videos`, `commentaries`, `courses`, `tagInfo`, `videosToCourses`)
   is parsed tolerantly into one flat catalogue of ~6,450 items.
3. Each video is served as discrete MPEG-TS segments on CloudFront
   (`<uuid>/HIDDEN<quality>-<index>.ts`) with **no published playlist**, so the
   segment count is found by bracketing from the expected length and binary
   searching for the last one that answers `200`.
4. Segments are fetched in parallel, concatenated in order (each part is deleted
   as it is consumed, so peak disk use is one copy plus one segment), remuxed to
   MP4 and atomically renamed into place.
5. A failed remux keeps the `.ts` rather than a mislabelled file, and any error
   clears the job's scratch folder — a failure never leaves partial output in
   `content/`.

The preview player picks its source per video. A lesson that is already on disk
plays straight from the file through `/api/media/…`, which answers `Range:`
requests so the browser can seek — and because a lot of the catalogue is no
longer published upstream, that file is often the only copy left. Anything else
streams from the CDN through this server: the playlist is synthesised from the
same segment scheme the downloader uses (a live check that the download path is
correct) and every part is relayed by `/api/segment/…`, so the browser only ever
talks to one origin and a part the CDN refuses becomes a plain `404` instead of
an S3 error document.

The downloads panel reads as a queue, not a feed. One bar covers the whole queue
(every item counted by its own percentage, with the aggregate speed and the
bytes still to fetch turned into a single ETA), then the queue is split into
courses: a course is one collapsible line with its own bar, its lesson tally and
the name of the lesson currently downloading, and opening it shows each lesson's
part-by-part progress and its own controls. Downloads that belong to no course
stay one line each. Courses are grouped by the catalogue's course id, so a bulk
run reads as one thing rather than a dozen unrelated downloads.

Jobs persist across restarts (`content/.skillcapped/jobs.json`); a job that was
mid-flight when the app closed is marked `interrupted` and can be retried. The
`skip downloaded` option is on by default and consults the on-disk library.
Downloaded files are recognised by parsing their own names, so the library stays
correct even if you move files around inside `content/`.

The catalogue opens on **courses**, and there is no catch-all tab — the content
switch is Courses / Videos / Smurfs. A course card is a collapsed entry: its
border turns green as soon as any of its lessons is on disk, and a fully archived
course reads solid green with a `Complete` tag, so what you already have is
visible in the grid without filtering for it. Clicking the card opens its lessons
**beside itself**: the lesson panel grows out of the card's right edge and the
rest of the grid slides along to make room (motion.dev springs, switched off
entirely under `prefers-reduced-motion`). Opening a course grows **the card
itself**: its own actions — on-disk progress, select/clear, `N selected` and the
download button — expand into the bottom of the banner, under a hairline, so the
metadata lives with the card it describes and the strip beside it is nothing but
lessons. The panel is **exactly as wide as its cards ask for** — one column per
two lessons — and never wider than the room left in its row, so a two-lesson
course opens a narrow panel while a long one takes the rest of the row and
scrolls inside it (the cards that followed wrap to the next row). Where fewer
than three columns remain — a phone, or a card near the end of a row — it takes
the full row below instead. Beside the card it is also **exactly as tall as the
card it belongs to**, so opening one never stretches the grid's row, and the
lessons are an **n×2 strip** — two rows as tall as half the card, scrolling
sideways for the rest — so a chapter reads as a strip of videos rather than a
wall of rows. Every lesson card takes the width its 16:9 poster needs at that
height, so a thumbnail is **never cropped horizontally**; it carries the poster,
duration in the corner, on-disk tag, selection box and a preview button in its
title row (so the button cannot swallow the select click). Full-row panels
(phones and narrow windows) put the strip under the card at a readable height
rather than matching the card's. A
plain click anywhere on a card selects it, and the expanded card's button queues
whatever is selected, or else exactly the lessons still missing. The card's own
checkbox, a shift-click (the range) or a ctrl/⌘-click (that one card, no range)
still adds it to the bulk selection.

## Limits worth knowing

- **No posters for most of the library.** Roughly two thirds of the videos and all
  commentaries predate SkillCapped's poster migration, so the card's no-image
  state is the common case by design and shows the role plus the kind.
- **Cards take their media shape from the art, not a house ratio.** Course banners
  are 576×912 portrait cards with the title baked in, video stills are 1280×720,
  so each card's media box adopts the poster's own aspect ratio (a 2:3 or 16:9
  placeholder stands in until it loads) instead of cropping to 16:9. Every card
  reserves two title lines, so the cards in a row are exactly the same height
  whatever their titles say, and the grid aligns to the top.
- **Four courses have no published lessons.** Their cards say so and cannot be
  selected.
- Course titles contain role placeholders (`Wave Control {support}`); they are
  rendered as `Wave Control (Support)`, and the same substitution is applied to
  the course name attached to each lesson, so folders and titles agree.
- The download queue is in memory plus `jobs.json`; there is no scheduler.

## iOS app

`ios/` is the phone companion, and it both reads and writes. Point it at the
folder the downloader writes to — wherever it lives, iCloud Drive included — and
it becomes a browsable library with real cover art and native playback. The
folder is read in place: nothing is uploaded, nothing is copied, and a lesson
held only in iCloud is fetched the moment you play it. From **Discover** it also
reads the site's own catalogue, so a lesson or a whole course can be downloaded
on the phone itself, into the same folders the desktop build writes.

- **Discover.** `CatalogService` looks the dump's address up in Firestore (the
  site publishes it in a document it reads at runtime), fetches it, flattens
  `courses`, `videos` and `commentaries` into one row shape and caches the result
  for thirty minutes. The catalogue is browsable before a byte is on disk: covers
  come from the CDN, search is the same folded match the rest of the app uses, and
  the role chips filter. A course that is already here wears the console's green
  border, solid when it is complete.
- **Downloading.** `SegmentDownloader` fetches the HLS parts four at a time under
  one shared polite budget and merges them into one MPEG-TS file, which is what
  lands in the library — nothing is re-encoded, because iOS cannot demux a
  transport stream and the player reads it through the HLS stack instead (see
  **Playback**). Files land in `Courses/<role>/<course>/`,
  `Videos/<role>/<category>/` and `Commentaries/<role>/` under the desktop's
  `<title> [<uuid>] <quality>.<ext>` name — `.ts` from the phone, `.mp4` from the
  desktop — so a phone download and a desktop download of the same course merge
  instead of duplicating. One lesson runs at a time so the phone stays
  responsive, and the queue is persisted: a relaunch resumes it.
- **Quality.** The order in `Settings` is the fallback ladder — 1080p, then 720p,
  then 4K by default — and the first rendition the CDN actually publishes wins.
  A label is understood in both vocabularies, the file-name one (`2160p`) and the
  name the app shows (`4K`). `QualityPlanTests` pins the ladder, the pick and the
  spelling the CDN gets back.
- **Continue watching.** Every position is remembered against the catalogue id,
  so it survives a re-download or a move between folders, and the browse screen
  leads with the lessons left unfinished.
- **Where it writes.** Downloads land in the library folder the app is pointed
  at, so the browser finds them immediately; with no folder chosen they go to the
  app's own Documents folder, which is the same place the desktop library lands
  when you use **On My iPhone › SkillCapped Local**.
- **What it reads.** `<title> [<uuid>] <quality>.<ext>` under
  `Courses/<role>/<course>/`, `Videos/<role>/<category>/` and
  `Commentaries/<role>/`, exactly as `src/core/naming.ts` writes them, joined to
  `.skillcapped/catalog.json` for titles, durations and the order a course lists
  its lessons in. Both containers are playable — an `.mp4` from the desktop and a
  `.ts` from this app (and a `.ts` copied in by hand). Without that catalogue file
  the folders still group a course, and a video copied in by hand keeps its own
  name — its id comes from the uuid in the filename, so a lesson scanned before
  the catalogue loaded still remembers where you stopped and still matches a
  download made on this phone.
- **Cover art.** A frame pulled out of each lesson (`AVAssetImageGenerator`), a
  little way in, cached under `Caches/posters`. Only the containers this platform
  can read yield one: an `.mp4` from the desktop does, a downloaded `.ts` does
  not — the player reads a transport stream through the HLS stack, and an HLS
  asset reports **no tracks**, so the generator has nothing to decode and never
  answers (measured; the same stream plays). A `.ts` is therefore not asked for a
  frame at all, and every other request is raced against a budget, because a
  generator that never returns would otherwise leave a card waiting forever. A
  file that yields no frame falls back to a gradient seeded from its title, so a
  card never looks broken.
- **Playback.** `AVPlayerViewController`, so picture in picture, AirPlay and
  subtitle tracks come for free; the position of every file is remembered and
  resumed above five seconds. A downloaded `.ts` is played by handing the player
  a **one-segment `#EXTM3U` playlist** (`Support/StreamAsset.swift`): the file is
  its own only segment, its duration comes from the catalogue (or a placeholder
  when unknown), and its bytes are served to `AVAssetResourceLoader` straight
  from disk — no server, no conversion, nothing copied. AVFoundation seeks
  through that loader by byte range, so scrubbing works on a merged file too.
- **Folder access.** `Choose a folder…` opens the system picker, so iCloud Drive,
  On My iPad and another app's folder all work; the pick becomes a security-scoped
  bookmark and the next launch reopens it. Two things refuse it otherwise, and
  both are reported instead of crashing. UIKit raises an **Objective-C exception
  from the picker's initializer**, which Swift cannot catch, so the call lives in
  `Support/PickerProbe.m`. And on iOS 26 and later a **folder-only** type array is
  refused outright with `folder import is not supported, use asCopy:false` — raised
  even though the call already passes `asCopy:NO`, so the hint names nothing that
  can be satisfied. Asking for `.folder` *beside* `UTTypeItem` avoids that path
  (LiveContainer's guest-app shim rewrites every request to
  `[UTTypeItem, UTTypeFolder]`; KartPad's working picker asks for
  `[UTTypeItem, UTTypeData, UTTypeDiskImage, UTTypeFolder]`), and the folder still
  comes back in place because `asCopy` stays `NO`. The probe walks a ladder — item
  + folder with multiple selection (a folder is selectable only while multi-select
  is on, now that the folder-only presentation is refused), the same single-select,
  item + data + folder, folder only, folder copy-in — and uses the first rung the
  running iOS accepts. The
  **Picker diagnostics** section in the sheet lists every rung with the exact UIKit
  sentence for the ones refused, so a device that refuses them all says so in a
  screenshot. No entitlements are shipped: an earlier build declared an iCloud
  container, but the refusal was never about iCloud, and a container cannot be
  granted to a sideloaded signature anyway. Each attempt also points the picker at
  the app's Documents folder, since left on its default root it opens on
  "Recents / No Recents" with Open disabled. `FolderPickerTests` builds it on every
  run, pins that starting folder and pins the ladder's first rung as item + folder
  with multiple selection (`FolderPickerUITests` drives the real button and insists
  the system picker appears — it does in the simulator, screenshot attached to the
  run). A refusal
  names the iOS version and build it came from, so a device-side refusal diagnoses
  itself. The fallback is unchanged: with `UIFileSharingEnabled` the app's own
  Documents folder is visible as **On My iPhone › SkillCapped Local**, and
  `LibraryLocator` lists every folder in there holding `Courses`, `Videos` or
  `Commentaries`. A single candidate is adopted on launch, several are offered in
  the `Library folder` sheet. Picking a folder that merely *contains* the library
  (iCloud Drive's root, a Downloads folder) adopts the only library one level down
  (`ExternalFolderTests` pins both, and that the bookmark survives a relaunch).
  `Settings` reports what was scanned, how large it is and whether it lives in
  iCloud.
- **Cloud files.** A pick does not download anything — a listing and a file size
  are metadata. A lesson whose bytes are only in iCloud can be listed as its
  hidden shadow file (`.Name [id] 1080p.mp4.icloud`): it is shown at the name it
  restores to, marked as needing a download, and listed once — never beside a
  downloaded copy. `AVPlayer` cannot open a placeholder, so playback asks iCloud
  for it (`CloudFile`) and shows `Downloading from iCloud…` until it lands; a
  poster that cannot be generated falls back to the gradient.
- **Build.** XcodeGen generates the project from `ios/project.yml`
  (`brew install xcodegen && cd ios && xcodegen generate`). iPhone and iPad,
  iOS 17+. `.github/workflows/ios.yml` runs the unit and UI suites on a
  simulator and publishes an unsigned IPA artifact; the sideloader (Feather,
  AltStore) applies its own signing profile. The app declares no entitlements. The
  marketing version comes from `ios/project.yml` `MARKETING_VERSION` — the
  workflow reads it whenever its dispatch input is blank, so a bump is one edit.

## Development

```bash
bun install
bun run dev:web          # Vite dev server on :5179, proxying /api to :4780
bun run start --no-open  # the server on :4780
```

| Script | What it does |
| --- | --- |
| `bun run dev:web` | Vite dev server with HMR for the UI |
| `bun run build:web` | Build the UI to one self-contained HTML and embed it in the server |
| `bun run build:exe` | Compile the executable (pass targets, or `--all`) |
| `bun run build` | `build:web` then `build:exe` |
| `bun test` | Unit suite (naming, CDN maths, segment probing, catalogue, flags, search, course lessons) |
| `bun run test:e2e` | Playwright browse suite (renders the real app) |
| `bun run test:live` | Opt-in end-to-end run that really downloads (`LIVE=1`) |
| `bun run typecheck` | TypeScript for both the server and the UI |

The UI is React 19 + Vite + Tailwind v4 + Radix, and the design language is shared
with [mirrorr](https://github.com/SRK7Kyros/mirrorr): the same token file drives
it, and `content/.skillcapped/` holds the cache, scratch space and job list. The
whole UI compiles into one HTML document that is embedded in the binary, so the
executable has no sidecar assets at all. That embedded copy
(`src/server/web.html`) is committed, and the repo is LF-only (`.gitattributes`),
so a Windows checkout cannot regenerate it with CRLF line endings and leave the
tree permanently dirty.

### Releases

`.github/workflows/release.yml` is manual (`Actions → Release → Run workflow`).
It typechecks, runs the unit suite, then compiles **linux-x64** and **windows-x64**
on `ubuntu-latest` (Bun cross-compiles, so no Windows runner is involved; the
x64 Linux binary is smoke-tested by booting it and waiting for `/health` before
anything is published), and finally creates — or re-uploads onto — the `v<version>`
release with both binaries and `SHA256SUMS.txt`. The `version` input defaults to
`package.json`, and `prerelease` marks the run as a pre-release. Assets are
replaced with `--clobber`, so re-running a version is safe.
