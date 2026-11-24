# Changelog

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
