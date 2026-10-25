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
   (`<uuid>/HIDDEN<quality>-<index>.ts`) beside a per-rendition manifest
   (`<uuid>/HIDDEN<quality>.m3u8`). The manifest is the authority on where the
   video ends: the distribution also keeps `200`-answering parts from an older,
   longer encode behind its last entry, so a tail found by probing appends
   footage that is not part of the video (measured: a 122-second lesson arriving
   as 400 seconds, with the stale stretch carrying content from a different
   edit). Only a video that publishes no manifest — about 2.5% of the catalogue
   — is bracketed from the expected length and binary-searched for the last part
   that answers `200`.
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
- **Cards are drawn at one window, not at whatever shape the art arrived in.**
  Course banners are 576×912 portrait cards with the title baked in, video stills
  are 1280×720, so each grid picks the shape its cards are designed around
  (`posterRatio` in `web/src/lib/media.ts`) and every media box is that shape. A
  poster that is a little taller loses its **bottom** — anchored at the top, so
  the title baked into the top always survives — and a wider one is trimmed at
  the sides. The box therefore never grows with its picture: the cards in a row
  are exactly the same height and nothing reflows when the art finishes loading.
  Every card also reserves two title lines, whatever its title says, and the grid
  aligns to the top.
- **The course window is 576×806, not 576×912.** The site prints a pure-black
  strip along the bottom of its course cards — 9.9–10.9% of the height, measured
  across the catalogue: 8 of 18 sampled posters have it, and every card in the
  Discover grid at the time of the fix had it. That strip is the band
  SkillCapped's own site prints its title onto; this app prints the title *under*
  the art, so drawing the card at its printed shape left ~24pt of pure black
  between the picture and the words that read as empty spacing. The window is the
  printed card with that foot cut off (`576 / 806` in `posterRatio`,
  `PosterShape.portrait` in the app, with `portraitArt` keeping 576×912 for the
  stand-in that must match the art it will show). A card with no strip loses the
  bottom 11% of dark art instead, which is the crop the design already makes
  everywhere else.
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
  border, solid when it is complete. A card is its poster and nothing else — no
  scrim over the art, no band under it — and the grid draws every card at the
  same window shape, so one odd poster cannot make a row ragged. **A course page
  is two columns only in landscape** (`Views/CourseView.swift`, geometry in
  `Support/CourseLayout.swift`): the poster fills the left edge whole — the column
  is exactly as wide as the art needs at its own shape to fill the height, capped
  at 46% of the width — and it does not scroll; the role badge, the numbers and
  *Play* share one line above the right-hand column (the title sits under them, so
  the header costs the list as little as possible) and the lessons scroll beneath.
  Portrait stacks instead, because a poster column there eats the list: a poster a
  third of the width (floored, capped, never cropped because it is drawn at its
  own shape) beside the role, title, numbers and a full-width *Play*, then the
  lessons in a scrolling box that takes the rest of the page. Below roughly 440pt
  of lesson room the rows turn **compact**, a smaller still and a taller title,
  instead of squeezing the words out. **The catalogue's course page is the same
  page** (`Views/DiscoverCourseView.swift`): same two arrangements, same hero, same
  pill — what changes is the data, so its pill reads *Play* when a lesson of that
  course is already on this phone and *Download* when none is. The hero itself is
  `Views/CourseHero.swift` (`CourseHero` + `CoursePill`), which is what keeps the
  two screens from drifting apart.
- **A lesson row is a file, and says so.** A left swipe on a lesson — or a long
  press — offers the two things a file can do from that page: **Export** and
  **Delete**. Both are on the row itself because the alternative is a settings
  screen nobody finds, and both come from the platform (`List`'s
  `.swipeActions(edge: .trailing)` plus `.contextMenu`), so the reveal, the haptics
  and the VoiceOver actions are iOS's own rather than a hand-rolled gesture that
  would fight the row's tap. *Delete* is drawn in the palette's own red: a
  destructive button otherwise keeps the app's global brand tint. An `.mp4` (a desktop download) goes straight to the
  share sheet as it lies; a `.ts` asks first, because one answer costs a copy of
  the lesson: *Share the file as it is*, or *Convert to MP4 and share*. The
  conversion is `Support/TSRemux.swift` — a repackaging, not an encode: the H.264
  and AAC bytes are what an MP4 already carries, so only the container changes.
  It reads its samples from `Support/TSDemuxer.swift` (PAT/PMT to find the two
  elementary streams, the PES headers for the stamps, Annex-B rewritten to AVCC
  with the parameter sets lifted into the format description, the ADTS headers
  peeled off the sound), feeds them to `AVAssetWriter` with no re-encode, and
  removes the half-written MP4 if it fails or is stopped. Two things about that
  writer are worth knowing before touching it: it throttles **per track**, so
  one queue fills both and waits on the pair (waiting on a single input while the
  other is unfed deadlocks the export with no error anywhere), and its sound
  format is an **ES descriptor** wrapped around the stream's
  `AudioSpecificConfig` — handed the bare two-byte config it still writes the
  audio track, but the file's `esds` cannot be parsed and the export plays with
  no sound at all. A lesson that is still
  only in iCloud is a shadow file, so the row offers neither action — there is no
  byte to move and no sheet that could say "fetching it first". Delete asks once
  (`Delete this video?`, naming the space it frees), forgets the queue entry and
  the playback position with the file, and rescans; the row leaves the screen at
  once because the course on screen is the value from the last scan.
  `LessonExportPlanTests` pins the shape/name decisions, `TSDemuxerTests` reads
  the fixture end to end (45 video frames, 66 AAC frames, a 480×270 High SPS) and
  remuxes it into an MP4 with both tracks, and `LessonActionsUITests` drives both
  gestures without accepting either action.
- **A course is a folder, so its long press speaks for all of it.** Holding a
  course card offers `Export all N videos` and `Delete all N videos`, N being the
  videos actually on this phone — a lesson only in iCloud is a shadow file and is
  left out of both, so the confirm quotes only the bytes that leave. Exporting a
  course raises **one** sheet with every file in it: the MP4s hand over as they
  lie and only the transport streams are repackaged, one after another, under one
  banner that counts them (`Repackaging 2 of 7`) and can be stopped. The
  *convert or share as-is?* question is asked only when the batch holds a `.ts`,
  because only that answer costs a copy — `LessonExportPlan.batch` decides it with
  no file touched, so the rule is unit-tested. Deleting takes each file with its
  queue row and resume point, reports a per-file failure rather than claiming
  success, and drops the card only once nothing of the course is left.
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
- **Where it writes — a folder you can see.** The app's own library is its
  Documents folder, `Files › On My iPhone › SkillCapped Local`, and it exists from
  the first launch: `LibraryBootstrap` creates `Courses/`, `Videos/` and
  `Commentaries/` there, so the folder Files shows is obviously the one lessons land
  in, and every screen names it that way (`FilesPlace`, never a
  `/var/mobile/Containers/...` path). Nothing but small state — the queue,
  preferences, playback positions — lives in the app's Application Support folder;
  no lesson ever does. Picking another folder anywhere in Files (iCloud Drive
  included) points the library there instead, and the app is never without one:
  going back to the app's own folder is a move, not a wipe.
- **Changing folders moves the library.** A pick is never only "look somewhere
  else": whatever the app already has under the previous folder is carried into
  the new one (`Model/LibraryMigration.swift`), so the app keeps one library
  instead of a stale copy beside a fresh one. The downloader's own layout is
  preserved — `Courses/`, `Videos/`, `Commentaries/`, the `.skillcapped/`
  catalogue cache and a loose lesson at the top of the folder are the only things
  carried, so a `Photos/` folder that happens to share the library is not the
  app's to relocate. A file already in the destination is never overwritten: the
  same relative path holding the same byte count counts as a second copy and the
  old one is dropped, while a destination file with different content is left
  alone and the source stays where it is, named in the report. A lesson still only
  in iCloud is a hidden shadow file, not bytes, so it is not fetched just to be
  moved. The move runs off the main actor (between two volumes it is a copy), the
  queue is held until the lesson being written finishes, and a finished row's
  remembered path follows its file; folders the move emptied are removed, so the
  old library does not linger as a maze of empty boxes. `RootView` shows the
  progress in a banner (and `Settings` in the folder section) and the report —
  `Moved 42 files (1.2 GB) · 3 were already there · 1 left in the old folder.` —
  once it lands. `LibraryMigrationTests` pins the carry, the merge, the refusal to
  overwrite, the untouched non-library folders, the cloud shadow, the
  never-into-itself rule and the progress readout.
- **What it reads.** `<title> [<uuid>] <quality>.<ext>` under
  `Courses/<role>/<course>/`, `Videos/<role>/<category>/` and
  `Commentaries/<role>/`, exactly as `src/core/naming.ts` writes them, joined to
  `.skillcapped/catalog.json` for titles, durations and the order a course lists
  its lessons in. **A course is its folder**, and the catalogue only describes it:
  a folder is named by a catalogue course only while exactly one course claims its
  lessons. Keying identity on a catalogue id instead split one folder into two
  cards with the same title whenever the desktop's file and the site disagreed
  about which course owns a lesson id — the demo library hits this for real,
  because two of its ids exist upstream under other courses — so `LibraryScanner`
  keys every course on `Courses/<role>/<folder>` and `CatalogIndex.merged` sorts
  its items, since that index's lesson → course map is last-write-wins and a
  dictionary's order must never decide an owner. Both cases are pinned in
  `LibraryScannerTests`. Both containers are playable — an `.mp4` from the desktop and a
  `.ts` from this app (and a `.ts` copied in by hand). Without that catalogue file
  the folders still group a course, and a video copied in by hand keeps its own
  name — its id comes from the uuid in the filename, so a lesson scanned before
  the catalogue loaded still remembers where you stopped and still matches a
  download made on this phone.
- **Cover art.** A frame pulled out of each lesson (`AVAssetImageGenerator`), a
  little way in, cached under `Caches/posters`. An `.mp4` from the desktop yields
  one; a downloaded `.ts` does not, and that is a platform restriction rather
  than a bug here: Apple's *Creating images from a video asset* states that
  generating images from HLS works only when the stream provides a media playlist
  with the `EXT-X-I-FRAMES-ONLY` tag, and `AVURLAsset.loadTracks` answers an empty
  array for an HLS asset by design. Measured on the runner against our own asset,
  that is exactly what it does — `playable=true | duration=3.00s | tracks=0`, and
  the load answers rather than stalling. A `.ts` is therefore not asked for a
  frame at all — a request that never returns would leave a card waiting forever —
  and every other request is raced against a budget. A file that yields no frame
  falls back to a gradient seeded from its title, so a card never looks broken.
  (`testTheHLSAssetReportsWhatItExposes` records what the asset actually exposes.)
- **Playback.** A hand-built player (`Views/PlayerScreen.swift`) over an
  `AVPlayerLayer`, so the transport behaves like a phone player's: **double tap a
  side to skip** five seconds — and keep counting, 10 s, 15 s, inside a 1.2 s burst
  that a pause or a tap on the other side restarts (a person who went forward three
  times and back once must not be thrown 20 s the wrong way) — **drag across to
  scrub**, **drag up the left half for brightness and the right half for the
  sound** (a write goes through the `UISlider` inside a hidden `MPVolumeView`,
  since `AVAudioSession.outputVolume` is read-only and hardware buttons are
  otherwise the only way), one tap for the chrome, which hides itself after four
  seconds of a picture that is **really advancing** — `timeControlStatus`, not the
  rate we asked for: an item that cannot play holds its requested rate at 1 while
  the screen shows a still frame, which hid the transport (the only way out of the
  player) four seconds in — **hold anywhere on the picture to play at 2× while the
  finger stays down** (a press that ends inside 0.4 s is still a tap, a press that
  starts moving is still a scrub, and letting go hands back the rate it
  interrupted, a pause included) — and a rate button cycling 1×/1.25×/1.5×/2×. The chrome
  has **two shapes**, and the whole transport floats over the picture in the order
  a thumb expects: skip back ten, play/pause, skip forward ten, the timeline, the
  rate, then the queue's previous and next. A wide window — a phone on its side, a
  whole iPad — keeps it all in **one row**, with the elapsed and remaining times
  flanking the timeline. A portrait phone cannot fit that *and* both readouts, so
  `PlayerChromeLayout` (below 540 points) floats the rate and the two queue steps
  **above the bar as their own round buttons**, left to right in the order they had
  in the row, and the bar keeps the three a thumb reaches for plus a timeline with
  room for **both times** — the width the moved controls gave back. **Picture in
  Picture alone sits in the screen's top-right corner**, over the close button and
  the lesson's name. The chrome takes the window's safe area from the layout — all
  four edges, re-read when the phone turns — and adds one margin to it
  (`PlayerChromeLayout.edge`), so the header and the bar clear the island, the home
  indicator **and the corners a landscape phone turns**, and their two ends line up
  with each other and with the letterboxed picture's edges. Reading the window's
  insets inside the body was what put a landscape build's corners ten points from
  the glass, under the curve, with the bar off-centre against the picture and its
  header touching the top edge. `PlayerChromeUITests` pins both
  shapes: upright the three floating controls share a band above the bar's, on its
  side every control but Picture in Picture shares one band, the close button and
  Picture in Picture each sit at least fifty points clear of the turned corner, and
  the transport's ends are equidistant from the window's — and both cases insist
  the elapsed and remaining readouts are on screen. **The player takes the sound
  over too** (`Support/AudioSession.swift`): an app that says nothing runs on the
  `soloAmbient` category, which the ringer switch silences and which stops at the
  lock screen — so a lesson played with the phone on silent had no sound at all,
  picture advancing and speaker silent, and the declared `UIBackgroundModes: audio`
  could not help. The category is `.playback` in the `.moviePlayback` mode,
  activated when the player opens and given back with `notifyOthersOnDeactivation`
  when it closes, and it **allows AirPlay and Bluetooth A2DP** (`.allowAirPlay`,
  `.allowBluetoothA2DP`) so a lesson can go to a TV or a pair of headphones instead
  of the phone's own speaker. The output is switched from the player's own header,
  beside Picture in Picture (`Support/RoutePicker.swift`, an `AVRoutePickerView` —
  the only public route to AirPlay's list, video devices first), which is where
  every other phone player offers it. **Control Center, the Lock Screen and a
  headset's buttons see the lesson too** (`Support/RemoteControls.swift`): the
  now-playing dictionary names the lesson, its role, its quality, its length, the
  elapsed time and the rate actually in force — a paused picture reports a rate of
  zero, which stops the system's clock where it is, while `defaultPlaybackRate`
  keeps the speed the person chose for when it starts again — with the site's
  poster (or a frame of the file) as its art, the matching `playbackState`, and
  every transport command wired to the same functions the on-screen chrome calls,
  the queue steps live only where the queue has a neighbour. Without it the picture
  was invisible to the system: Control Center went on showing whatever had played
  before it and its buttons could not reach the lesson.
- **The phone's orientation is the player's.** Turning rotation lock on with the
  phone on its side used to send the picture back to portrait, because the lock
  pins the window to the orientation it was unlocked in whatever the app declares.
  `Support/PlayerOrientation.swift` answers twice: an `OrientationKeeper` asks the
  window for the orientation the phone is held in (`requestGeometryUpdate`, which
  the system honours when it will), and when that is refused the player **turns its
  own picture** — a quarter circle on its own view, which no setting can prevent —
  and takes its safe area from the window's other edges
  (`PlayerOrientation.insets`), so the notch and the home indicator are still
  cleared. The turn is published 350 ms after the phone moves, so a phone turning
  with the lock *off* is answered by the window's own rotation instead of by a
  double turn, and the requests stop after eight refusals because the player's own
  turn already covers it.
- **Pinch to zoom.** Two fingers grow the picture up to five times around the point
  under them (`Support/PlayerZoom.swift`: `offset(starting:from:to:anchor:size:)`
  holds the anchor's content point still, so a pinch opens the spot the fingers are
  on rather than the middle of the screen), a zoomed picture **pans** with a drag
  instead of scrubbing, the offset is clamped so its own edge can never come inside
  the window and show a band of black, and a pinch back below fit springs to fit.
 Picture in
  picture, the route list itself and hardware decoding are still the platform's own
  (`Support/PictureInPicture.swift` wraps `AVPictureInPictureController` around the
  layer, `Support/RoutePicker.swift` the output button). The maths behind every gesture lives in `Support/PlayerGestures.swift`
  (`PlayerMath`, `SkipBurst`, `HoldToSpeed`) so it is pinned by a test rather than by eye.
  `AVPlayerViewController` was used until 1.4.0 and could not carry any of it: its
  chrome cannot be extended, so a lesson could not offer what a phone player offers.
  The position of every file is remembered and resumed above five seconds, and the
  transport steps through the queue the cover was opened from. A downloaded `.ts`
  is played by handing the player a **one-segment `#EXTM3U` playlist** served by a
  loopback HTTP server (`Support/LessonServer.swift`): the file is its own only
  segment, its duration is the catalogue's (or, for a file the catalogue does not
  know, read off the stream's own presentation timestamps — `Support/TransportStream.swift`
  walks both ends of the file for the 90 kHz stamps a PES packet carries, so a
  hand-copied lesson shows its real length instead of a made-up hour; a stream
  that states nothing keeps the placeholder, which is why playback is exact
  either way), and its bytes are served straight from disk by byte range — no
  conversion, nothing copied. AVFoundation seeks by byte range, so scrubbing
  works on a merged file too. The resource-loader route was tried first and does
  not work: Apple's HLS stack refuses the media bytes a delegate answers with, and
  an asset served that way reports its duration and never a frame.
- **Posters.** One box, `Views/PosterArt.swift`, for both kinds of art: a frame
  pulled out of a local file (`PosterStore`) or a poster the site hosts
  (`Support/RemoteArt.swift`, in-memory plus the URL cache — nothing is written
  into the library). A box in a grid is drawn at **one window shape** — the shape
  its grid is designed around, `PosterShape.portrait` for the course cards on
  **both** surfaces (Discover and the library draw the same card, now that a
  library course shows the site's printed poster rather than a frame out of its
  first lesson), `.landscape` for the library's stills and for a lesson thumbnail
  (`Support/PosterShape.swift`) — never at the shape of whichever picture
  arrived. The art fills that window anchored at the **top**: a poster a little
  taller loses its bottom (the title the site printed at the top always survives),
  a wider one is trimmed at the sides, and because the box cannot change size the
  cards in a row are always equal and a grid never reflows under the tap. A
  one-off hero or a course header passes no window and keeps the art's own shape,
  so nothing is cropped there. `fixedSize(vertical:)` on the grid cards is what
  stops a card being stretched to a taller row. The caption under the art is
  padded **4pt above / 9pt below**: a line box already carries a few points over
  its capitals, so a 9pt top band read as a gap of dead card between the poster's
  hard bottom edge and the title rather than as breathing room. **A lesson
  downloaded on the phone has no frame to show** — iOS will not decode a
  transport stream, so `PosterStore` is not even asked — which is why a lesson
  and a course carry the catalogue's own `thumb` and `PosterArt` falls back to it
  (`remote:`), and why the library **adopts the fetched catalogue**
  (`LibraryStore.adopt(catalog:)`, merged under the `.skillcapped/catalog.json`
  the desktop writes, local winning where both know an item): a folder the phone
  filled itself has no catalogue file of its own, so without that merge its
  lessons would have no titles, no order, no durations and no posters at all.
  Only an `http(s)` string is drawn — anything else would be read as a local file
  the app never wrote (`Support/WebLink.swift`).
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
  run).

  **The app owns the dismissal.** `UIDocumentPickerViewController` hands the pick to
  its delegate and then waits: until the app dismisses it, the picker shows a
  spinner exactly where **Open** was, for ever. Nothing in the build did that, which
  is what "it spins on Open and the app has to be restarted" was — so
  `FolderPickerPresenter` now dismisses the picker itself, waits for that dismissal
  to finish before answering (a second dismissal while one animates is dropped by
  UIKit and the picker stays up), and answers directly when the system already took
  the picker away or when a dismissal never reports back. The `isDirectory` stat
  that decides "folder, not file" runs off the main thread and takes the security
  scope itself, because a stat through another app's file provider is an
  out-of-process round trip. The UI suite now drives **Open** as well as Cancel and
  insists the picker leaves and the library comes back — the path it never touched
  before, which is the one that hung. A refusal
  names the iOS version and build it came from, so a device-side refusal diagnoses
  itself. The app's own folder needs no picker at all: with `UIFileSharingEnabled`
  it is the app's Documents folder, visible as **On My iPhone › SkillCapped
  Local**, and it is the library from the first launch — `LibraryBootstrap`
  creates `Courses/`, `Videos/` and `Commentaries/` in it, so Files shows where a
  lesson lands before any exists, and `LibraryStore` adopts the folder itself
  (adoption is by identity, not by content, because freshly made buckets are
  empty). `LibraryLocator` lists every folder in there holding a library; a single
  candidate is adopted on launch, several are offered in the `Library folder`
  sheet, and with none the app stays on its own folder rather than on no library
  at all. Picking a folder that merely *contains* the library
  (iCloud Drive's root, a Downloads folder) adopts the only library one level down
  (`ExternalFolderTests` pins both, and that the bookmark survives a relaunch).
- **A pick is read off the main actor.** Deciding what a picked folder is means
  listing it, and a folder in another app's container answers through its file
  provider — a listing there is a round trip outside this process, and on a tree
  nobody expected there are thousands of them. Doing that on the main actor is
  what made the iPad picker's **Open** spin forever with the app frozen behind it
  (v1.6.1). `LibraryPick.prepare` now runs on a detached task and hands the store
  a finished answer — target, bookmark, whether the sandbox already allows the
  folder, and the security scope it is holding on the app's behalf —
  `LibraryLocator.walk` stops after `walkBudget` (400) folders and says that it
  stopped, and nothing about the current library changes until the answer is in.
  While it runs the library shows `Reading <folder>…` with **Stop**, so a folder
  stock iOS is still fetching can be abandoned instead of wedging the app, and
  the sheet's **Last pick** line reports what the folder turned out to be, how
  many folders were read, how long it took, whether the security scope was
  granted and whether the walk stopped early (`LibraryPickTests`, and the budget
  cases in `LibraryLocatorTests`). The app's own folder still takes the immediate
  path: no walk, no bookmark, nothing to wait for.
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
  Two debug-only launch arguments keep the UI suite off the network:
  `-demoLibrary` seeds a throwaway library in the app's own sandbox
  (`Support/DemoLibrary.swift`) and `-demoCatalog` installs a small catalogue in
  `CatalogueStore` (`Support/DemoCatalogue.swift`) whose lesson ids are the uuids
  the demo library writes — so a run with both opens a *catalogue* course that
  this phone already has, which is what `BrowseUITests` asserts in both
  orientations.

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
