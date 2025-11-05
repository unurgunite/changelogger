# Changelogger

A tiny TUI to build CHANGELOGs from your git history. Browse your git graph in the left pane, pick "anchor" commits that
mark minor releases, and watch a live preview of the generated CHANGELOG in the right pane. Press Enter to write
CHANGELOG.md.

- Left pane: git log graph with htop-style scrolling
- Right pane: live preview of the CHANGELOG you’re about to generate
- Anchor selection -> semantic-ish versions: 0.1.0, 0.2.0, ... with evenly spaced patches in between
- Colorful highlighting, helpful key hints, and a comfy terminal UX

Works best on macOS/Linux terminals. Windows users: try WSL.

* [Changelogger](#changelogger)
    * [Demo](#demo)
    * [Install](#install)
    * [Quick start](#quick-start)
    * [What it does](#what-it-does)
    * [Key bindings](#key-bindings)
    * [Versioning algorithm](#versioning-algorithm)
    * [Output format](#output-format)
    * [UI details](#ui-details)
    * [Requirements](#requirements)
    * [Troubleshooting](#troubleshooting)
    * [Programmatic usage (library)](#programmatic-usage-library)
    * [Development](#development)
    * [Contributing](#contributing)
    * [License](#license)
    * [Acknowledgements](#acknowledgements)

## Demo

![Demo](docs/demo.gif)

## Install

Gemfile:

```ruby
gem "changelogger"
```

Then:

```shell
bundle install
```

Or install globally:

```shell
gem install changelogger
```

## Quick start

From a git repository with commits:

```shell
# If installed globally:
changelogger

# If running from the repo with bundler:
bundle exec exe/changelogger
```

- Move the cursor in the left pane and press Space to select at least 2 commits (anchors).
- Watch the right pane update live with the CHANGELOG that would be generated.
- Press Enter to write CHANGELOG.md to the current directory.
- Press q or ESC to quit without generating.

## What it does

- Reads your repository history
- Lets you choose "anchors" (two or more commits) that define minor versions:
    - First anchor -> 0.1.0
    - Second anchor -> 0.2.0
    - Third anchor -> 0.3.0
    - ...
- Commits between each pair of anchors become 0.<minor>.<patch>, where patch numbers are spaced evenly within 1..10 (
  configurable base), e.g.:
    - 1 in-between -> 0.1.5
    - 2 in-between -> 0.1.3, 0.1.7
    - 3 in-between -> 0.1.3, 0.1.5, 0.1.8
- Writes a clean CHANGELOG.md with dates and subjects, plus bodies indented.

The result starts with:

```markdown
## [Unreleased]

## [0.1.0] - 2021-08-09

- Initial release
```

...and continues for your selections.

## Key bindings

Left pane (Graph)

- Up/Down or j/k: move between commits
- Space: toggle anchor selection
- PgUp/PgDn (or keypad equivalents): jump by 5 commits
- f: toggle "fit full selected commit" inside the viewport
- r: refresh the git graph and commit list
- <: shrink left pane, >: expand left pane

Right pane (Preview)

- Up/Down or j/k: scroll
- PgUp/PgDn: page scroll
- g: top, G: bottom

Global

- Tab / Shift-Tab: switch focus between panes
- Enter: generate CHANGELOG.md and exit
- q or ESC: cancel and exit without generating

Key hints are always shown at the top of each pane. Selected anchors are highlighted in a distinct color; the current
cursor commit block is highlighted separately.

## Versioning algorithm

This gem uses a simple "semantic-ish" mapping:

- Major version stays 0
- Minor version increments per anchor: 0.1.0, 0.2.0, 0.3.0, ...
- In-between commits are assigned patch numbers distributed across the 1..10 range (default base) using a spacing
  function:
    - `patches[i] = round((i+1) * base / (k+1))` adjusted to be strictly increasing
    - You can change the base in code to make spacing tighter/looser

Examples

- Anchors A and B with 1 commit between -> versions in that segment: 0.1.5, then B = 0.2.0
- Anchors A and B with 3 commits between -> 0.1.3, 0.1.5, 0.1.8, then B = 0.2.0
- Adding more anchors repeats the scheme for each segment.

## Output format

For each selected commit (anchors and in-between):

- Section header: "## [x.y.z] - YYYY-MM-DD"
- Bullet: "- <subject> (<short_sha>)"
- Commit body (if any) is included, indented on subsequent lines

A top "## [Unreleased]" section is included by default.

## UI details

- Side-by-side layout:
    - Left: git log --graph with branches rendered
    - Right: live preview of the generated CHANGELOG
- htop-like scrolling: selection moves within the viewport first, then the screen scrolls
- "Fit selected commit block" avoids cutting commit messages at the bottom (toggable with f)
- The .graph file is auto-regenerated if missing or stale; press r to refresh manually

## Requirements

- Ruby 2.7+
- A POSIX terminal with basic color support recommended
- Linux/macOS tested; Windows via WSL recommended
- Git installed and a repository with commits

## Troubleshooting

- Tab doesn’t switch focus:
    - We normalize Tab across terminals, but if your terminal swallows it, try Shift-Tab or ensure your TERM is set
      properly (e.g., xterm-256color).
- No colors:
    - Colors depend on your terminal’s capabilities; it falls back to bold/standout automatically.
- "No git graph available":
    - You’re probably not in a git repo or have no commits yet.
- Pressing q/ESC shows "No CHANGELOG generated...":
    - Fixed. Cancel now exits quietly (no message). If you still see it, update to the latest code.

## Programmatic usage (library)

If you want to generate a changelog without the TUI, require the internal components directly:

```ruby
require "changelogger/git"
require "changelogger/versioner"
require "changelogger/changelog_generator"

commits = Changelogger::Git.commits
# Choose anchors by SHA (full or short). Must be 2+ in chronological order.
anchors = ["abc1234", "def5678", "fedcba9"]

# Preview as a string:
puts Changelogger::ChangelogGenerator.render(commits, anchors)

# Or write to file (default: CHANGELOG.md)
Changelogger::ChangelogGenerator.generate(commits, anchors, path: "CHANGELOG.md")
```

Note: requiring "changelogger" boots the TUI. For scripts, require the files above individually.

## Development

- Clone the repo and run:

```shell
bin/setup
```

- Run the app (from a git repo):

```shell
bundle exec exe/changelogger
```

- Lint and tests:

```shell
bundle exec rubocop
bundle exec rspec
```

Heads-up: the default spec is a placeholder and intentionally fails. Replace it with real specs before shipping.

- Build/install locally:

```shell
bundle exec rake install
```

## Contributing

Issues and PRs welcome! Please:

- Use a clear title/description
- Add reproduction steps or a short video for UI bugs
- Keep changes focused and include before/after notes

## License

MIT © 2021–present unurgunite, SY573M404

## Acknowledgements

- Curses for the terminal UI
- Git for the history plumbing
- You, for using and improving this little tool
