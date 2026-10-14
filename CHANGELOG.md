# 1.7.153

The music player takes its look from the cover, like BitChord:
* The page under the cover fills with the cover's own colour, darkening
  towards the bottom, and a second colour from the cover glows behind
  the play button. Dark themes only; the light theme and videos look as
  before. With Player canvas on, the glow drifts slowly
* The line being sung shows under the title for songs with synced
  lyrics; tap it for the full lyrics
* Minimising the player shrinks the cover into a card that lands on the
  mini player, while the screen behind shows through; opening it grows
  the cover back out

Lyrics:
* Synced lyrics can be scrolled through now (they used to sit still
  under your finger). While you look around, the line in the middle
  shows its time and ▶; tap ▶ to play the song from that line, as you
  can in Spotify, Apple Music and YouTube Music. A few seconds after you
  let go they go back to following the song. A tap still closes them
* Share lyrics as a picture, like Spotify and Apple Music: ⋮ › Share
  lyrics, pick up to 5 lines and share the card (the song's cover
  colours, the lines large, the song and artist) to any app
* Romanized lyrics, like Metrolist and YouTube Music: Korean, Cyrillic
  and Greek lyrics show how they sound in Latin letters under each line
  ("사랑해" → "saranghae", with the sound changes you hear in the song,
  like "감사합니다" → "gamsahamnida"). Not for the script of the app's own
  language; Settings › Romanized lyrics turns it off
* Translated lyrics, like Apple Music, Spotify and YouTube Music: switch
  on ⋮ › Translate lyrics (or in Settings) and lines in another language
  show their translation into the app's language under them, with the
  romanization when there's one; synced, word-by-word and plain lyrics.
  Off by default; while on, lyrics are sent to Google Translate
* Lyrics text size, like Metrolist's: Settings › Lyrics text size
  (Small, Default, Large, Largest) for synced, word-by-word and plain
  lyrics. Synced lyrics now also follow your phone's font size; they
  used to stay the same size whatever it was set to
* Lyrics timing, like Musixmatch's sync: when a song's synced lyrics
  run ahead of the singing or behind it (some from LRCLIB do), ⋮ ›
  Lyrics timing moves them later or earlier, half a second a tap, for
  that song only; it's remembered for next time. The line under the
  title and "play from this line" follow it too
* Lyrics offline, like Spotify's for downloaded songs: downloading a
  song now fetches its lyrics too, and YouTube Music's own lyrics (for
  songs without synced ones) are kept once seen, so both show without a
  connection; they used to need one each time

Mini player (phones):
* Drag it sideways and the song follows your finger while the next (or
  previous) song slides in beside it; let go past a third of the way,
  or flick, to skip. A short drag springs back, and where there's
  nothing to skip to it only gives a little. Swiping back always goes to
  the previous song (the ⏮ button still restarts the song first when
  you're more than 3 seconds in)

Screen readers (TalkBack):
* Play / pause, the mini player's previous / next, every song row's ⋮
  and the download button now say what they do ("Pause", "Next",
  "More options", "Download", "Downloading 45%") instead of just
  "button"; on desktop the mini player's shuffle, repeat, lyrics, queue,
  mute and song info buttons show what they are on hover
* What a swipe does on a song row (add to queue, play next, add to
  playlist, remove) and on an Up Next row (remove) is in TalkBack's
  actions for that row, as in Spotify; with TalkBack on, a swipe moves
  between items, so those were out of reach
* The gesture player's cover (swipe for next / previous, double-tap to
  play or pause) reads as "Cover art" with Play / Pause, Next and
  Previous in TalkBack's actions, and double-tap and hold still opens
  the song's options

Sleep timer:
* Music and audiobooks now fade out over the last 10 seconds before the
  timer stops them, like podcasts already did, instead of cutting off
  mid-note (not in video mode or a playlist Mix, which fade their own way)
* Custom: any length from 5 minutes to 4 hours on a slider, like Pocket
  Casts and AntennaPod; it opens at the length you picked last time
* Shake to restart (Android), like Pocket Casts and AntennaPod: while a
  timed sleep timer runs, shake the phone to set it back to its full
  length, even with the screen off; it buzzes so you know, and a fade
  that had begun stops. On by default; the switch is in the sleep timer
  while it runs

Lock screen and notification:
* A heart next to previous / play / next likes or unlikes the playing
  song, like Spotify and YouTube Music; it also shows in Android 13+'s
  media controls and in Android Auto, and follows likes you make in the
  app. Music only (podcasts keep skip back / forward)

Android Auto:
* Ask for music, as with Spotify and YouTube Music: say "Play <song or
  artist> on Riff" and the songs YouTube Music finds play, the best
  match first; "Play music on Riff" carries on with what was playing, or
  shuffles your Favorites. The search button in Riff's car screen lists
  the songs found; pick one and the rest follow it. On the phone, "Hey
  Google, play <song or artist> on Riff" does the same, even with Riff
  closed

Now playing:
* Tap the time at the end of the seek bar to see the time left
  ("−2:31") instead of the length, as in Apple Music and Pocket Casts;
  tap again for the length. Remembered, in every player
* The playing song's row (lists, Up Next, a show's episodes, a book's
  chapters) shows three little bars that bounce while it plays and stop
  while it's paused, as in Spotify, Apple Music and YouTube Music,
  instead of a still equalizer icon. Still with "Remove animations" on;
  TalkBack reads it as "Now playing"

Song rows:
* Explicit songs show an "E" before the artist, as in Spotify, Apple
  Music and YouTube Music: in playlists, albums, search results and
  Similar songs (TalkBack reads it as "Explicit"). Songs saved before
  this get it the next time they're loaded from YouTube Music
* Downloaded songs show a small download mark before the artist, like
  Spotify's green arrow, in every song list, so you can see what plays
  offline. It appears as soon as a download finishes and goes when you
  delete it (TalkBack reads it as "Downloaded")
* Swipe a song all the way to the left to add it to the queue straight
  away, like Spotify; the row slides back with a tick. A shorter swipe
  still shows the Add to queue / Play next buttons

Podcasts:
* Each show can skip its intro and outro, like Pocket Casts and
  AntennaPod: on the show's page, the sliders button (Playback
  settings) › Skip intro / Skip outro (off up to 5 minutes, in 5 s steps
  to a minute, then 15 s).
  Episodes then start after the intro, unless you're resuming further
  in (bookmarks still open where they point), and end where the outro
  begins: marked played and on to the next episode, as if they'd played
  out, also from the lock screen and Android Auto. Episodes too short to
  leave a minute play whole. The setting is the show's own and stays
  when it goes back to the global playback defaults
* "Sleep at end of episode" (and of the last chapter) stops where a
  skipped outro begins
* Unsubscribing from a show (its page, or long-press › Unsubscribe) says
  "Unsubscribed from <show>" with Undo, which brings the subscription
  back as it was and puts the show back in its folders; unsubscribing
  from the show's page now also takes it out of your folders
* Removing an episode from the podcast Up Next with its ✕ button gives
  the same Undo as swiping it away, and both look like the app's other
  snackbars
* Clearing the podcast Up Next says "Queue cleared" with Undo, as the
  music queue does, which brings it back in its order (episodes added
  since stay, after it); it used to empty at once with no way back
* Removing an episode's download (Downloads, or the episode's menu) says
  "Download removed" with Undo; the file is only deleted once Undo is
  gone (or on the next start), so a slip doesn't mean downloading a big
  episode again
* Chapter art, like Pocket Casts and AntennaPod: in episodes whose
  chapters come with their own pictures, the cover shows the playing
  chapter's picture, crossfading as chapters change, and the episode's
  own art in chapters without one
* The chapter list marks the chapter playing with the now-playing bars,
  following the episode as it goes, and chapters that link to a web page
  (show notes, a guest's site) get a button that opens it, as in Pocket
  Casts
* A show's page remembers its episode order (Newest first / Oldest
  first) for that show, like Pocket Casts and AntennaPod, so a series you
  hear in order stays oldest first. The eye button next to it hides
  played episodes (the count follows), and episodes you finish while the
  page is open drop out of the list; tap it again to show them
* Search a show's episodes, like Pocket Casts and AntennaPod: the search
  button in a show's Episodes header opens a field that narrows the list
  to episodes with those words in the title or notes as you type (the
  count follows); its ✕ closes it
* Previous and next chapter buttons either side of the chapter in the
  podcast and audiobook player, like Pocket Casts and Audible: next goes
  to the next chapter; previous starts the chapter playing again, or in
  its first 3 seconds goes to the one before. For episodes and books with
  chapters inside them; a book's separate tracks keep the player's own
  previous / next
* Listening history, like AntennaPod's and Pocket Casts': Podcasts ›
  History lists the episodes you've played, newest first, under Today,
  Yesterday and the date, with where each stands (played, time left).
  Tap one to carry on where you were, long-press for Up Next, swipe one
  away to take it out, or Clear history; both with Undo. Episodes played
  in a private session aren't kept
* Share an episode from the podcast player's ⋮, like Pocket Casts and
  Spotify: Share episode, or Share from 12:34 to share the moment
  playing; Share episode is in an episode's long-press menu too. The
  link is the YouTube video for a YouTube episode (starting at that
  moment), else the episode's page from its feed, else its audio file
  (which a browser starts at that moment)
* Timestamps in show notes play the episode from there, as in Pocket
  Casts, Spotify and YouTube: tap "12:34" (or "1:02:03") in the notes,
  and web addresses in them open in the browser; both in the accent.
  Times past the episode's end stay plain text (a clock time, not a
  moment of the episode). In an episode's long-press menu › Shownotes,
  a timestamp plays that episode from there
* Followed shows count their new episodes, like AntennaPod and Pocket
  Casts: in Podcasts › Subscriptions, a show's cover shows how many of
  its episodes are waiting in the Inbox (a folder's, those of its
  shows), and the number goes down as you play them or mark them played
* Add a show's new episodes to the queue, like Pocket Casts' "Add to Up
  Next": on the show's page, ⋮ › Episodes and downloads › Add new
  episodes to the queue (Off, At the top, At the end). From then on, the
  show's new episodes join the podcast queue when the Inbox finds them,
  oldest first; at the top they go after the episode playing. Episodes
  you've played, ones Keep latest set aside and ones you take out of the
  queue aren't added again
* Download a show's new episodes, like AntennaPod and Pocket Casts: in
  the same sheet, Download new episodes (Off, On Wi-Fi, Always). From
  then on, the show's new episodes download one after another when the
  Inbox finds them; On Wi-Fi waits while you're on mobile data and gets
  them on the next refresh on Wi-Fi. Played episodes and ones Keep latest
  set aside aren't downloaded, and Delete downloads after listening
  still clears them up. For shows from feeds (YouTube episodes can't be
  downloaded)
* Follow a show by its feed address, like AntennaPod, Pocket Casts,
  Apple Podcasts and Overcast: paste an RSS link (or a feed://, pcast://
  or itpc:// subscribe link) into the Podcasts search and that show comes
  up with Follow, for private feeds (Patreon, Supercast, Substack) and
  shows the directories don't list. YouTube links still find the channel
* Swipe episodes in the Inbox, like AntennaPod and Pocket Casts: swipe
  one right to add it to the queue, left to mark it played (it leaves
  the Inbox, with Undo, which also puts it back where it was in the
  queue and where you were in it). Off with the other swipe actions in
  Settings; TalkBack offers both as actions
* Sort the shows you follow, like Pocket Casts, AntennaPod and Apple
  Podcasts: the sort button in Podcasts › Subscriptions orders them by
  Name, Latest episode or Recently followed (Default keeps the order
  they had), inside folders too; folders stay first. Shows followed
  before this update count as followed earliest
* In Android Auto, Podcasts starts with your queue and your Inbox, as
  Pocket Casts starts with Up Next and AntennaPod with its queue and
  Inbox: the queue in its order, and the Inbox's new episodes as of its
  last refresh, newest first (played and set-aside ones left out), each
  playable on from there; Continue listening and your shows follow
* Mark as played from the podcast player, like Pocket Casts: ⋮ › Mark
  as played ends the episode as if it had played out (the next one
  plays, or with Autoplay episodes off it stops, back at its start) and
  marks it played. Undo brings it back unplayed, in its place in the
  queue, playing from where you were
* Skip chapters, like Pocket Casts: in an episode's chapter list, Skip
  chapters lets you untick the ones you don't want to hear, and playback
  jumps over them each time it reaches them (with Undo, as other
  skips); an unticked last chapter ends the episode there. Unticked
  chapters read as skipped in the list (tap one to hear it anyway), show
  with the episode's segments, and sync with the segments you mark
* Download queued episodes, like Pocket Casts' auto download of Up
  Next: Podcast settings › Download queued episodes (Off, On Wi-Fi,
  Always). Episodes you add to the podcast queue then download one after
  another, ready to play offline; On Wi-Fi waits while you're on mobile
  data and catches up when the app next starts or the Inbox refreshes
  on Wi-Fi. For shows from feeds

Audiobooks:
* The lock screen, notification, Android Auto and headset buttons skip
  back 10 s / forward 30 s in a book, like podcasts and Audible, instead
  of previous / next; next stays in the expanded notification
* Smart resume works in audiobooks too, as in Audible: after a pause the
  book steps back a few seconds (the longer the pause, the further), so
  you pick up the sentence. It follows the Smart resume switch in
  Podcast settings
* Books keep their own speed: the speed pill in the book player (and in
  its ⋮) no longer changes how fast music plays, and the music speed in
  Settings no longer changes a book or podcast that's playing. Books
  start at the speed they played at before
* Bookmarks in audiobooks, like Audible's: the book player's ⋮ ›
  Bookmark this moment saves where you are ("Bookmarked at 12:34"), and
  Bookmarks in this book lists them in reading order, each with its time
  and chapter. Tap one to play from there, even in another chapter;
  remove one with Undo
* The book player says how long is left in the book, like Audible and
  Apple Books: "Chapter 4 of 12 · 5 hr 12 min left", counted at the
  book's speed and kept up as it plays. For books in several chapters
  (a book in one file has its time left at the end of the seek bar)
* Notes on audiobook bookmarks, like Audible's: "Bookmarked at 12:34"
  offers Add note, and in Bookmarks in this book each bookmark has a
  note button (add or edit; an empty note takes it off), its note shown
  under its chapter. Podcast bookmarks' notes use the same editor

Library:
* Removing a song (swipe it, or "Remove" in its menu) now says "Removed
  from your library" with Undo, like YouTube Music; its download or
  cached copy is only deleted once Undo is gone (or on the next start if
  the app closed first), so a slip no longer costs the download
* Removing a song you'd only listened to (cached, not downloaded) from
  Library Songs now sticks; it used to come back on the next start
* Search finds songs by artist and album too, not just the title, and
  every word counts ("daft lucky" finds Get Lucky by Daft Punk); accents
  don't matter ("beyonce" finds Beyoncé). Albums match their artist,
  playlists their description
* Songs has a "Downloaded only" switch next to the cloud one: the list,
  the count and Play / Shuffle then cover only songs saved to the
  device, not ones that are just cached from listening
* Library Songs and the songs of a playlist sort by Artist or by Album
  too, like Spotify and Apple Music: each artist's (or album's) songs
  together, then by album (or artist) and title, songs without one last
* Library › Playlists and Albums sort by Recently played, like Spotify's
  Recents: the ones you last played from come first, the never played
  after them by name (Riff remembers from now on when you play from a
  playlist or album)
* Pin up to 4 playlists to the top of Library › Playlists, like
  Spotify: long-press a playlist › Pin to top (Unpin to undo). Pinned
  playlists sit right under Recently played, Favorites, Cached/Offline
  and Downloads, whatever the sort or search, with a small pin before
  their song count; they also come first when adding a song to a
  playlist
* Library › Playlists and Albums as a list, like Spotify's Your Library:
  the button next to the title switches between the grid of covers and
  rows (small cover, name, songs or artist); tap, long-press and pins
  work the same. The choice is kept, for both tabs

Playlists:
* Deleting one of your playlists now asks first ("Delete playlist?"),
  like Spotify and YouTube Music; before, one tap erased it and its
  songs straight away
* Removing a song from one of your playlists (swipe or the song menu)
  shows "Removed from <playlist>" with Undo, which puts the song back
  where it was; the swipe used to remove it without a word
* Give one of your playlists a photo of your own, like Spotify's Change
  image: open it › ⋮ › Set photo (later Change photo or Remove photo).
  It's cropped square and shows wherever the playlist's cover does: the
  Library, Home and Speed dial, and the playlist's page
* Recommended songs under your own playlists, like Spotify: ten songs
  like the ones in it, from your latest additions and others across the
  playlist. Tap + to add one, tap a song to play it, ↻ for others. Not
  shown offline, or while you search, arrange or select songs in it
* Add to playlist shows where the song already is, like Spotify and
  YouTube: Favorites and your playlists that already have it (all of
  the songs, when you add several) get a check, so you can see it before
  you add it twice
* A downloaded playlist stays downloaded, as in Spotify: when every song
  in one of your playlists is downloaded, songs you add to it later
  (from Add to playlist or its Recommended songs) download too
* Smart shuffle, like Spotify's: a playlist's ⋮ › Smart shuffle plays it
  shuffled, with a song like it that you haven't heard mixed in after
  every three. In Up Next a ✦ before the artist marks the songs it
  added; the playlist itself doesn't change. Offline it just shuffles

Up Next:
* Removing a song (swipe it away, the song menu, or ✕ on desktop) and
  Clear queue now show "Undo" for a few seconds; undo puts the song back
  exactly where it was, or brings the whole queue back
* Swiping a song away shows what it does: a remove icon on a red tint.
  The playing song doesn't swipe (it can't be removed)

Home's Speed dial:
* Swiping now goes round: a swipe right on the first page slides to the
  last one (and on from the last back to the first), instead of nothing
  happening
* Pages shrink and fade a little as they slide, the current page's dot
  stretches into a pill, and each page change gives a light tick

Private session:
* Like Spotify's Private session (YouTube Music's Pause history):
  Settings › Private session, and for 6 hours (or until you switch it
  off) what you play isn't added to Recently played, your stats and
  Rewind, the taste your mixes learn from, the Library's Recently played
  order or ListenBrainz. The setting shows when it ends; it also ends
  on time if the app was closed

Fade between songs:
* Like Spotify's and Apple Music's Crossfade: Settings › Fade between
  songs (off, 3, 5, 8 or 12 seconds) fades the end of a song out and the
  next one in, instead of a hard cut. The fade follows the song, so
  seeking back, pausing or skipping during it puts the volume straight
  back. Music only: podcasts, audiobooks, repeat-one, the last song of
  the queue, songs shorter than three fades and playlist Mixes (which
  have their own transitions) play as they are. Off by default
* Loudness normalization has a volume level, like Spotify's: Settings ›
  Volume level (under Loudness normalization, Android): Quiet, Normal (as
  before) or Loud, which keeps more of each song's volume. Changing it
  applies to the song playing straight away

Streaming quality:
* Auto, as in Metrolist (YouTube Music and Spotify set Wi-Fi and mobile
  data apart too): Settings › Streaming quality › Auto plays songs in
  high quality on Wi-Fi and low on mobile data, going by the connection
  each song starts on (high on desktop). Data saver still means low
  everywhere; video mode's audio and the song info follow the same rule

Stats:
* Play your top songs, like Spotify's: in Stats, tap a song in Top songs
  to play it with the rest of the list after it, or Play to start from
  the top. Songs come as Riff keeps them (Favorites, downloads, Recently
  played); podcast episodes in the list stay as they are

App icon shortcuts (Android 7.1+):
* Long-press Riff's icon for Search, Favorites and Downloads, as with
  Spotify and YouTube Music, or drag one to the home screen. They're in
  the app's language and follow it when you change it

Home screen widget (Android):
* A Riff widget for the home screen, like Spotify's, YouTube Music's and
  AntennaPod's: the song or episode playing with its cover, title and
  artist, and previous, play / pause (in your accent colour) and next.
  It follows the music in the background too, and its buttons do what
  the notification's do. Tap the cover or the title to open Riff; while
  Riff isn't running, the buttons open it. Black like the app, 4 × 1 and
  resizable in width

Keyboard (Linux PCs, and tablets with a keyboard):
* Spotify's desktop shortcuts work on every screen: Space play / pause,
  Ctrl + → / ← next / previous, Shift + → / ← forward / back 10 seconds,
  Ctrl + ↑ / ↓ volume, Ctrl + S shuffle, Ctrl + R repeat, Ctrl + F
  search, and Ctrl + / lists them all. Not while you type in a text
  field, which keeps its keys

# 1.7.152

* Riff now runs on Linux PCs. Every release ships a Linux build next to
  the APKs:
  * Arch Linux: `riff-mobile-bin-*.pkg.tar.zst`, install with
    `sudo pacman -U riff-mobile-bin-*.pkg.tar.zst` (the matching
    `PKGBUILD` is attached too)
  * Any other distro: `riff-mobile-*-linux-x64.tar.gz`, unpack and run
    `./install.sh` (needs mpv, GTK 3, libsecret and libayatana-appindicator)
* On Linux, media keys and desktop media widgets see Riff, closing the
  window can keep music playing in the tray (Settings, Background play),
  and opening Riff again brings back the running window
* Signing in to YouTube or Spotify needs the Android app for now; the
  desktop app says so instead of opening an empty page

# 1.7.151

* The Up Next tab at the bottom of the player now runs edge to edge with
  a gently arched top, like the top slice of a circle. Same height as
  before

# 1.7.150

A clean-up release: bugs, memory and speed across the whole app, and
about 2,300 lines of code that did nothing removed. Nothing looks
different.

**Playback**
* Editing the queue (remove, reorder, shuffle) while a song was loading
  could drop that song, leaving nothing playing and the app stuck on
  "loading"
* "Remove from queue" from an older menu no longer moves you to the
  wrong song
* Radio / Wave running out while offline no longer breaks every skip
* Android Auto: Daily Mixes and Fresh finds play again
* "Never play this" now also applies to radio, Up Next and Home's song
  shelves
* Smart queue (Settings) now actually works after starting the app:
  when two or fewer songs are left it adds a few similar ones. You can
  turn it off in Settings
* Video mode follows Data saver
* Audiobookshelf gets the right book length when you switch to music

**Podcasts and audiobooks**
* YouTube Music podcast episodes no longer show lengths like 56 hours
* A feed with one bad date no longer shows "No episodes"
* Episodes without an id in their feed no longer share progress and
  downloads
* Pull-to-refresh and Discover search can't be overwritten by an older,
  slower load
* Tapping Download twice no longer breaks the download
* One unreachable feed no longer holds up the whole Inbox for minutes
* Saving or cancelling a bookmark note no longer throws an error
* Audiobookshelf search while the library loads shows only results

**Everywhere else**
* Albums and playlists that fail to load show the error instead of
  loading forever
* Switching search filters quickly no longer crashes the results
* The new-playlist name no longer clears itself while you type
* Play on a tile while offline opens the page instead of doing nothing
* The app follows the system's light/dark setting correctly again
* Lyrics fall back to the next provider when LRCLIB answers oddly
* Soulseek downloads finish (they used to wait 30 minutes and fail)
* Spotify: the first play after launch uses your saved match; the
  remote panel stops polling in the background
* Settings search no longer keeps an invisible filter when you come back

**Memory and speed**
* Player, link handling and other listeners are released properly
* Caches that grew forever are capped (covers, transcripts, SponsorBlock,
  Spotify, Soulseek, the diagnostics log)
* Large transcripts are read in the background; Home does half the work
  on each track change; video mode redraws the progress bar less often
* Startup runs its steps independently and reads secure storage
  alongside the database

# 1.7.149

**Riff Wave lives in Discover**
* The Riff Wave card and its stations (Fresh finds, Rediscover, …) moved
  off Home to the top of the Discover tab, right under the search field,
  and scroll with the rest of Discover
* Home keeps every other section in the same order

**Playlist covers**
* Playlists without a cover get their own generated one: a soft colour
  blend with grain and the playlist name in bold, the same on every
  device. Library, Home, playlist pages, Spotify and Navidrome playlists

**Player**
* Tap the artist of a song with several artists and Riff asks which one
  you mean ("Choose artist", with their photos)

**Podcasts**
* Folders can have their own photo: long-press a folder › Set photo. It
  is cropped and shrunk to fit, and keeps the folder colour as a frame
* The second row of filters on the Inbox is gone: tap the Inbox chip to
  pick New, In progress, Queued, Downloaded, Bookmarked or Under 20 min.
  The chip shows the filter you picked
* Fixed: tapping a show you follow in Subscriptions or a folder started
  an episode instead of opening the show. It now opens the show's page
  with its episodes; the play button on the cover still plays

# 1.7.148

**Everything under ⋮, in every player**
* Podcasts and audiobooks: the button row under the controls is gone.
  Speed, sleep timer, shownotes (chapters for books), transcript, video
  and autoplay are in the ⋮ at the top right, above bookmarks and segments
* Audiobooks get that ⋮ too
* Cover-filling (gesture) player: lyrics, sleep timer and share moved into
  a ⋮ next to the heart

**Player polish**
* "Playing from …" at the top stays readable on light covers
* The Up Next tab at the bottom is one slim line with an up-arrow

# 1.7.147

**Discover in the side rail**
* New Discover tab with a compass, right under Home: a search field on top
  (tap it to search, with your history and suggestions) and YouTube's
  genres and music shelves below it
* The search and compass buttons are gone from the top right of Home

**Player**
* Similar songs moved off the player: swipe up the Up Next tab and switch
  to Similar songs at the top of the panel; tap one to play it
* The Up Next tab at the bottom is smaller and sits on the bottom edge
* Tap "Playing from …" at the top to open the album, playlist or artist
  that's playing
* Hold the play/pause button and slide left to jump back, right to jump
  forward (5 second steps, shown in a bubble while you slide)

# 1.7.146

**Player buttons moved into ⋮**
* The row of buttons under the song (lyrics, sleep timer, radio, add to
  playlist, share) is gone; the cover gets the room
* All five are in the ⋮ menu next to the song title: Start radio, Add to
  playlist and Share at the top as before, then Show/Hide lyrics and Sleep
  timer, which shows the time left while it runs
* Tapping the cover still shows the lyrics

# 1.7.145

**A smaller, rounded Up Next**
* At the bottom of the player, Up Next is now a slim rounded card floating
  above the gesture bar instead of a full-width block, lined up with the
  controls above it
* "Up Next" and the next song share one line; tap or swipe it up to open
  the queue, same as before

# 1.7.144

**What's playing? Name the song around you**
* New mic button at the top right of Home: Riff listens for up to 12
  seconds and tells you the song, artist, album and cover
* Play it straight away or search it in Riff; recent finds are kept in a
  list you can tidy up
* Recognition works the way Audire does (Shazam's catalogue, no account);
  the microphone is only used while that screen is listening
* Android only

# 1.7.143

**The side rail looks like it used to**
* Back by request: the active item sits in a soft green rounded box with
  a thin green outline, other items are grey, and the labels are big again
* Same rail width, items and order; tapping an item still gives a light
  click

# 1.7.142

**New look, step 8: sheets, dialogs, settings and stats**
* Menus and sheets share one style: rounded top, slim handle, roomy rows
  with clear icons, and remove/delete options in red
* Dialogs use the same dark surface with readable text and pill buttons
* Snackbars float above the bottom edge in your accent
* Settings groups are flat with thin dividers and bigger headings; the
  switches follow your accent
* Stats and Rewind use outlined tiles and accent charts
* Light taps on long-press menus, pull-to-refresh, play next, adding to a
  playlist or queue and starting a download
* Nothing moved: same settings, menus and buttons in the same order

# 1.7.141

**New look, step 7: podcasts and audiobooks**
* Episode rows: 48 dp covers, bold titles, grey details, thin dividers,
  and an outlined play pill; progress is a thin accent line
* Show and book pages: flat covers, bigger titles, Subscribe as a filled
  pill and Subscribed as an outlined one
* Section and filter pills are outlined, lighting up in your accent when
  selected; the podcast search field matches the main search
* The podcast and audiobook player sits on black with only a soft tint of
  the show's colour at the top
* The Skip-ad pill is a 36 dp accent pill that fades and slides in when
  an ad starts
* Nothing moved: same screens, rows and buttons in the same order; ad
  detection, auto-skip and SponsorBlock unchanged

# 1.7.140

**New look, step 6: players**
* The mini player is a flat dark card with a thin outline, a smaller
  cover, and plain play and next buttons; its progress line is thinner
* The full player sits on black; the cover's colour only softly tints the
  top
* Bigger, bolder track title; the seek bar is a thin line and its handle
  only appears while you drag
* Shuffle, repeat and the action row light up in your accent when on;
  liking a song or turning on lyrics gives a light tap
* Lyrics use one bold size, with the lines around the current one dimmed
* Nothing moved: same buttons in the same places, same gestures

# 1.7.139

**New look, step 5: lists**
* Song rows across Library, albums, playlists, artists, search and the
  queue share one style: 48 dp covers, bold titles, grey details, thin
  dividers, and the playing song tinted with its title in your accent
* Search has a slimmer pill-shaped field and outlined result filters;
  recent searches are plain rows
* Album, playlist and artist headers use bigger bold titles, flat covers
  without shadows, and a Play button in your accent
* Tabs show a short accent bar under the active label
* Loading placeholders gently pulse instead of shimmering
* Nothing moved: same screens, rows and buttons in the same order

# 1.7.138

**New look, step 4: Home**
* Home sections are separated by thin full-width lines with a little more
  room above each one
* Riff Wave is a flat dark card with a thin outline and a bigger title
* Station chips are slimmer outlined pills; the one you tap lights up in
  your accent while its station starts
* Shelf covers and Quick picks cards have tighter corners, with clearer
  titles under the covers
* Speed dial, Jump back in and Quick picks tiles sit on the same dark
  surface; the playing tile's equalizer is in your accent
* Nothing moved: same sections, same order, same items

# 1.7.137

**New look, step 3: side rail and page headers**
* The side rail is lights out: outline icons, the active one filled in
  your accent with no pill behind it, smaller labels, and a hairline
  down its right edge
* Pressing a rail item shows a soft round highlight and gives a light
  click
* Page titles are 20 pt bold, header icons 22 dp, and a hairline
  appears under a header only while content scrolls beneath it
* On tablets the side bar is black and its labels show properly
* Nothing moved: same rail width, items and order; same header buttons
  in the same places

# 1.7.136

**New look, step 2: one set of sizes and colours everywhere**
* Every screen now takes its colours, text sizes and spacing from the
  theme instead of its own numbers, so the whole app follows the same
  scale (and the accent you pick)
* Side margins are 16 dp everywhere, and spacing follows a 4-point grid,
  so some rows and gaps are a touch roomier
* The light and album-colour themes use the same type scale as Pitch
  Black, so text sizes match across themes
* Snackbars use dark text on the accent
* Nothing moved: same screens, same elements, same order

# 1.7.135

**New look, step 1: type and colours**
* Riff now uses Inter, bundled with the app (no font download on first
  start), with a tighter, bolder type scale
* Pitch Black follows X's "Lights out" palette: pure black, one-pixel
  hairlines, softer grey for secondary text, and your accent colour only
  on things you can tap or that are on (all six accents work)
* Buttons are pills, presses show a flat highlight instead of a ripple,
  snackbars use your accent, sliders and progress bars are thinner
* Nothing moved: every screen keeps its layout. The rest of the restyle
  comes screen by screen in the next updates

# 1.7.134

**Spotify on Home**
* When you're signed in to Spotify, Home shows your Spotify shelves after
  your own mixes: Jump back in (the albums, playlists and artists you just
  played on Spotify), On repeat (your top songs of the last four weeks),
  New from artists you follow (the last four weeks), Your top artists,
  Your playlists and Recently liked
* "Your Spotify mix" (first card in On repeat) plays a radio from your top
  songs, recent plays and likes. Long-press a Spotify song for a radio from
  it
* Songs play through Riff: each one is found on YouTube Music when you play
  it. Albums, playlists and artists open their Spotify page
* A song that's already on Home from YouTube Music isn't shown again
* Shelves show at once from the last visit and refresh in the background
  (every 30 minutes, or pull down on Home). If your Spotify sign-in ends,
  Home shows a Reconnect card
* Spotify no longer lets apps use its recommendations, Daily Mixes,
  Discover Weekly or Release Radar, so these shelves are built from your
  own listening instead
* Switch the Spotify shelves off in Settings → Home layout

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