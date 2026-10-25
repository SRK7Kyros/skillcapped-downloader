#!/usr/bin/env bash
# Which iOS tests a change needs.
#
# The suite is ~11 minutes on a macos-26 runner and ~6.5 of that is the UI
# tests, each launching the app afresh on a cold simulator. A change to a model
# file cannot move a button, so re-running the screens it does not touch buys
# nothing — it only costs the wait. This script reads the diff and answers one
# of three things:
#
#   all   — every test. The fallback whenever the change cannot be proven safe:
#           the shared shell, the fixtures the tests launch with, a view the
#           table does not know, or ios/project.yml (which changes what is built).
#   none  — unit tests only. Nothing rendered moved: Model/, logic-only Support/,
#           tests, docs, the web app, the workflow itself.
#   some  — exactly the UI classes whose screens the diff touches.
#
# The table is deliberately conservative in one direction only: it never skips a
# class it cannot prove is unaffected. A file it does not recognise under Views/
# answers `all`.
#
# Usage:
#   test-scope.sh [--base <rev>] [--head <rev>] [--message <text>]
#                 [--mode auto|all|none] [--self-test]
#
#   --base      diff against this rev (default: $BEFORE, then HEAD~1, then all)
#   --message   the commit message; `[ui-all]` / `[ui-none]` override the mode
#   --mode      auto (the diff decides), all, or none
#   --self-test proves the table against known paths, no git required
#
# With $GITHUB_OUTPUT set, writes `ui=` and `flags=` (space-separated xcodebuild
# arguments) to it; the decision itself always goes to stdout.

set -u

UI_TARGET="SkillCappedLocalUITests"
ALL_CLASSES="BrowseUITests FolderPickerUITests LessonActionsUITests PlayerChromeUITests SettingsUITests"

die() { echo "test-scope: $*" >&2; exit 2; }

# ---------------------------------------------------------------- the table
#
# One token per changed file. Tokens expand to classes in `classes_for`, so a
# token can name more than one screen (a course row is rendered by the browse
# grid and driven by the lesson-actions test).
classify() {
  case "$1" in
    # Everything at once: the shell around every screen, the palette, the demo
    # fixtures the UI tests launch with, and the project definition itself.
    ios/SkillCappedLocal/Views/RootView.swift | \
    ios/SkillCappedLocal/Support/Palette.swift | \
    ios/SkillCappedLocal/Support/OnScreen.swift | \
    ios/SkillCappedLocal/Support/Format.swift | \
    ios/SkillCappedLocal/Support/DemoCatalogue.swift | \
    ios/SkillCappedLocal/Support/DemoLibrary.swift | \
    ios/project.yml | \
    ios/SkillCappedLocal/Info.plist | \
    ios/Shared/*)
      echo all ;;

    # The player: its screen and surface, every layout/gesture rule behind the
    # chrome, and the glass those controls are drawn on.
    ios/SkillCappedLocal/Views/Player*.swift | \
    ios/SkillCappedLocal/Views/GlassSurface.swift | \
    ios/SkillCappedLocal/Support/Player*.swift | \
    ios/SkillCappedLocal/Support/PlayheadHold.swift | \
    ios/SkillCappedLocal/Support/DisplayCorner.swift | \
    ios/SkillCappedLocal/Support/VideoFit.swift | \
    ios/SkillCappedLocal/Support/PictureInPicture.swift | \
    ios/SkillCappedLocal/Support/RoutePicker.swift | \
    ios/SkillCappedLocal/Support/SystemVolume.swift | \
    ios/SkillCappedLocal/Support/RemoteControls.swift | \
    ios/SkillCappedLocal/Support/AudioSession.swift)
      echo player ;;

    # A course page and its rows are opened by the browse grid and acted on by
    # the lesson-actions test, so both runs.
    ios/SkillCappedLocal/Views/CoursePage.swift | \
    ios/SkillCappedLocal/Views/CourseHero.swift | \
    ios/SkillCappedLocal/Views/CourseView.swift | \
    ios/SkillCappedLocal/Views/DiscoverCourseView.swift | \
    ios/SkillCappedLocal/Views/ExportBanner.swift | \
    ios/SkillCappedLocal/Support/CourseLayout.swift | \
    ios/SkillCappedLocal/Support/LessonExport.swift | \
    ios/SkillCappedLocal/Support/LessonExportPlan.swift)
      echo course ;;

    # The catalogue grid, the library list and the cards that fill them.
    ios/SkillCappedLocal/Views/BrowseView.swift | \
    ios/SkillCappedLocal/Views/DiscoverView.swift | \
    ios/SkillCappedLocal/Views/CourseCard.swift | \
    ios/SkillCappedLocal/Views/CatalogCourseCard.swift | \
    ios/SkillCappedLocal/Views/PosterArt.swift | \
    ios/SkillCappedLocal/Views/ContinueShelf.swift | \
    ios/SkillCappedLocal/Views/DownloadsView.swift | \
    ios/SkillCappedLocal/Views/RowState.swift | \
    ios/SkillCappedLocal/Support/PosterShape.swift | \
    ios/SkillCappedLocal/Support/RemoteArt.swift | \
    ios/SkillCappedLocal/Support/WebLink.swift | \
    ios/SkillCappedLocal/Support/Search.swift)
      echo browse ;;

    # The system folder picker and the library sheet that raises it.
    ios/SkillCappedLocal/Views/LibraryLocationView.swift | \
    ios/SkillCappedLocal/Support/FolderAccess.swift | \
    ios/SkillCappedLocal/Support/FolderPickerPresenter.swift | \
    ios/SkillCappedLocal/Support/PickerProbe.h | \
    ios/SkillCappedLocal/Support/PickerProbe.m | \
    ios/SkillCappedLocal/Model/LibraryPick.swift | \
    ios/SkillCappedLocal/Model/LibraryStore.swift | \
    ios/SkillCappedLocal/Model/LibraryLocator.swift | \
    ios/SkillCappedLocal/Model/LibraryBootstrap.swift | \
    ios/SkillCappedLocal/Support/FilesPlace.swift)
      echo folder ;;

    # Settings, including the two readouts it prints.
    ios/SkillCappedLocal/Views/SettingsView.swift | \
    ios/SkillCappedLocal/Views/QualityOrderView.swift | \
    ios/SkillCappedLocal/Support/DebugReport.swift | \
    ios/SkillCappedLocal/Support/LiveActivityDiagnostics.swift | \
    ios/SkillCappedLocal/Support/BundleVersion.swift | \
    ios/SkillCappedLocal/Support/BackgroundJournal.swift | \
    ios/SkillCappedLocal/Support/PreferencesStore.swift)
      echo settings ;;

    # A UI test's own change re-runs that class — except a shared helper or a
    # fixture, which could be behind any of them.
    ios/${UI_TARGET}/*.swift)
      stem=$(basename "$1" .swift)
      case " $ALL_CLASSES " in
        *" $stem "*) echo "self:$stem" ;;
        *) echo all ;;
      esac ;;

    ios/${UI_TARGET}/*)
      echo all ;;

    # A view the table does not name could be rendered on any screen.
    ios/SkillCappedLocal/Views/*)
      echo all ;;

    # Logic only. The visual rules are all named above; anything left under
    # Support/ or Model/ is exercised by the unit tests, not by a simulator.
    ios/SkillCappedLocal/Support/* | ios/SkillCappedLocal/Model/* | ios/SkillCappedLocalTests/*)
      echo none ;;

    *)
      echo none ;;
  esac
}

# A token's classes, in the fixed order the summary prints them.
classes_for() {
  case "$1" in
    all) echo "$ALL_CLASSES" ;;
    player) echo "PlayerChromeUITests" ;;
    browse) echo "BrowseUITests" ;;
    course) echo "BrowseUITests LessonActionsUITests" ;;
    folder) echo "FolderPickerUITests" ;;
    settings) echo "SettingsUITests" ;;
    self:*) echo "${1#self:}" ;;
  esac
}

# The whole decision for a list of paths, left in $SCOPE: "all", "none", or the
# class list in canonical order. The deciding files stay in $REASONS. State
# rather than stdout, because a command substitution would lose $REASONS.
SCOPE=""
REASONS=""
scope_for() {
  tokens=" "
  REASONS=""
  for p in "$@"; do
    t=$(classify "$p")
    [ -z "$t" ] && t=none
    case "$t" in
      all) REASONS="$REASONS$p (any screen), "; SCOPE=all; return ;;
    esac
    tokens="$tokens$t "
    REASONS="$REASONS$p ($t), "
  done
  [ "$tokens" = " " ] && { SCOPE=all; return; }

  picked=""
  for c in $ALL_CLASSES; do
    for t in $tokens; do
      for k in $(classes_for "$t"); do
        if [ "$k" = "$c" ]; then
          case " $picked " in *" $c "*) ;; *) picked="$picked $c" ;; esac
        fi
      done
    done
  done
  picked=${picked# }
  [ -z "$picked" ] && { SCOPE=none; return; }
  # every class picked is the same as running them all
  if [ "$picked" = "$(echo $ALL_CLASSES)" ]; then SCOPE=all; else SCOPE=$picked; fi
}

# ---------------------------------------------------------------- self-test
self_test() {
  fails=0
  check() {
    want=$1; shift
    scope_for "$@"
    got=$SCOPE
    if [ "$got" = "$want" ]; then
      printf 'ok    %-46s -> %s\n' "$*" "$got"
    else
      printf 'FAIL  %-46s -> %s (want %s)\n' "$*" "$got" "$want"
      fails=$((fails + 1))
    fi
  }

  # a screen's own file runs that screen's test, and nothing else
  check PlayerChromeUITests ios/SkillCappedLocal/Views/PlayerScreen.swift
  check PlayerChromeUITests ios/SkillCappedLocal/Support/PlayerChromeLayout.swift
  check PlayerChromeUITests ios/SkillCappedLocal/Support/PlayerZoom.swift
  check SettingsUITests ios/SkillCappedLocal/Views/SettingsView.swift
  check FolderPickerUITests ios/SkillCappedLocal/Support/FolderPickerPresenter.swift
  check FolderPickerUITests ios/SkillCappedLocal/Model/LibraryPick.swift
  check BrowseUITests ios/SkillCappedLocal/Views/BrowseView.swift
  # a course row is both a browse card and a lesson-actions row
  check "BrowseUITests LessonActionsUITests" ios/SkillCappedLocal/Views/CoursePage.swift
  check "BrowseUITests LessonActionsUITests" ios/SkillCappedLocal/Support/LessonExport.swift
  # a change to a test re-runs that test
  check BrowseUITests ios/SkillCappedLocalUITests/BrowseUITests.swift

  # logic-only changes cost no simulator
  check none ios/SkillCappedLocal/Model/SegmentDownloader.swift
  check none ios/SkillCappedLocal/Support/BackgroundTransfer.swift
  check none tests/unit/cdn.test.ts
  check none README.md
  check none .github/workflows/ios.yml
  check none ios/scripts/test-scope.sh

  # anything unprovable buys the whole suite
  check all ios/SkillCappedLocal/Views/RootView.swift
  check all ios/SkillCappedLocal/Views/SomeNewScreen.swift
  check all ios/project.yml
  check all ios/SkillCappedLocal/Support/DemoLibrary.swift
  check all ios/Shared/DownloadActivityAttributes.swift
  check all ios/SkillCappedLocalUITests/Fixtures/helper.swift

  # several files: the union, canonical order, and one unknown file wins the lot
  check "PlayerChromeUITests SettingsUITests" \
    ios/SkillCappedLocal/Model/DownloadManager.swift \
    ios/SkillCappedLocal/Views/PlayerScreen.swift \
    ios/SkillCappedLocal/Views/SettingsView.swift
  check all \
    ios/SkillCappedLocal/Views/PlayerScreen.swift \
    ios/SkillCappedLocal/Views/RootView.swift
  # every class picked individually is just "all"
  check all \
    ios/SkillCappedLocal/Views/BrowseView.swift \
    ios/SkillCappedLocal/Support/FolderAccess.swift \
    ios/SkillCappedLocal/Views/CoursePage.swift \
    ios/SkillCappedLocal/Views/PlayerScreen.swift \
    ios/SkillCappedLocal/Views/SettingsView.swift

  if [ "$fails" -ne 0 ]; then
    echo "$fails of the table's cases disagree" >&2
    exit 1
  fi
  echo "the table agrees with all its cases"
}

# ---------------------------------------------------------------- arguments
base=""
head_rev="HEAD"
message=""
mode="auto"

while [ $# -gt 0 ]; do
  case "$1" in
    --base) base=${2:-}; shift 2 ;;
    --head) head_rev=${2:-}; shift 2 ;;
    --message) message=${2:-}; shift 2 ;;
    --mode) mode=${2:-}; shift 2 ;;
    --self-test) self_test; exit $? ;;
    -h | --help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$mode" in
  auto | all | none) ;;
  *) die "--mode takes auto, all or none (got '$mode')" ;;
esac

# A commit can overrule the table when the author knows better. The message is
# read from the head commit when one was not handed in, so a local run behaves
# exactly like the workflow's.
if [ -z "$message" ]; then
  message=$(git log -1 --format=%B "$head_rev" 2>/dev/null || true)
fi
case "$message" in
  *"[ui-all]"*) mode=all ;;
  *"[ui-none]"*) mode=none ;;
esac

emit() {
  ui=$1
  flags=$2
  reason=$3
  printf 'ui=%s\n' "$ui"
  printf 'flags=%s\n' "$flags"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'ui=%s\nflags=%s\n' "$ui" "$flags" >> "$GITHUB_OUTPUT"
  fi
  count=0
  for c in $ALL_CLASSES; do count=$((count + 1)); done
  case "$ui" in
    all) sentence="all $count UI tests" ;;
    none) sentence="no UI tests (unit tests only)" ;;
    *)
      n=0
      for c in $ui; do n=$((n + 1)); done
      sentence="$ui ($n of $count)"
      ;;
  esac
  echo "::notice title=Test scope::UI tests: $sentence — $reason"
}

if [ "$mode" = all ]; then
  emit all "" "forced by --mode/commit token"
  exit 0
fi
if [ "$mode" = none ]; then
  emit none "-skip-testing:$UI_TARGET" "forced by --mode/commit token"
  exit 0
fi

# auto: the diff decides. A base that cannot be resolved (a first push, a
# force-push, a shallow clone) means nothing can be proven, so everything runs.
[ -z "$base" ] && base=${BEFORE:-}
if [ -z "$base" ] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  base=$(git rev-parse --verify --quiet "$head_rev~1" 2>/dev/null || true)
fi
if [ -z "$base" ] || ! git cat-file -e "$base^{commit}" 2>/dev/null; then
  emit all "" "no comparable base commit"
  exit 0
fi

if ! files=$(git diff --name-only "$base" "$head_rev" 2>/dev/null); then
  emit all "" "git diff $base..$head_rev failed"
  exit 0
fi
if [ -z "$files" ]; then
  emit all "" "the diff from $base is empty"
  exit 0
fi

# shellcheck disable=SC2086
scope_for $files
scope=$SCOPE
[ -z "$REASONS" ] && REASONS="(nothing to attribute)"

case "$scope" in
  all)
    emit all "" "a changed file can reach any screen: $(printf '%s' "$REASONS" | sed 's/, $//')"
    ;;
  none)
    emit none "-skip-testing:$UI_TARGET" "nothing rendered changed: $(printf '%s' "$REASONS" | sed 's/, $//')"
    ;;
  *)
    flags=""
    for c in $scope; do flags="$flags -only-testing:$UI_TARGET/$c"; done
    emit "$scope" "${flags# }" "$(printf '%s' "$REASONS" | sed 's/, $//')"
    ;;
esac
