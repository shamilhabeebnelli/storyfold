# StoryFold

**Read the story once. Keep every source.**

A local-first browser app backed by a **Haskell story-grouping engine**. Import downloaded RSS/Atom feeds or a JSON reading list, fold similar headlines into one card, inspect the reason for each match and compare every original headline/body.

This is a working file-import prototype, not an automatic subscription service. It does not fetch live feeds, scrape websites, summarize articles with AI or deploy a hosted website.

## Run locally

Requirements: GHC 8.8+ with `base` and `containers`, Python 3.9+, and a modern browser. There are no pip or npm dependencies.

```sh
ghc -O2 -Wall -Werror Main.hs -o storyfold
python3 app.py
```

Open **http://127.0.0.1:8787** and choose **Try sample stories**. Six fictional source entries become four groups. The two headlines that disagree about a train-service count remain separate.

On Windows compile with `-o storyfold.exe`, then run `python app.py`. The code is tested on Linux with GHC 8.8.4 and Python 3.10; Windows and macOS have not been tested.

If port 8787 is occupied: `python3 app.py --port 8788`.

## What it does

- Imports one or more **UTF-8 RSS 2.0 / Atom XML files** and JSON arrays. Importing appends to the current reading list.
- Keeps every source entry and original link. Nothing is silently deleted.
- Removes common tracking parameters when comparing URLs, while retaining content-identifying query parameters.
- Detects normalized identical headlines, reordered/mildly altered headlines and repeated body word sets.
- Gives each suggested match a readable reason and, for fuzzy headlines, its Jaccard word-overlap percentage.
- Lets the reader adjust the threshold, search headlines/sources, expand all original wording or show every entry separately.
- Exports the complete reading list as JSON for re-import.
- Leaves data in memory only. Closing/reloading the page clears the list unless exported.

## How matching works

`StoryFold.hs` is the decision engine. `Main.hs` is a small bounded Unicode bridge. `app.py` uses only Python's standard library to parse feed files, validate input and run the compiled Haskell executable. `index.html` is the browser interface.

The engine first checks matching URLs, then normalized headline words, then long body word sets and conservative headline similarity. Different explicit numbers or simple English negation block fuzzy matching. A shared URL can still group changed revisions because it identifies the same source address.

Groups compare each member against one deterministic representative, not a chain of loosely related articles. Sorting uses the supplied publication strings, source, URL and title for repeatability. It **does not parse dates chronologically** and the representative is not necessarily the earliest, newest or best article. Every source is equally accessible.

This is **not semantic AI, fact checking or plagiarism detection**. Related articles can be missed and unrelated ones can be grouped. Body word-set equality ignores order and frequency, so its reason explicitly asks the reader to review wording. Stop words and negation checks are English-oriented. Unicode is preserved, but cross-language matches and accurate Malayalam grouping are not promised. Recycled headlines are labeled as possible republication, not asserted to be duplicate reporting. No article-body rewriting or inline change-highlighting is included.

## Import format

```json
[
  {
    "title": "City opens a coastal walking trail",
    "url": "https://example.com/story",
    "source": "Example Daily",
    "published": "2026-11-20",
    "body": "Optional original text for comparison."
  }
]
```

Only `title` is required. Other fields default to empty strings. Maximum: 500 stories in a combined list, 4 MB per request, 2,000 characters per metadata field and 10,000 per body. Large imports fail validation instead of being truncated. RSS items without titles are skipped. Unsupported XML schemas and malformed documents fail. Feed bodies containing HTML are displayed as plain text, never executed.

Save an RSS feed's XML using your browser or download tool, then import that file. The app intentionally has no remote URL fetcher or automatic refresh scheduler. Importing the same file twice retains two entries, which may be folded together; source entries are not discarded.

## Tests

```sh
ghc -Wall -Werror Test.hs -o storyfold-tests
./storyfold-tests
python3 -m unittest -v test_app.py
```

24 Haskell checks cover matching, number/negation guards, URL tracking cleanup, determinism, source preservation, Unicode and JSON escaping. 13 Python checks cover RSS/Atom parsing, DTD rejection, size/types, bridge behavior and HTTP host/token protections. Browser interaction checks also exercised the sample, search, separate view, clear, JSON import and narrow-mobile layout.

## Privacy and safety

- The server binds only to `127.0.0.1`. Do not expose it through a proxy or bind it to a public interface.
- Requests are protected with a per-run token and checked Host header. There is no CORS access for other sites.
- No telemetry, cloud model, database, paid API or automatic network fetching.
- Reading lists are not written to disk by the app. Export is an explicit browser download. Browsers/operating systems may retain their own history or downloads.
- Clicking an original source link opens that external website. Its own privacy policy then applies.
- XML DTD/entity declarations are rejected; file sizes and story lengths are bounded.
- Original titles/body text are inserted as text, not HTML. Only HTTP(S) source links are clickable.
- Treat matches as suggestions. Use separate view and original sources when correctness matters.

## Why this project

Community requests that motivated the problem:

- [Miniflux: duplicate and similar-title entries](https://github.com/miniflux/v2/issues/797)
- [FreshRSS: clear duplicate articles](https://github.com/FreshRSS/FreshRSS/issues/948)
- [FreshRSS: consolidate entries across feeds](https://github.com/FreshRSS/FreshRSS/issues/6916)

Existing alternatives already solve parts of this problem. [NewsBlur offers story clustering](https://www.newsblur.com/features/story-clustering), and FreshRSS/ReactFlux provide duplicate handling. StoryFold is a small inspectable local experiment, not a claim of a new category or affiliation with those projects.

## License

MIT License. Copyright (c) 2026 shamilhabeebnelli. See [LICENSE](LICENSE). The license covers this original code and documentation. It does not grant trademark rights or override licenses on separately installed dependencies or imported third-party content.
