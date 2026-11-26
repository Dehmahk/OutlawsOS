----------------------------------------------------------------------
-- Guild OS - What this release changed (EKO patch: the Now tab's update notice).
-- Each client sends its version and these notes in its check-in ("ekowho"), so a guildmate on an
-- older OutlawOS sees "OutlawOS x is out" on the Now tab and can read the changes. The notes go out on
-- every login, so keep them short (1500 characters at most, cut past that). Update them with each release.
----------------------------------------------------------------------
GuildOS.RELEASE_NOTES = {
    version = "1.40.01",
    text = [[
- Groups: the group line and the LFG line name the dungeon's level range, for example "Krol'dok Stronghold levels 40-45".
- Recruit scanner: the found count turns red when nothing matches.
- Settings: an owner sync button. Every client refreshes who is online and sends its member data.
- My Char is now My Toon. Each character re-sends its main and offspec on a sync request, so late logins catch up.
- Announcements: a post shows in a box on everyone's screen for about six seconds, with a Close button. Post it from the Outlaw Desk. Anyone except recruiters can post.
- Quick Tools: a tab on the Inner Circle for officers and Raid Leaders. Location of the Week, Bounty Hunter, Bounty Board, raffle, Gazette and announcement buttons, grouped by category.
- Inner Circle: the Ranks tab is gone. Promote and demote stay on the roster and in Ready for Outlaw.
- Login: when the Guild Master logs in, every OutlawOS screen online shows "The Matriarch has arrived."
]],
}
