# Riff sync format, version 1

This is how Riff apps keep podcast and library data in step through a
WebDAV folder the listener owns (Nextcloud, ownCloud, a NAS, `rclone serve
webdav`, …). There is no Riff server: every app reads the files, merges them
with what it has, and writes them back.

The format is plain JSON and OPML, so any app can implement it. Riff Mobile
(Flutter) and Riff desktop (GTK4 / Python) both follow this document. Where
this text says "client", it means any app that implements it.

## Folder layout

Everything lives in one folder, `Riff/`, at the WebDAV URL the listener
enters (for Nextcloud that is usually
`https://host/remote.php/dav/files/<user>/`).

```
Riff/
  manifest.json
  podcasts/
    subscriptions.opml
    episodes.json
    bookmarks.json
    segments.json
  library/
    playlists.json
    favorites.json
```

A client creates missing folders (`MKCOL`) and treats a missing file as an
empty collection. Each file is independent: a client that only understands
some collections leaves the other files alone.

## Common rules

### Time

All times are integers: milliseconds since 1970-01-01T00:00:00Z (UTC).

### Records

Every collection is a set of records, each with an `id` that is unique
within its collection. A record is either live (it has `data`) or a
**tombstone** (`"deleted": true`, no `data`), which says the record was
removed and must stay removed everywhere.

| Field       | Type    | Meaning                                                     |
|-------------|---------|-------------------------------------------------------------|
| `updatedAt` | integer | When this version was written (see "Time").                 |
| `device`    | string  | Id of the client install that wrote it (see "Device id").   |
| `deleted`   | boolean | `true` for a tombstone. Absent or `false` otherwise.        |
| `data`      | object  | The record itself (per collection, below). Absent on tombstones. |

### Merging: last writer wins

To merge two versions of the same record, keep the **winner**:

1. The larger `updatedAt` wins.
2. On a tie, a tombstone wins over a live record.
3. Still tied: the larger `device`, compared as plain ASCII strings, wins.
4. Still tied: they are the same write; keep either.

A record that exists on one side only is kept as it is. The rules make
merging order-independent, so all clients end up with the same result.

### Tombstones expire

A tombstone older than **180 days** (`now - updatedAt > 180 days`) may be
dropped by any client while it writes the file. A client that has not
synced for longer than that may bring a deleted record back; this is the
accepted cost of keeping files small.

### Unknown fields

Clients **must keep** fields they don't know: in a record, inside `data`,
and at the top of a file. When a client writes back a record it didn't
change, it writes it exactly as it read it. This lets newer clients add
fields without older ones erasing them.

### When the local edit time is unknown

A client should stamp each change with the time it happened. A client that
can't (an old install, data from a backup) uses the time it notices the
change, which is the time of the sync. A record that was never synced and
has no known edit time is stamped `0`, so the first sync of a new device
defers to what is already on the server.

### Device id

A random string of lowercase hex digits, made once per install and kept.
Its only purpose is breaking ties.

### Writing safely

Read a file with `GET`, keep its `ETag`, merge, then `PUT` with
`If-Match: <etag>` (or `If-None-Match: *` when the file didn't exist). On
`412 Precondition Failed` another device wrote in between: read again,
merge again, try again. Servers without ETags get a plain `PUT`.

A client never writes a file it couldn't parse; it reports an error and
leaves the file alone.

## manifest.json

```json
{
  "format": "riff-sync",
  "version": 1,
  "updatedAt": 1767225600000,
  "device": "3f9a0c2b7d41e865"
}
```

`version` is the major version of this document. A client that finds a
larger `version` than it supports must not write anything and should tell
the listener to update. Additions that older clients can safely ignore
(new fields, new collection files) don't change `version`.

## JSON collection files

```json
{
  "format": "riff-sync",
  "version": 1,
  "collection": "podcast.episodes",
  "records": {
    "<id>": { "updatedAt": 1767225600000, "device": "3f9a…", "data": { … } },
    "<id>": { "updatedAt": 1767225700000, "device": "77b1…", "deleted": true }
  }
}
```

`records` is an object keyed by record id.

### Podcast episode ids

Episode ids are opaque strings. Riff Mobile uses its own: the YouTube video
id for YouTube episodes, and `podcast_<number>` for RSS episodes. Because
the number can't be computed outside Riff Mobile, every record that refers
to an episode also carries fields to find it by:

| Field          | Meaning                                         |
|----------------|-------------------------------------------------|
| `feedUrl`      | The show's RSS feed URL (RSS episodes).         |
| `enclosureUrl` | The audio file URL from the feed's `<enclosure>`. |
| `guid`         | The feed item's `<guid>`, when known.           |
| `videoId`      | The YouTube video id (YouTube episodes).        |

A client that can't compute an id finds the episode by these fields. When
it creates a record for an episode that has no record yet, it uses
`url:<enclosureUrl>` as the id (or the video id for YouTube episodes).
Riff Mobile turns a `url:` record into one with its own id: it writes the
same `data` and `updatedAt` under its id and a tombstone, at the same
`updatedAt`, for the `url:` id.

### `podcasts/episodes.json`: `podcast.episodes`

Where the listener is in each episode, and which are finished. Id: the
episode id.

```json
{
  "positionMs": 1234000,
  "durationMs": 3600000,
  "played": false,
  "title": "Episode title",
  "show": "Show name",
  "artUri": "https://…/cover.jpg",
  "feedUrl": "https://example.com/feed.xml",
  "enclosureUrl": "https://example.com/ep1.mp3",
  "guid": "…",
  "videoId": "…"
}
```

- `played: true` means finished; `positionMs` is then `0`.
- A tombstone means "never started" (progress reset, marked unplayed).
- `title`, `show`, `artUri` let a client show the episode in "Continue"
  before it has loaded the feed.

### `podcasts/bookmarks.json`: `podcast.bookmarks`

Saved moments in episodes. Id: the bookmark id (any unique string; Riff
Mobile uses `<episodeId>_<createdAt>`).

```json
{
  "episodeId": "podcast_123",
  "positionMs": 754000,
  "createdAt": 1767225600000,
  "quote": "Words from the transcript at that moment",
  "note": "Optional note",
  "episodeTitle": "Episode title",
  "showTitle": "Show name",
  "feedUrl": "…",
  "enclosureUrl": "…",
  "episode": { "id": "…", "title": "…", "artist": "…", "artUri": "…", "durationMs": 3600000, "extras": { … } }
}
```

`episode` is a snapshot that lets Riff Mobile play the episode again;
other clients can ignore it (but keep it, see "Unknown fields").

### `podcasts/segments.json`: `podcast.segments`

Stretches of episodes the listener marked by hand (ads, intros, …). Id:
`<episodeId>#<segmentId>`.

```json
{
  "episodeId": "podcast_123",
  "segmentId": "m_1767225600000",
  "start": 61.5,
  "end": 125.0,
  "category": "sponsor",
  "feedUrl": "…",
  "enclosureUrl": "…"
}
```

`start` and `end` are seconds from the start of the episode. `category`
uses SponsorBlock's category names (`sponsor`, `selfpromo`, `intro`,
`outro`, `interaction`, `preview`, `music_offtopic`, `filler`).

### `library/playlists.json`: `library.playlists`

Playlists. Id: the playlist id. Riff Mobile uses `LIB<number>` for its
own playlists and the YouTube Music playlist id for saved YouTube Music
playlists. Favourites aren't a playlist here; see `library.favorites`.

```json
{
  "title": "Road trip",
  "description": "",
  "thumbnailUrl": "https://…",
  "kind": "local",
  "songs": [
    {
      "videoId": "dQw4w9WgXcQ",
      "title": "Song title",
      "artists": [{ "name": "Artist", "id": "UC…" }],
      "album": { "name": "Album", "id": "MPRE…" },
      "durationSec": 213,
      "thumbnailUrl": "https://…"
    }
  ]
}
```

- `kind`: `local` (made in a Riff app, `songs` in order) or `youtube` (a
  saved YouTube Music playlist; `songs` is empty because the app loads it
  from YouTube Music).
- Songs may carry more fields; see "Unknown fields".
- A whole playlist is one record: if two devices change the same
  playlist between syncs, the later change wins.

### `library/favorites.json`: `library.favorites`

The liked songs. Id: the song's YouTube video id. `data` is the song, in
the same shape as a song in `library.playlists`. Every device has a
Favourites list, so it syncs song by song: liking a song on one device and
another song on a second device keeps both, and un-liking leaves a
tombstone.

## podcasts/subscriptions.opml

The subscriptions are an OPML 2.0 file, so other podcast apps can import
it directly. Riff's own fields use the namespace `urn:riff:sync:1`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0" xmlns:riff="urn:riff:sync:1">
  <head>
    <title>Riff podcast subscriptions</title>
    <riff:sync version="1" updatedAt="1767225600000" device="3f9a…"/>
    <riff:tombstone xmlUrl="https://old.example.com/feed.xml"
                    updatedAt="1767225500000" device="3f9a…"/>
  </head>
  <body>
    <outline type="rss" text="Show" title="Show"
             xmlUrl="https://example.com/feed.xml"
             riff:updatedAt="1767225400000" riff:device="77b1…"
             riff:author="Host name" riff:artwork="https://…/art.jpg"/>
  </body>
</opml>
```

- Id: `xmlUrl`.
- Each `<outline>` in `<body>` with an `xmlUrl` is a live subscription.
  `text` / `title` is the show name; `riff:author` and `riff:artwork` are
  optional.
- `<riff:tombstone>` in `<head>` marks an unsubscribed feed.
- An outline without `riff:updatedAt` (for example, one added by another
  podcast app) counts as `updatedAt` `0`.
- Unknown attributes and elements should be kept, as for JSON.

## Order of a sync

1. Read `manifest.json`. If its `version` is too new, stop.
2. For each collection: read, merge with local data, apply the result
   locally, and write the file back if the merge changed it.
3. Write `manifest.json` if anything changed.

Each file is merged and written on its own, so an interrupted sync leaves
every file valid.
