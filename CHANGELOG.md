# Changelog

## 1.41.31

### Minimap button
- The tooltip says "OutlawOS" and the version (it said "Guild OS by Chehul").
- OutlawOS now shows up in minimap-button bags and bar addons that use Broker (ElvUI, Titan Panel, Bazooka and similar), with left-click to open and right-click for the menu.
- One time per account, a chat line says where the button is and that `/outlawos minimap` brings it back if it is hidden.

## 1.41.30

### Calendar
- An event's full description now shows, wrapped, instead of stopping after the first line with "...". The Where, Lead and other detail lines wrap the same way.

## 1.41.29

### Fixes
- Footer: "/outlawos help" no longer runs into "Blizzard". The links are measured after the font is applied.
- Calendar: the selected day's event titles line up with the left edge (they were centred), and the first event's title is no longer cut off at the top.

## 1.41.28

### Memory
- English no longer loads its 1,600-line string list, which only mapped every string to itself. Saves about 150 KB for every player. The list stays in the folder as `Locales/enUS.keys.lua` for translators.

## 1.41.27

### One command name
- Every message, help line and tip now says `/outlawos`, in all languages. `/gos` and `/guildos` still work behind the scenes, so old macros keep running.
- The top bar says "OutlawOS" when you are not in a guild (it used to say "Guild OS"), and so do the mesh and network-alert labels.
- The support probe's "saved" messages no longer show the internal data-file name.

## 1.41.26

### Now tab: Next Event card
- The card fills its space. It keeps the event's title, date and kind, and adds:
  - a large countdown (gold in the last 3 hours);
  - who hosts it, and where to meet;
  - your answer in words ("You: going · DPS", or "You have not answered yet");
  - a bar per role against the spots the event asks for (the plain counts when it names none);
  - who is going, in class colours with their role, and who is tentative;
  - the organizer's notes;
  - the next three events under "Later". Click one to open it in the calendar;
  - a coloured edge bar by the event's colour or kind.
- Along the foot, next to Going / Tentative / Absent: Discord (the invite), Copy location (when the event names one), and for officers Remind (N), which posts a short reminder in guild chat (at most once every 30 minutes per event). N is how many online members have not answered.
- Each block shows only if it fits, so a short card keeps the essentials and a tall one shows more. Events planned on the website keep their "Sign up in Discord or on the website" line.

## 1.41.25

### Top bar
- The Wind & Blade emblem sits before the OutlawOS wordmark on every style (the leather theme keeps its own larger one).
- A thin gold rule under the top bar, and the bottom bar's rule is the same gold.
- The guild line shows how many officers are online (Guild Master, Co-Guild Master, Officer, Raid Marshal). Hover it for the guild's renown, the achievements closest to earned, and the names of the officers online.
- A "next event" chip shows the next calendar event and when ("Fish Camp · 1d3h"). Click it to open the calendar on that day.
- A gold dot and a count show when something needs you (join requests, trials, RSVPs). Click it for the Now tab; hover it for the first few.
- The sync time is green when fresh, grey, then amber as it ages, and red when stale or never synced.
- A Discord button opens the copy box with the Outlaw invite.
- A bell quiets the group notices and their sound for an hour; click it again to turn them back on.
- As the window narrows, the new buttons drop out first, lowest priority first, so nothing runs under the close button.

## 1.41.24

### Bottom bar
- The window's bottom bar now matches the Outlaws: the left link is the Outlaw Discord (click it for a copy box with the invite), the help link says /outlawos help, the version reads "OutlawOS v...", and the rule, links and version are brass instead of grey-blue.

## 1.41.23

### Now tab
- The top of the Now tab says "Next event" instead of "Next raid", since it shows the next calendar event whatever it is (Fish Camp is not a raid). With nothing planned it says "No event scheduled."

## 1.41.22

### Now tab
- The Outlaw Gazette card showed only three lines and a "..." even with plenty of empty room below. It now measures the room the card really has, refits when the window is resized, and when a long line (like the list of promotions) does not fit it cuts that line where it stops fitting, so the lines after it still show.

## 1.41.21

### Alliance style
- The Alliance style now has the gold trim its description promises: window borders, dividers, pop-up borders and hover edges are antique gold on the royal blue. Before, they were blue-grey and only the title, active tab and primary buttons were gold.

## 1.41.20

### Styles
- The Parchment style is gone from the style picker, the welcome screen and /gos style. If you had it selected, OutlawOS goes back to the default style on your next reload, with no message.

## 1.41.19

### Parchment theme
- Coloured text made for dark windows (lime green, pale yellow, white, orange) is brought down to a darker shade on Parchment, so the item level column, "Now", "Solved", the Bounty Board counts and the rest read on cream. The dark themes are unchanged.
- Hover tooltips stay dark on every theme, and now use light text on Parchment (before, the lines were dark brown on a dark tooltip and could not be read).

## 1.41.18

### Parchment theme
- The pop-up windows (Welcome back, Recruitment, join requests, the calendar, settings pop-ups, search and about forty others) had a fixed near-black background, so on Parchment their dark text could not be read. They now take their colours from the theme, and look the same as before on the dark themes.
- Class colours are darkened on Parchment, so priests, rogues, hunters and mages can be read on cream.
- Level numbers and "Now" in the Ledger no longer use white and bright green on cream. They follow the theme.
- Gold text (the Bounty Board tiers, guild bank goal, About links, group notice, market prices) uses a deep amber on Parchment instead of pale yellow.

## 1.41.17

### Wanted (Gilded Feather)
- Verified clears typed in by hand have no limit now. "+ Add clear" is always there, however many clears a dungeon has.
- Saving verified clears sends them to the guild at normal speed (it used to go in the slow lane), and says so in chat with the count. Every member's Bounty Board, on the Desk and on the home page, repaints as soon as the clears arrive instead of at the next time it is opened. Officers who are offline get them when they next log in, as before.

## 1.41.16

### Groups notice
- The Ask button checks that you can actually ask. If you're in a group, leading one, too low or too high for the activity, already asked, or the group has ended, the button is greyed and says why. It re-checks every second while the notice is up.
- Click the role icon on the Ask button to ask as another open role of yours (a healer main can ask as DPS without opening the tab).
- Right-click the X for a small menu: mute that activity for a day, go quiet for 30 minutes, or put the card back in its default spot.
- A soft sound plays with a new group or a spot request. Turn it off in Settings (Groups).
- Hover the notice for the details: level range, the leader's level, open roles, how long ago it was listed, and the leader's note.
- When groups are waiting, the best fit comes up first (in your level range, one of your roles, room for more than one of you). Groups that have ended are skipped, and the waiting ones are dropped once you're in a group yourself.
- The notice remembers where you drag it, even through the slide-in.

## 1.41.15

### Groups
- The "Ask as ..." button on the group notice now carries your role's icon, so it is clear which role you are asking as. Whisper stays the quieter button.
- Several groups at once no longer stack or replace each other. The first stays up, and the card says "+2 more groups >". Click it to move to the next group; the one you leave goes to the back of the line. When a notice ends, the next one comes in.
- A request for a spot in your group, or a warning that your listing is ending, still goes first. The X on the notice, or opening the tab from it, clears the waiting ones.
- The notice is a little wider (330px) to fit the new line.

## 1.41.14

### Groups
- The "Groups being formed" notice is redesigned. Nothing is cut off any more: the leader's name (in their class colour) and the activity (in gold) sit on the first line, and the open roles show as role icons with counts on the second. Without role art you get the words instead.
- A row of pips shows how full the group is, gold for places taken. Groups bigger than ten show a count like 3/25.
- A gold bar runs down the left edge, and a thin gold bar along the bottom runs out as the notice's time does.
- The notice slides in, and fades out before it goes.

## 1.41.13

### Web tab
- The names kept off the site and the "what goes on the site" switches are now shared between officers. Change them on one officer's PC and every officer's roster follows, so another officer's publish can no longer put a hidden name back. The newest change wins, and only an officer's change is taken.

### Companion
- OutlawOS ships an empty placeholder Inbox.lua that never overwrites the real one. While the companion app still writes to the old GuildOS folder, a small GuildOS bridge addon there loads that Inbox.lua for OutlawOS.

### Alliance
- A slot request that gets no answer used to vanish silently. If nothing comes back within three minutes you now get a message saying so. An answer (yes or no) clears it.

## 1.41.12

Release that rolls up 1.41.06 to 1.41.11 (below). No other changes.

## 1.41.11

### Sync at login
- When a member logs in, the guild already answered their request with member data, trials, raid data and more. It now also answers with the leaders' shared records (the About page, bounty board, Gazette, strikes and other officer settings, sent only by someone allowed to send them), each member's check-in, the list of who has OutlawOS, and the daily activity counts. Answers stay limited to one every two minutes per client, so a busy login hour does not flood the guild channel.

## 1.41.10

### The Ledger
- A member's tooltip showed the OutlawOS version up to three times (one in red, one grey for officers, one from the check-in). It now shows one line, from the member's check-in, and only falls back to the older sources when there is no check-in. "Not installed" is said once.

## 1.41.09

### Interface styles
- Three new options in Settings, Interface style: GuildOS (the original flat dark look, without the Outlaw leather, brass emblem and western fonts), Alliance (deep royal blue with silver and gold trim) and Parchment (light cream and tan with dark brown text). Pick one, press Apply and reload. OutlawOS (leather and brass) stays the default.
- Parchment is a light theme, so some class colours (yellow, white) are hard to read on it.
- The first-run screen still offers only OutlawOS and WoW: Forever.

## 1.41.08

### Audit Log and The Office
- The filter and sort buttons on the Audit Log showed no text, so you could not tell which filter was on. They now show their names, and a filter that is switched on is marked in gold. The period button in The Office had the same blank caption and is fixed too.

## 1.41.07

### The Ledger
- "Avg activity" now reads the same for everyone. A client only knew about the days it was running (and only counted a member on the last day they were seen), so a newly installed client read far lower than an older one. Clients now share each day's login count (at login and on Check) and keep the highest, so the number catches up within a login or two.

## 1.41.06

### The Ledger
- The counter cards now wrap onto more rows when the window gets small instead of dropping off or squeezing. Every card stays visible with its text readable, the card band grows taller as needed, and the member list below moves down and shows fewer rows. At full width it is still one row.

## 1.41.05

### The Ledger
- The counter cards across the top no longer squish together when the window is resized. The cards with longer captions (Officer+ online, Recruiters online, Avg attendance, With OutlawOS) need more room before they show, and a caption or number that is still too long is cut at the card's edge instead of running into the next card.

## 1.41.04

### With OutlawOS count
- The Roster's "With OutlawOS" number no longer depends on which check-ins your game happened to be online for. Each client now shares the list of guildmates it has heard from in the last 14 days (at login and when someone presses Check), and every client merges it, so the count converges. A newly installed client fills up within a minute or two of other players being online.

## 1.41.03

### Audit Log
- Filter by action (promoted, demoted, removed, joined, left, MOTD, info), date range (24 hours, 7, 30 or 90 days), person (the one it was done to or who did it) and free text. A counter shows how many of the entries match, and Reset clears every filter.
- Sort by clicking a column heading (When, Action, Person, Done by) or with the sort button: newest, oldest, person A-Z, action A-Z, done by A-Z. Your choices stay while the window is open.

### The Office (Inner Circle, guild master / GM Alt / Co-GM only)
- A new tab that only those ranks see.
- Overview: members and who is online, joins, leaves and kicks, trials ready, members ready to promote, guild bank and this week's bounty clears.
- Recruiter tracker: joined, stayed 7 days or more, promoted to Outlaw, still in the guild, pitches sent and join percentage, credited to whoever sent the invite.
- Officer tracker: recruits, strikes issued, kicks, events run, raids led, when they were last on and their weekly goal.
- Periods: all time, this week, this month, last 7 days, last 30 days.
- Weekly goals per person (recruits and events) with progress.
- Guild settings: officer line, trial length, automatic trials. A leadership-round button posts a one-line summary to officer chat. Copy for Discord opens a window with the text ready to copy.
- Danger zone: clear the audit log, goals or pitch counts, each with a confirmation.
- Numbers only cover what this PC and the other officers' addons saw. Pitches are counted for whispers sent from this PC.

## 1.41.02 (since 1.40.01 and 1.41.00)

### Web tab
- A second column on the Web tab (under the first on a narrow window).
- Publish tools: why the game and the site counts differ, a preview of who joined, left or changed rank since the last write, the companion's last word with a stale warning (officers also get a chat line at login), a copy-site-link box, a schedule that offers to publish every 1, 2, 4, 12 or 24 hours (ask, or auto when you are solo and out of combat), a history of the last writes, and a "Published" line after the reload.
- Choose what this client sends: loot history, raid nights and attendance, journal, join requests, points and loot lists. Names can be kept off the roster this client sends.
- Raid tools: load an upcoming raid from the guild calendar, see the class mix, what the raid lacks (tank, healer, buff classes), who is online and in your group, invite the maybes and standby after the confirmed raiders, post the roster to guild chat, save plans and load them again, and a raid-day checklist.
- Every button on the tab shows a hover hint, and a greyed-out one says what turns it on.

### Chat
- Rank symbols in guild and officer chat always show, even if the chat icons and tags are off. The "Rank symbol" option is gone.

## 1.41.00 (since 1.40.01)

### Renamed to OutlawOS
- The addon folder is now OutlawOS, with OutlawOS.toc, and the game's addon list, key bindings, buttons and messages say OutlawOS.
- Update steps: close the game, delete Interface\AddOns\GuildOS, put the new OutlawOS folder in Interface\AddOns, and copy WTF\Account\<your account>\SavedVariables\GuildOS.lua to OutlawOS.lua in the same folder so your settings and guild data come across. Do this before you log in.
- The game saves an addon's data under the addon's folder name, which is why the copy is needed. Nothing else about your data changed.
- If the old GuildOS folder is still there next to OutlawOS, a red line in chat says so at login.
- Under the hood the addon, its saved data name and the guild sync keep their old internal names, so members still on 1.40 keep syncing with the guild.

## 1.40.01 (since 1.40.00)

### Eastern Kingdoms Outlaws
- Groups: the group line and the LFG line name the dungeon's level range, for example "Krol'dok Stronghold levels 40-45".
- Recruit scanner: the found count turns red when nothing matches.

## 1.40.00 (since 1.39.27)

### Eastern Kingdoms Outlaws
- Login: when the Guild Master logs in, every OutlawOS screen online shows "The Matriarch has arrived." Only the Guild Master's login sends it.

## 1.39.27 (since 1.39.26)

### Eastern Kingdoms Outlaws
- Inner Circle: the Ranks tab is removed. Promote and demote stay on the roster and in Ready for Outlaw.

## 1.39.26 (since 1.39.25)

### Eastern Kingdoms Outlaws
- Version bump only. No code changes since 1.39.25.

## 1.39.25 (since 1.39.24)

### Eastern Kingdoms Outlaws
- Announcements: a post shows in a box on everyone's screen for about six seconds, with a Close button. Post it from the Outlaw Desk.
- Quick Tools: a tab on the Inner Circle for officers and Raid Leaders. Location of the Week, Bounty Hunter, Bounty Board, raffle, Gazette and announcement buttons, grouped by category.

## 1.39.24 (since 1.39.23)

### Eastern Kingdoms Outlaws
- Announcements: a Post button on a movable box at the top of the Ledger. Each new post shows for about six seconds, then fades. Anyone except the EKO recruiters can post.

## 1.39.23 (since 1.39.22)

### Eastern Kingdoms Outlaws
- The My Char tab is now My Toon.
- My Toon: each character re-sends its own main and offspec on the answer to a sync request, so people who log in later catch up.

## 1.39.22 (since 1.39.21)

### Eastern Kingdoms Outlaws
- Settings: a sync button, shown only to the owner, that has every client refresh who is online and send its member data. Each client answers at a random moment within 45 seconds, and a second press within a minute is ignored.

## 1.39.21 (since 1.39.20)

### Eastern Kingdoms Outlaws
- Alt links: a stale officer copy can't remove a link here, and an unlink sticks. Each link keeps the time it last changed; the newer change wins. Officers on the new version send the times; older clients still get the plain list.
- Link alt: when you view an alt, the button adds the new alt to that alt's main. It used to do nothing, because an alt cannot take alts.

## 1.39.20 (since 1.39.19)

### Eastern Kingdoms Outlaws
- Alliance: the Apply screen says who may apply. A guild master or Co-Guild Master of any guild other than the Outlaws can apply for their guild; everyone else sees why, greyed out.

## 1.39.19 (since 1.39.18)

### Eastern Kingdoms Outlaws
- Join requests: the form shows the guild's fit (nights, pace, language, looking for, loot) and asks three short questions: when you play, main or alt, and what you want from a guild. A review shows what the officers will see before you send.
- Join requests: Withdraw takes a request back. Ask again sends it once more, at most once every five minutes, the same gap as the automatic repeat.
- Join requests: an officer can decline with a reason and a date to ask again. The player sees both, and the decline menu lists the reasons.
- Join requests: an answer that came while you were away is shown once at login.
- Join requests: officers see how long each request has waited, and a gold line when one expires within three days.

## 1.39.18 (since 1.39.17)

### Eastern Kingdoms Outlaws
- Guildless start: a Guild Master line sits above the recruiters and officers, with an Online status. Your own line shows when you qualify.

## 1.39.17 (since 1.39.16)

### Eastern Kingdoms Outlaws
- Recruit scanner: the candidate list no longer fails with "stack overflow" after many clicks. Rows are reused instead of rebuilt.

## 1.39.16 (since 1.39.15)

### Eastern Kingdoms Outlaws
- Guildless start: an Online now section lists the Outlaws' recruiters and officers who are online, each with Whisper.
- Recruiters and officers send a short online ping on the realm bus every few minutes, and guildless characters hear it.
- Settings: an owner preview of the guildless screen. Nothing is saved or sent.

## 1.39.15 (since 1.39.14)

### Eastern Kingdoms Outlaws
- Guildless start: the choices are Apply to the Outlaws (a join request) and Apply to Alliance. The guild search is gone from that screen.

## 1.39.14 (since 1.39.13)

### Eastern Kingdoms Outlaws
- Alliance applications: their own Applications tab under Alliance, for ambassadors. Join requests no longer list them.

## 1.39.13 (since 1.39.12)

### Eastern Kingdoms Outlaws
- Join requests: the card list draws again. 1.39.12 left it empty.

## 1.39.12 (since 1.39.11)

### Eastern Kingdoms Outlaws
- Join requests: each request is a card. Alliance applications are gold and labelled, so they stand apart from join requests.

## 1.39.11 (since 1.39.10)

### Eastern Kingdoms Outlaws
- Marketplace: a post that cannot be drawn shows its error on its own line, instead of a blank bar.

## 1.39.10 (since 1.39.9)

### Eastern Kingdoms Outlaws
- Join requests: a Remove button on every row, separate from Decline. Remove takes the request off every officer's list, open or closed, and the player is not told. Decline still answers the player.
- Join requests: Remove is shared over the guild channel, so the other officers' lists match.

## 1.39.9 (since 1.39.8)

### Eastern Kingdoms Outlaws
- Looking for a group: a card per player, grouped by activity. A gold outline marks players who fit your group.

## 1.39.8 (since 1.39.7)

### Eastern Kingdoms Outlaws
- Recruiting tab: changes you save (message, interval, Discord, channels, on or off) stay after a relog.

## 1.39.7 (since 1.39.6)

### Eastern Kingdoms Outlaws
- Roster tooltip: shows the OutlawOS version a member last checked in with, or that OutlawOS is not installed.

## 1.39.6 (since 1.39.5)

### Eastern Kingdoms Outlaws
- Wanted page: a verified clears section for each bounty board. Officers type up to five names per clear, tick full party, and save. The paste box stays.

## 1.39.5 (since 1.39.4)

### Eastern Kingdoms Outlaws
- Bounty Board: a "Set verified clears" button beside "Set bounties" for officers.

## 1.39.4 (since 1.39.3)

### Eastern Kingdoms Outlaws
- Verified clears: a paste whose tab characters were lost (rows with spaces) is read too, so Wanted posters update.

## 1.39.3 (since 1.39.2)

### Eastern Kingdoms Outlaws
- Wanted posters: a "Verified clears" button on the Wanted header lets officers paste this week's clears from the Bounty Board sheet's Clears tab. A clear with three or more Outlaws marks its poster and counts for its claims, even when no OutlawOS client logged it. Bounty points and raffle entries are unchanged.

## 1.39.2 (since 1.39.1)

### Roster
- The rank list scrolls instead of overlapping the class filters in a short window.

## 1.39.1 (since 1.39.0)

### Guild Hub
- About the Outlaws: text no longer overlaps when the window is resized.

## 1.39.0 (since 1.38.0)

### Alliance
- Events tab: ambassadors post shared events with the calendar editor, and allied guilds request slots. Approvals and cancels are for ambassadors only.

## 1.38.0 (since 1.37.14)

Addon title is now "OutlawOS" in the addon list.

### Eastern Kingdoms Outlaws
- Ledger anniversaries: the panel lists the last 7 days by milestone (2, 3 and 4 weeks, then months) and a "Coming up" list for the next 14 days.
- Bounty Board clears are counted from this week's dungeon clears logged by members with OutlawOS. The Bounty Board status and your bounty points on the Dashboard use the same count.
- Raffle entries are counted from this week's clears, one per clear. Officers can still paste a list to override the count for that week.

### Guild chat
- Timestamps on the name line, a line-length cap, a 2-minute split for a speaker's run, and day dividers.
- Text size setting, a gold wash on your own lines, and a roster tooltip on the class icon.
- 240-byte counter, focus kept after Send, and Up/Down to recall sent lines.
- A "To <channel>" line and inline lock state.
- Click, right-click or Ctrl-click a name to whisper, filter to a player, or invite. Right-click a card to copy.
- Latest button, unread counts on channel tabs, a new-lines line, and a search box.
- Gold mention highlights and an alerts switch per channel.

### Marketplace
- Posting: the item field takes about a third of the form. The price reads back as you type and warns when it isn't a price.
- Mine turns amber five posts before the cap and red at it. Refusals show under the form.
- The item stays in the form after posting. The price of your own post can be changed in place.
- Each tab has its own empty state. Filters and searches with no results offer Clear search or Show all.
- Tab labels show live counts. Old posts are dimmed and tagged. Duplicate items are one row with a count.
- Prices sit in their own column. Quantities show as x3. Sub-tab, filter and sort are remembered across reloads.
- Popup button is "Mute this item". The Muted filter shows a count.
- Fix: the quantity box shows 1 when the tab opens, so it no longer looks empty.

### Polls
- Bars behind options, a leading tag once closed, closed and closes-on status, and author class colour.
- Posted date, rules between polls, and a question counter. Who-voted tooltips.
- Results stay hidden until close. Auto-close after 3, 7 or 14 days. Reopen, and delete with confirm.
- Confirm before closing. Post to guild chat or bulletin, with confirm.
- Open/Closed/All filter, summary line, and a six-option warning.

### Bulletin
- Each notice has a rule above it. The newest unpinned notice is tagged Latest.
- Officers can pin, edit, and post notices that expire after a week or a month. They can send a notice to guild chat after confirmation.
- Delete asks for confirmation. A search box filters by text or author.
- Officers see the count against the 20-notice cap. "Updated" shows when the board last changed.
- Empty boards say what to do, for officers and members.

### Achievements
- Nearest: cards are only as tall as needed. Percentage beside the count. A sort button puts the closest to done first.
- Earned: rows grouped under month headings. A search box. Newest tier shows who earned it, with a "New" mark for 7 days.
- Long groups show four parts then "+N more". Sections fold when their title is clicked.
- Header hint line, "Synced" shows the site's upload time, and "Last earned" names the newest achievement.
- Fix: a long name in the who-column no longer wraps onto a second line.

### Raids
- Sessions and Raiders have search boxes. Raiders columns sort by name, role, gear, ilvl and spec.
- Cores ask for confirmation before delete. Readiness counts are coloured by status.
- Diagnostics are behind a Show/Hide toggle. Raid Tools shows an "Updated HH:MM" stamp.

### Guild rules
- Wide windows split into two columns. Sections fold with Hide/Show. A jump row scrolls to a section.
- Attendance penalties sit on one line under one Save. Reset attendance to defaults.
- Ticking an officer rank asks for confirmation. Each rank shows how many members hold it.
- Calendar and officer changes are stamped with who changed them on this client.
- Readiness item level is checked from 1 to 1000. Copy rules and Paste rules move the rules as one line of text.

### Chat and alerts
- Live preview of an annotated guild line and a sample mention line.
- Mentions split into "who sets an alert off" and "what happens".
- Watch-word chips are sorted with hit counts. Add your linked alts. Copy and paste watch-words as text.
- Three-letter watch-words warn but are still added.
- Temporary mute (30 minutes or 1 hour) and Unmute. Test alert button. Repeat-alert cooldown of 5 s, 30 s or 2 min.

### Interface
- Two columns: appearance on the left, in-game options and reset on the right.
- Language picker: English, Portuguese, Spanish, German, French, Russian, Korean, Chinese (Simplified and Traditional), and Italian. Applies after a reload.
- Option to hide the footer. Guild bank options grey out unless a guild bank is open.
- Reset interface settings, behind a confirm dialog. The language is kept.
- Fix: the page scrolls correctly after a jump (for example, to Readiness).

### Roster and leaders
- Right-click menu: Assign Recruiter and Assign Event Organizer. These record the role only; rank changes stay in the native guild panel.
- Leader panel shows each leader's CurseForge version, with NOT INSTALLED or UPDATE OutlawOS when out of date.
- Auto-invite removed: the recruiting whisper handling, /gos autoinvite, its settings and help text. Groups/LFG whisper invites are kept.
- Chat tweaks are on by default, with a one-time switch-on for existing installs.
