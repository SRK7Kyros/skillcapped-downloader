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
