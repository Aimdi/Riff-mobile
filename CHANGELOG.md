# 1.7.133

**A new Home**
* Your own music comes first, always in the same order: Jump back in,
  Riff Wave, Speed dial, Quick picks, your mixes and shows, Your week, then
  up to four YouTube Music shelves and an Explore more button for the rest.
  The YouTube feed can no longer push Riff Wave, Speed dial or Quick picks
  down, and empty sections leave no gap
* Jump back in: the queue you left, podcast episodes and audiobooks in
  progress, as up to four tiles with a progress bar. Tap to resume,
  long-press for more
* One row of stations under Riff Wave: Fresh finds, Rediscover, Energize,
  Feel good, Relax and Workout. Every chip starts playing. Explore moved
  to the top bar, next to Stats and Search; YouTube's genre chips are on
  the Explore page now
* Speed dial: no play buttons on the covers; the song that's playing shows
  a moving equalizer. Long-press an album, playlist or artist on any shelf
  to pin it to Speed dial
* Quick picks: bigger cards, with the next one peeking in and a Play all
  button
* Shelves: one card size per kind (covers, round artists, wide videos),
  no badges on covers, and each song, album or playlist appears only once
  on Home. Charts and hits shelves are merged into one, and so are mood and
  time-of-day shelves; Throwback is gone (Rediscover covers it), and
  shelves with too few items or mostly missing covers are hidden
* Missing covers show a coloured tile with the first letter of the title
  instead of a music note
* Headers are in sentence case. Home draws behind a transparent status
  bar, and the end of the page clears the mini player
* The side rail keeps its width when Songs is expanded, and TalkBack reads
  every rail item, chip and card
* Home layout in Settings now switches sections on and off; the order is
  fixed

**Fixes**
* Your week no longer names "Podcast" as your top artist: podcast
  episodes and audiobook chapters don't count toward top artists in Your
  week, Stats or Rewind

# 1.7.132

**Spotify Connect (Premium)**
* New in Spotify settings: Spotify Connect. Play songs, playlists, albums,
  Liked Songs and your top tracks on any of your Spotify devices (the Spotify app
  on this phone, a computer, a speaker), straight from Riff. The music
  plays in Spotify itself, so it's the real Spotify recording; Riff's own
  player isn't touched
* The speaker icon on the Spotify screen opens a remote: what's playing,
  play/pause, skip, seek, volume, and moving playback to another device
* Playlists that Spotify doesn't let Riff list can still be played on a
  Spotify device
* Needs Spotify Premium, and two more permissions the first time you turn
  it on. If no device is awake, Riff offers to open Spotify

# 1.7.131

**Spotify: likes and radio**
* New in Spotify settings (the sliders icon in the Spotify screen): Send
  likes to Spotify. Off until you turn it on. Songs you like in Riff go
  into your Spotify Liked Songs a few seconds later, and come out again if
  you unlike them in Riff. Songs you liked on Spotify yourself are never
  removed by Riff. Spotify asks for one more permission the first time
* Add Spotify Liked Songs to Favorites: finds each song on YouTube Music
  and adds it to your Riff Favorites in one go
* Spotify radio (the radio icon): a mix from your Spotify top tracks,
  recent plays and Liked Songs, at most 3 songs per artist and never the
  same artist twice in a row when it can be helped. Long-press a Spotify
  song for a radio from that song: its artist first, then artists in the
  same genres

# 1.7.130

**Spotify, played through Riff**
* The Spotify plugin is now a full Spotify library: Liked Songs, your
  playlists, saved albums, followed artists, top tracks and artists,
  Recently played, and Spotify search. Everything plays in Riff: each song
  is matched to YouTube Music, songs are matched once and remembered, and
  playback starts as soon as the first song is found
* Wrong version (a live take, a cover)? Long-press the song › Change
  match… and pick the right one; Riff always plays your pick from then on
* Spotify's song codes (ISRC) are now used to find the exact recording
* Signed in? A Spotify tile appears in your Library
* Spotify only shares the songs of playlists you made or collaborate on;
  others show a note and can be imported by their link if they're public
* Sign-in tokens now live in the phone's secure storage. When Spotify
  ends a session (sign-ins last six months), Riff says so and asks you to
  sign in again. Sign in once more to see Recently played
* Clear messages when Spotify refuses (Premium needed for the Spotify
  app's owner, a user not on the app's list, too many requests); Riff
  waits as long as Spotify asks before trying again

# 1.7.129

**Sync through WebDAV**
* New: Settings › Advanced › Sync. Connect a WebDAV folder you own
  (Nextcloud, ownCloud, a NAS, …) and Riff keeps your podcast
  subscriptions, where you are in each episode and which you finished,
  bookmarks, the segments you marked, your playlists and Favorites the
  same on all your devices
* Test the connection before saving; the password is kept in the
  phone's secure storage. Sync now, or turn on Sync automatically (when
  Riff opens and when you leave it)
* The files are plain JSON, plus an OPML subscription list that other
  podcast apps can import, in a Riff folder on your server. The format is
  documented in docs/sync-format.md, so Riff on the desktop can use the
  same folder
* Edits made on two devices are merged item by item, and the later edit
  wins. Deleted items stay deleted everywhere. If two devices sync at the
  same moment, Riff reads the file again and merges once more, so nothing
  is overwritten

# 1.7.128

**Android Auto, Never play, CSV import**
* Android Auto: long lists (big playlists, your library, a show's
  episodes) come in pages or in sections of 100, so they no longer fail
  to open in the car. New in the car: Podcasts, with Continue listening
  and the shows you follow
* Never play now covers artists and albums everywhere: Daily Mixes, Riff
  Wave, radio, autoplay and recommendations all leave them out. A song's
  menu offers Never play this album, and Never play this artist bans the
  song's main artist (before, it only matched that exact artist line-up)
* Settings › Never play is now a full page listing artists, albums and
  playlists, and songs, each with Allow again (and Undo)
* Import a playlist from a CSV file: Exportify and TuneMyMusic exports
  (or any CSV with title and artist columns), from the Spotify import
  window. ISRC codes in the file are used to find the exact recording,
  and you get a list of what matched and what didn't

# 1.7.127

**Playback hardening**
* Riff now keeps track of who asked for each play, pause, seek and skip
  (you in the app, the notification or lock screen, Android Auto, a
  headset, the sleep timer, automatic skipping)
* A playback watchdog checks every couple of seconds while something
  plays, screen off included. If the position stops moving while the
  player says it's playing, it gets it going again (seek in place, then
  pause and play); if the notification or app shows the wrong play/pause
  state, it corrects it. It never restarts something the system paused
  (a call, another app)
* Automatic skips (podcast segments and SponsorBlock) no longer override
  a seek you just made, whether from the app, the notification or Android
  Auto, and leave a segment alone for a minute when you jump to just
  before it
* Automatic skips duck the sound for a moment and fade back in instead
  of cutting hard

# 1.7.126

**Podcasts: smart touches**
* Expected today: at the top of the Inbox, the shows you follow that
  usually release on this day, with roughly when. It needs a few weeks of
  history from the show's feed; YouTube shows don't give release times, so
  they don't appear. Once the episode is out it shows up in the list
* The podcast player takes its colour from the episode's artwork. Turn it
  off in Podcast settings › Player. Music keeps your theme
* The Podcasts tab opens straight onto your last Inbox, even after
  restarting the app, and refreshes behind it with a thin bar at the top
  instead of a loading screen
* Listening stats (chart icon in the Podcasts tab): time listened, time
  saved by faster playback and by skipping, your listening streak and top
  shows. Share them as a picture. Podcasts only

# 1.7.125

**Podcasts: a tidier library**
* Keep latest episodes: choose how many unplayed episodes of a show stay
  in the Inbox and Queue (1, 3, 5, 10 or all). Older ones step aside when
  new ones arrive; they're still on the show's page, and episodes you've
  started are never moved. Set a default in Podcast settings, or per show
  from the menu at the top of its page
* Delete downloads after listening: never, right away, or after 24 hours.
  Default in Podcast settings, per show from its page. Bookmarks stay
* Mark all as listened, from a show's page menu, with Undo
* Filters in the Inbox: New, In progress, Queued, Downloaded, Bookmarked
  and Under 20 min
* Folders can now hold shows you follow by feed too (long-press a show in
  Subscriptions), and you can drag folders into order
* Import and export your podcast subscriptions as OPML, in Podcast
  settings, to move between podcast apps
* Queue: swipe an episode away to remove it (with Undo). The episode menu
  has Play last next to Play next

# 1.7.124

**Podcasts: transcripts and bookmarks**
* YouTube podcast episodes now have transcripts too, made from the
  video's captions. Feed transcripts still come first. The Transcript
  button only shows when an episode has one
* Transcripts are kept on the phone after the first time you open them
* In the transcript: the current line follows playback. Scroll away
  and a Resync button brings you back. Tap a line to jump there
* Search the transcript, with the number of matches and up / down to
  step through them
* The eye button hides what's ahead (blurs the lines you haven't heard
  yet)
* Sponsor reads, intros and other segments are shaded in the transcript
  with their seek-bar colour and name
* Long-press a line to bookmark it, and add a note if you like.
  Podcast player › ⋮ › Bookmark this moment works without a transcript
* Bookmarks in this episode: in the podcast player's ⋮ menu and the
  transcript header. All bookmarks: the new Bookmarks tab in Podcasts.
  Tap one to play from that moment, or share it as a quote

# 1.7.123

**Podcasts: smarter segment skipping**
* Podcast settings › Segment skipping: choose what happens with each
  kind of segment (sponsor, self-promotion, like / subscribe reminders,
  intro, outro, preview / recap, off-topic tangent, non-speech music):
  skip automatically, show a Skip button, mute, or ignore. Sponsors are
  skipped, self-promotion and reminders get a button, the rest is left
  alone unless you change it
* YouTube podcast episodes now use SponsorBlock with its private lookup
  (only a short hash of the episode is sent), remembered for a day. RSS
  episodes use the show's own chapters, as before
* Segments show as coloured marks on the podcast seek bar; the colours
  are listed in Podcast settings
* After an automatic skip a message says what was skipped and for how
  long, with Undo to go back and hear it
* Skipping only happens when playback runs into a segment; jumping into
  the middle of one plays it, and nothing is skipped twice
* Mark your own segments: podcast player › ⋮ › Mark segment start /
  end. The same menu lists the episode's segments
* The "Skip podcast ads" switch moved from Settings into Podcast
  settings, keeping your choice. Each show can still turn automatic
  skipping off on its page
* Riff counts the listening time skipping saves you

# 1.7.122

**Podcasts: playback settings per show**
* New Podcast settings page, from the gear in the Podcasts tab header.
  It sets how podcast episodes play: speed (0.5× to 3×), skip back and
  skip forward lengths, trim silence, voice boost and ad skipping.
  Music keeps its own speed and settings
* Each show can have its own playback settings: tap the sliders icon on
  the show's page. "Use global defaults" goes back to the Podcast
  settings
* Episodes play with their show's settings, also when the next episode
  starts by itself. Switching to music puts music's settings back
* The podcast player's skip buttons use the show's lengths, and the
  media notification gets skip back / skip forward buttons for podcasts
* The speed button in the podcast player opens a speed picker with a
  slider and quick choices
* Smart resume: after a pause, an episode goes back a few seconds (more
  after a longer pause) so you don't lose the thread. On by default, in
  Podcast settings
* Sleep timer for podcasts: stop at the end of the current chapter, and
  episodes fade out over the last 10 seconds instead of cutting off
* Your current speed and trim-silence settings carry over as the new
  podcast defaults, so nothing changes until you change it
* Fixed: some YouTube Music podcasts opened with no episodes (the show
  was found under a different id form)

# 1.7.121

**The side rail is back**
* Phones use the side rail on the left again (Home, Songs with
  Playlists / Albums / Artists, Podcasts, Audiobooks, Settings). The
  floating bottom tab bar and the one-page Library from 1.7.119 are gone
* The mini player is the full-width strip at the bottom again
* Home keeps its new layout: Riff Wave and the generators up top, the
  smaller Quick picks further down, and Settings › Home layout

# 1.7.120

**Home: Riff first, Quick picks further down**
* Riff Wave and the Fresh finds / Rediscover / Explore / New releases
  chips now sit right under the greeting, before the speed dial
* Quick picks is a smaller carousel (cards about half the screen wide)
  with its own title, near the bottom of Home after YouTube Music's
  shelves
* If you already arranged Home yourself under Home layout, your order
  is kept

# 1.7.119

**The app, laid out the Echo Music way**
* Phones get Echo's floating tab bar: a pill with Home, Library,
  Podcasts and Audiobooks and a round Search button beside it. The
  side rail is gone on phones (tablets keep it). The mini player docks
  above the bar, and both slide away as the player opens
* Library is one tab with Songs / Playlists / Albums / Artists chips
  under the title, like Echo's library filters
* Home opens with the app name, the greeting under it, and the stats
  and settings buttons on the right
* Quick picks is Echo's hero carousel for real now: one big card
  (290dp tall, like Echo's) centred with the neighbours peeking in on
  both sides, snapping page by page, with no title over it, moving on
  by itself every five seconds

**Put it anywhere**
* Settings › Library & sync › Home layout: drag Home's sections into
  any order and switch off the ones you don't want (chips, continue
  listening, quick picks, speed dial, Riff Wave, generators, daily
  mixes, YouTube Music shelves, your week)
* Long-press a section on Home to move it up or down, or hide it,
  without leaving the page

# 1.7.118

**Home**
* The chips under the greeting are YouTube Music's own (Relax,
  Energize, Workout, Focus, …). Tapping one reloads Home with that
  mood's shelves; tapping it again brings the usual feed back. Riff's
  mood chips stay as the fallback when YouTube sends none (offline)

# 1.7.117

**Home, organised the Echo Music way**
* Section titles are small, bold, upper case and muted, across the app,
  so the artwork carries the page and the labels just organise it
* Quick picks is a compact hero carousel: the centred cover leads, the
  next one peeks in smaller, the title sits over the art, a badge shows
  what is playing, and it moves on by itself every 5 seconds until you
  swipe it
* Speed dial comes right after, and its last tile is a dice that plays
  the dial shuffled
* The top is lighter: no library shortcut tiles (Favorites, Recently
  played and Downloads are in the Songs tab). Fresh finds, Rediscover,
  New releases and Explore are one row under Riff Wave

# 1.7.116

**Home**
* Home is a real timeline again. It fetches nine YouTube Music shelves
  instead of three, keeps the song shelves ("Listen again", "Forgotten
  favourites", …) and artist shelves it used to drop, and shows every
  shelf in full under the speed dial instead of squashing them into a
  chip row with one rotating carousel
* Quick picks is an ordinary section again; the paged cover grid comes
  right after Riff Wave
* "Your week" at the end: plays per day and your top artist, from the
  local listening history, opening Stats
* Explore is a shortcut chip next to Favorites and Recently played

# 1.7.115

**Design**
* Home's first screen is lighter: the library and discovery shortcuts
  are one scrolling row of chips, Riff Wave is a single-row card, and
  the big Quick picks covers sit right under the mood chips

# 1.7.114

**Design**
* Every remaining screen now matches the new look: the song menu, sleep
  timer, add to playlist, queue, create playlist and sort sheets; the
  Artists tab, Explore, Stats and Rewind; podcast categories, downloads,
  folders, queue, inbox and subscriptions; Plugins, Cloud, Audiobookshelf,
  Spotify Bridge, SoulSync and Seeker
* Backup, restore, export, playlist export, Piped, song info, update and
  Spotify import dialogs, and the podcast transcript, share one style
* Filled buttons use your accent color instead of a default blue
* Home opens with mood chips, Quick picks as big swipeable covers and a
  3×3 "speed dial" of recent songs; the player's cover fills the top of
  the screen with the title over it; the mini player is a floating pill

# 1.7.113

**Fixes**
* Settings › Podcasts showed a grey box instead of the row
* Shared YouTube links: a link YouTube answers without details (bot
  check, region block) now opens; a failed lookup no longer leaves the
  loading spinner up forever; bare or incomplete links show a message
* Artist pages that can't load show an error with Retry instead of
  loading forever
* Song menu: Go to album works for songs without an album id; deleting a
  download after leaving its playlist and removing a song that isn't
  stored no longer fail; Never play / Add to queue confirmations show
* Spotify import, Piped unlink and the Home cache setting no longer close
  storage other screens are using ("box already closed")
* Piped login no longer takes Home away if its dialog was closed early

# 1.7.112

**Fixes**
* Riff no longer closes as soon as something starts playing. Since 1.7.108
  the release build dropped the notification icon as unused, and Android
  killed the app when playback posted its notification. Podcasts, songs
  and audiobooks were all affected
* Starting an episode while Favourites, Recently played or a playlist was
  open no longer breaks the player's bookkeeping ("box already closed")

# 1.7.111

**Podcasts**
* An episode never opens with video on its own: podcast video is off each
  time Riff starts and only turns on from the Video button. A saved
  "video on" choice from an older version is cleared
* Episodes streamed straight from YouTube send the headers of the client
  the stream was issued to, as NewPipe does

**Diagnostics**
* Settings › App info › Copy diagnostics: the version, the last unexpected
  exit and the recent log, ready to paste into a bug report
* The crash dialog now includes what the app logged before it stopped,
  and shows a recorded crash even when Android kept no exit record

# 1.7.110

**Crash reports**
* After an unexpected close, the crash details now include the error's
  stack trace, ready to copy and send
* The first crash after an update is no longer skipped

# 1.7.109

**Podcasts**
* Tapping a show opens its page instead of starting an episode; search
  results are a list with a subscribe button
* New show page: cover, Latest episode / Resume, About, and episodes with
  notes, progress and newest/oldest sorting
* Podcasts and audiobooks get their own player: 10s back, 30s forward,
  speed, sleep timer, show notes or chapters
* Fixed the crash when an episode of a show with many episodes started;
  podcast video is now opt-in
* After an unexpected close, Riff offers the crash details to copy

**Browsing**
* Playlists, albums and artists open their page on tap; the ▶ on the cover
  and long-press still play. Same for Favorites, Recently played and
  Downloads

**Player**
* The Gesture player style matches the new player

# 1.7.108

**New look**
* Home, now-playing, Podcasts, Library (Songs, Playlists, Albums),
  Audiobooks, Search, artist, album, playlist and Settings pages share one
  layout: 12dp edges, the same section headers and cards, one big green
  Play with secondary actions in a ⋮ menu
* New app icon: equalizer bars

**Audiobooks**
* Free public-domain LibriVox audiobooks play in-app, with chapters,
  resume, genres, search and Saved

**Search**
* Result filters are pills under the search bar (the side rail never drew)
* Long-press a search for all results; suggestions bold the new words

**Artists**
* Videos shelf and View all for songs, videos, albums and singles
* One Follow button; radio, podcast subscribe and share in the ⋮ menu

**Settings**
* Search now filters settings; sections are cards with a summary
* Video player row no longer shows an error on the Lite APK

**Video & podcasts**
* Native ExoPlayer video engine; YouTube podcasts, with Open in WizeStream

**Fixes**
* Home grey-box crash; shuffle skipping and stale loads
* Opening a second artist page no longer crashes ("box already closed")
* Podcast date parsing, feed jank and lyrics races; smoother scrolling

# 1.7.107

**Player**
* Straight Spotify-style seek bar; podcasts with chapters show section gaps
* Volume slider removed from now-playing (use the phone’s buttons)

**Podcasts**
* Subs covers load through the same path as the old grid, with a browser
  User-Agent so Apple/Google art is not 404’d
* Empty subscription artwork is filled from Apple’s directory

# 1.7.106

**Podcasts**
* Subs covers retry the stored artwork when the upscaled CDN URL 404s, so
  followed shows keep their real thumbnails instead of the Riff note

# 1.7.105

**Player**
* Audio keeps playing while a YouTube video stream is still loading
* Play/pause stays tappable — buffering no longer replaces the green button
  with a spinner

**Podcasts**
* Subs uses a 2-column large-cover grid with play overlays
* Discover similar-show rows are 148px tiles, three “Because you follow”
  shelves, and a short kicker instead of cramped 64px chips

**Settings**
* Listening starts collapsed, like Appearance and the other groups

# 1.7.104


**Discovery**
* Play paths stamp a discovery source (home, search, album, playlist,
  artist, cloud, podcast, downloads, Soulseek, radio, mixes)
* Stats record listen fraction, skips, and last source instead of assuming
  every play was heard in full
* Daily Mix, smart radio, and similar songs rank by listen fraction, skip
  rate, and source — downloads and playlists beat radio noise
* Home shelves play with the matching source; Fresh Finds stays tagged
* Fresh Finds shortcut and Android Auto library songs keep the right source

**Look & feel**
* Search, artist, album, playlist, podcast, audiobook, cloud, and similar
  lists use themed song-row shimmer instead of a spinner

**Maintainability**
* Shared Hive box accessors and typed `MediaItem.extras` helpers
  (favorites, podcast / audiobook flags, discovery source)

**Cache**
* Auto-cached songs expire by LRU / least-recently-played against a
  1 GB default (500 MB–5 GB or unlimited) and a 30-day age cap
* Now-playing and queued tracks are never evicted; downloads are never
  auto-deleted
* Settings shows cache / download / image sizes and can clear cached
  songs or images

**Reliability**
* First play can prompt to disable battery optimization so background
  radio is not killed

# 1.7.103

**Playback**
* Album, playlist, search, Soulseek, torrent, audiobook, Spotify, cloud, and
  subscription rows play on tap instead of only the overflow play button
* Play next waits for the song to land in the queue before claiming success
* Radio skip keeps the station going instead of dying at the last cached track
* Previous / next report whether the skip actually started

**Honesty**
* A tap that never resolved a stream, died after the URL was handed off, or
  failed a video handoff no longer pretends play started
* Failed video enable resumes the audio track instead of leaving silence
* Enqueue, play next, ban, playlist add, sleep timer, cache clear, download
  delete, continue, cloud play, and settings reset snack when they no-op
* English strings cover Soulseek, podcasts, torrents, mix, and video settings

**Fixes**
* End-of-track no longer double-skips
* Shuffle miss and a stale play-by-index no longer leave the player spinning
* Heart like no longer flips back after a successful save

# 1.7.102

**Playback**
* Home, Library, and Search play on tap — Jump back in, shortcuts, Daily Mix,
  Quick Picks, discovery shelves, Downloads, and Songs Play all / Shuffle
* Artist albums, playlists, and related artists play on tap; long-press opens
* Podcast discovery episodes play the shelf; Search Enter plays the top song
* Cloud random mix plays after fetch; Play all on the loaded slice
* Previous restarts the current track after three seconds
* Mini-player long-press opens the current-song sheet

# 1.7.101

**Look & feel**
* Quick Picks and song rows drop stock Material ListTile chrome for denser
  Riff rows with muted artists and soft current-song highlight
* Search loses the empty left rail; the field is filled elevated; history and
  empty states are clearer
* Wave mood chips are quieter; content tiles no longer stamp P/L letter badges
* Image placeholders and shimmer use Riff elevated surfaces; light theme accent
  is Riff green

**Performance**
* Song-tile Obx only updates highlight chrome — art and marquee no longer
  rebuild on every skip
* Search overview lists cap preview rows instead of force-building every tile
* Up Next uses a fixed item extent; queue panel drops expensive backdrop blur
* Podcast and album/playlist hero images decode at display size

**Fixes**
* Cold-start play / Wave waits for AudioService instead of crashing
* Song / queue sheets no longer bang a null scaffold context
* Exhausted stream auto-retry stops the broken player cleanly
* Null-safe extras and lyrics mode toggle

# 1.7.100

**Audiobooks**
* Your whole Audiobookshelf library loads, not just the first 50 titles
* A failed load now says why — an expired session, a server error, or an
  unreachable server — with a retry button, instead of claiming the library
  is empty

# 1.7.99

**Audiobooks**
* Audiobookshelf bookkeeping now survives an app restart — after a session
  restore a book could still play, but could no longer refresh an expired
  stream URL or report its position anywhere
* Opening a book resumes where you left off, preferring the position stored on
  this device over the server's, which lags behind
* Uploading a book streams from disk instead of reading whole files into
  memory, so large multi-part books no longer risk being killed mid-upload
* The catalog and upload screens show real text instead of raw key names

**Podcasts**
* Switching away from an episode no longer measures it against the *next*
  item's length — a long episode followed by a short track was treated as
  finished and vanished from Continue Listening
* Saved progress no longer points at a download you have since deleted
* HTML entities in shownotes and transcripts are decoded

**Spotify**
* New opt-in Spotify bridge plugin: sign in with your own Spotify app and
  import your playlists, played from Riff's existing free sources
* Imported playlists pick the right recording instead of the first search hit,
  so remixes, live cuts and sped-up uploads stop slipping in
* Track lengths are filled in from Deezer's public metadata when Spotify omits
  them, which is what makes that matching work

# 1.7.98

**Release**
* Re-ship with the previous release signing key so 1.7.98 installs over earlier
  APKs (1.7.97 had fallen back to debug signing after the keystore was
  untracked from the repo)

# 1.7.97

**Look & feel**
* Player chrome uses Riff surfaces end-to-end: Up Next strip, accent play button,
  art depth, quieter “Playing from”, fixed mini-player progress polarity, and a
  snappier waveform scrub
* Home Wave hero is larger and clearer; Daily Mixes show collage cards with the
  mix title first; Quick Picks are denser; Explore chips match the brand
* Library and Search show a green current-song cue, denser artist rows, Recent /
  Suggestions headers, and tighter search chrome
* Mini-player title crossfades on track change; Listening settings open by default

**Playback & podcasts**
* Dead streams auto-retry with a fresh URL and keep your position (manual Retry
  does too)
* Search suggestions are debounced; Daily Mixes appear from cache immediately
* Podcast Downloads hub is playable with metadata; `feedUrl` survives Continue /
  Up Next; finished episodes leave the queue
* Cold start paints before AudioService finishes init

**Security & data**
* Sensitive credentials migrate into secure storage
* Release keystore files are no longer tracked (copy from a secure store for
  local release builds; CI falls back to debug signing when missing)
* Corrupt Hive boxes recover via safe open instead of bricking launch

# 1.7.96

**Playback resilience**
* Remote client config now refreshes the moment a stream fails, instead of only
  once per cold start behind a 12h timer — a published fix reaches users in
  minutes rather than up to a day
* Config downloads are validated before being cached, so a malformed emergency
  fix can no longer be stored and silently ignored
* Network waits are bounded: a hung NewPipe resolve now falls through to the
  fallback player clients instead of blocking them forever

**Lyrics**
* LRCLIB lookups no longer send a literal "null" album to the exact-match
  endpoint, which had been guaranteeing a miss for search, radio and
  watch-playlist tracks; parameters are now properly encoded and time-limited
* KuGou no longer caches the wrong track's lyrics forever when its top result's
  duration is clearly wrong

**Fixes**
* Settings and the update check read the real app version instead of a
  hardcoded string that had drifted 16 patches behind
* Sorting albums by "Date" sorts by year and by "Name" sorts by title — the two
  comparators were inverted
* Shuffle no longer drops the currently playing track each time the queue grows,
  which had been compounding on every radio continuation
* A single play is logged once; re-emitted track events no longer inflate play
  counts, scrobbles, and skip signals
* A track whose duration never resolved is no longer scored as a full listen by
  the discovery engine

**Project**
* The test suite runs on every push (197 tests) and the live YouTube API
  diagnostics run nightly, so a player-client rotation surfaces before users
  hit it

# 1.1.0 — Discovery redesign
* Local private taste model (affinity, familiarity, co-occurrence, impressions, skip learning)
* Shared recommendation pipeline for radio, similar songs, and generated mixes
* Smart radio with exploration control (Settings → Riff → Discovery)
* Similar songs sheet + More like this play next + player Similar row
* Daily Mixes, Fresh Finds, Release Radar, Rediscover (resume-time generation)
* Personal Home sections after enough listening signal (cold start unchanged)
* Follow artists (library) for Release Radar; Android Auto mix folders
* Stats: exploration ratio, rising artists, kept-from-Fresh-Finds
* Unit tests under test/discovery/

# 1.12.2
* Added wakelock support to keep screen awake while playing music (can be toggled from settings)
* Enabled downloading in external storage for Android devices
* Fixed Home discover content loading issue
* Added more options to export playlist (CSV file & Direct export to YT Music (Song limit - 50))

# 1.12.1
* Fixed Search issue
* Fixed Artist-song content

## 1.12.0
* Redesigned Album & Playlist screen
* Added Basic Interface for Android Auto #496 #492 #427 #111
* Import/export functionality for playlists by @ani-sh-arma
* Android splash screen implemention for all devices by @girish54321
* (Windows)-TitleBar Color implementation
* Fixed Album,Single loading issue in Artist acreen #509
* Fixed Miniplayer in landscape mode #462
* Fixed playlist add ui overflow #500
* Fixed restoration of downloaded songs #552
* Fixed Chinease language issue #548
* Fixed trigger dynamic mode for offline songs #537
* Fixed screen freeze issue in Android #348 #492

## 1.11.2
* Fixed rendering issue in Android (happening due to flutter upgrade)

## 1.11.1
* Fixed Missing playlist content #437
* Fixed - Album original tracks are not available in album #439,#440 and #299
* Added right click support for opening song context menu #431
* Added option to enable/disable auto opening of player full screen #273
* Added More tags for album songs #404,#293
* Player screen enhancement (Android) #432
* Changed icon style and app font
* Made pause play button animated
* Updgraded AGP
* Replaced Device Equalizer & SDKInt package with binding generated with jnigen (Tried to fix Equalizer in Android)

## 1.11.0
* Fixed Stream issues
* Added feature to restore settings to default
* Fixed: Android swipe gesture navigation cause half-way drag on player page #367
* Updated language data

## 1.10.4
* Fixed stream issues
* Fixed cross platform data restore issue

## 1.10.3
* Fixed Song is not playable due to server restriction!
* Added option to swipe to queue item removal and queue clear 
* Desktop Full Screen player (Will open on clicking song title in mini player)
* Automatically download favorite songs #164 (Enable it from settings)
* Redirect to home before exiting 
* Enabled download option for fav playlist
* Fixed Can't capitalize letters in playlist titles
* Fixed Last song in queue is covered on Android
* Fixed search button height in Android
* Fixed opening of album from song when album is already bookmarked

## 1.10.2
* Fixed Song is not playable due to server restriction!
* Added hl code #298

## 1.10.1
* Improved song loading time (Android)
* Added slide gesture to song tile for playing next song by @DarkNinja15
* Optional feature: Gesture based player (Android)
* Prettified title on Windows app #279 (Windows)
* Fixed art img size
* Feature: Queue loop #234
* Fixed Stop music on task clear not working #268 (Android)
* Transparent bottom #177 (Android)
* Added null check on genID from Db #278
* Enable loading on Buffering #170
* Fixed AppImage don't play (Linux)


## 1.10.0
Fixes:
* fix: allow use of qt window decorations by @Merrit
* fix: system tray causing crash on linux by @Merrit
* Fixed Won't load big playlists #222
* Fixed tab ui mismatch issue #239
* Fixed griditem overlap in library playlist section #239
* Fixed song restarts from beginning when radio is enabled #223
* Fixed - Repeatative entries from Recently played can be removed #261
* Changes in downloader & Fixed issue - Audio from videos will not download #264

Features:
* Poweramp support #82
* Enabled backup and restore feature for Android #90 #250
* Made App landscape mode compatible #218 #115
* Added support for direct opening of YTM links #242
* Added song info for current song #201
* Added option to view lyrics in desktop mode #226
* Added play/pause feature using spacebar #249
* Added scrollbars for horizontal contents for desktops #249
* Added button to minimize full screen player #249
* Added shuffle mode #174 #252
* Added searchbar in homescreen for desktops #249
* Added loudness normalization feature (Android) #15 #243
* Added app version info & customized settings screen #254
* Added feature to browse content using url via search #203

## 1.9.2
* Fixed Showing Black screen #197
* Fixed loading of deeplink playlist #198
* Fixed broken things #210,#209,#198
* Backup & restore feature for Windows by @encryptionstudio


## 1.9.1
* Added volume slider for desktop app #169
* Added open in youtube/youtube music option #189
* fixed list widget size issue android
* fixed queue rearrange issue android #165
* Ucommented audiotags implementation for Auditag #163
* Fixed song removal issue #162
* Fixed Small Thumbnail issue #158 & #183
* Fixed Album & playlist stuck on exception #192
* Fixed Enabled/disabled color of toggles are misleading #178
* Fixed RP playlist song order & added option for deletion #179


## 1.9.0
* Added Windows and linux platform support #136
* Added feature to rearrange local playlist, add multiple songs to plalist, delete multiple songs #153
* Added feature to export downloaded files to external storage #157
* Added feature to restore last playback session #121
* Added feature to cached home content data #133
* Added feature to remove song from downloads from bottom sheet #143
* Added option to disable transition animation #150
* Loading indicator added in play/pause button #134
* Fixed HM is categorized as browser #142
* Used isolate to fetch song url #133
* Fixed songs are not in the correct order in offline/bookmarked album #132
* added artist name in downloaded filename to resolve issue #152
* Added system tray support for desktops and provided option for background playing

## 1.8.0
* Added feature to switch to Bottom Navigation Bar (Major Change) #95 #58
* Synced Lyrics feature added #66 #116 #98 (Data provided by lrclib.net)
* Added x button to clear search query #92
* Added Search history #128
* Sleep Timer feature added #118 #109
* Added feature to ensure offline availability of bookmarked Album/playlists #113
* Highlight for now playing song in playlists #97
* Changes made for remember last session selection for loop mode #127
* Added functionality to remove invalid char from file name to fix issue #129
* Downloaded thumbnail support for downloaded song
* Added option to set no of homescreen content (approx)
* Fixed app flagged as TROJEN in virustotal #122
* Fixed song album id issue for songs in album
* Fixed playlist sort issue
* Fixed null album issue
* Improved app animation #83
* fixed thumbnail url issue
* New language support Interlingua, Esperanto and updated other langs thanks to @softinterlingua, @Kjev666, @maboroshin, @trunars, @gallegonovato, @nexiRS, @WaldiSt, @MattSolo451, @


## 1.7.0
* Added feature to download whole playlist/album #79 & #100
* Added Replay on previous feature #101
* Fixed Result tab alignment & playlist screen intial flickr
* Fixed piped custom instance issue #103
* Fixed (increased) Lockscreen's album art image quality #96
* Translation completed Azerbaijani,Indonesian,Japanese,Portuguese,Chinese and some correction in other lang translation. Thanks to @Qaz-6,@Hada45,@maboroshin,@S4r4h-O,@raymond-nee,@siggi1984,@PonyJohnny,@MattSolo451,@hoabuiyt

## 1.6.0
* App language support #21 #54
* Selective song download feature #40
* Fixed - Songs can not be deleted from the cached/offline #68
* Changed app font
* Fixed - Offline playlist rename/delete issue

## 1.5.0
* Added search feature where required - Feature requested in #45 
* Fixed - loop song does not work #49
* Fixed - screen mismatching issue #57
* Fixed - Home page not loading #59
* Fixed - Some songs are not playing, it remains paused #60 
* Fixed type #62 & made test more brighter #61

## 1.4.0
* Piped playlist integration - Feature requested in #28 
* Option added  in settings to stop music on app cleared from ram/task #30
* Fixed full song name in playlists #32
* Fixed not appearing all songs in bookmarked platlist #37
* Fixed - not able to scroll till the last song #44 

## 1.3.2
* Patch version for issue #34
* Upgarded packages & update kotlin version

## 1.3.1
* Android Auto support
* Fixed Artist content

## 1.3.0
* App Link/Deep link support
* Miniplayer progressbar fixed 
* Home Content list changed from column to listView

## 1.2.0
* Discover content selecter added in settings
* Equalizer support added
* Lyrics support added
* images resolution changes done
* App new version notifier added
* Hide Search FAB from settings
* Internal client error 403 handled using workaround

## 1.1.0

* Radio feature added
* Search/(Artist-song/videos) list continuation added
* List sorting feature added
* PlayNext option added
* Bug Fixes

## 1.0.1

* Some Network Exceptions handled
* Ignore battery enable option for notification issues
* Some Minor changes & bug fixes

## 1.0.0

* initial release.