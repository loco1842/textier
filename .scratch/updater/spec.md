# In-app updater

Status: done (awaiting manual pass, step 85)

textier finds a newer release on GitHub and, when asked, installs it and relaunches.

## Decisions

1. **Source:** the repo's GitHub Releases (`loco1842/textier`), through GitHub's latest-release API (drafts and pre-releases aren't offered). No framework: our own code, like the JSON parser (ADR-0002). The trust is HTTPS and the GitHub account, as for a download by hand. Recorded in ADR-0005, which makes the update check textier's one exception to "no network calls".
2. **When:** at launch (a few seconds in) and once a day after, while Settings › General's **Check for updates automatically** is on (`"checkForUpdates": true`, the default); and whenever **Check for Updates…** in the menu bar icon's menu or Settings' **Check Now** asks. An automatic check that fails is retried an hour later, silently.
3. **Offer:** a window: "textier X is available — you have Y", the release notes, and **Install and Relaunch**, **Later**, **Skip This Version**. A skipped version isn't offered automatically again, but a check asked for shows it. A check asked for also says when textier is up to date, or what went wrong.
4. **Install:** downloads `textier-X.zip`, checks it against the release's `SHA256SUMS.txt`, unzips it, checks it's textier (bundle identifier) at version X, clears the quarantine flag, puts it in place of the running app, quits and opens the new one. Anything wrong leaves the installed app as it was and says what, with a link to the release page. Running outside an app bundle (`swift run`), it offers the release page instead.
5. **Accessibility:** the window says macOS asks for Accessibility again after the update (the app is ad-hoc signed, not with a Developer ID).

## Not now

Delta updates, a beta channel, signing the archive beyond its checksum.
