# SillyTavern Termux

Install [SillyTavern](https://github.com/SillyTavern/SillyTavern) on an Android phone with one command — plus a numbered menu for running it day to day.

No PC, no server, no VPN required.

> Apache-2.0 · Free to use · Commercial use permitted

---

## What it does

Paste one command into Termux and it handles the rest. **Pick one based on your network:**

**Mainland China (recommended — direct from Gitee)**

```bash
curl -fsSL https://gitee.com/luyao23333/silly-tavern-termux/raw/main/install.sh | bash
```

**Behind a VPN / overseas**

```bash
curl -fsSL https://raw.githubusercontent.com/luyao20000315-sketch/SillyTavern-Termux/main/install.sh | bash
```

It will:

1. Point apt at a mainland-China mirror (rolls back automatically if the mirror doesn't answer, so your sources can't end up broken)
2. Install git / node / curl
3. Clone the Tavern core, pinned to v1.18.0
4. Run `npm install`
5. Write the control panel to `~/st.sh` and add an `st` alias

Open a new Termux session and type `st`:

```
┌────────────────────────────────────────────┐
│  Tavern Console                       stopped │
├────────────────────────────────────────────┤
│  [1] Start      [2] Stop      [3] Restart  │
│  [4] Status     [5] Logs                   │
├────────────────────────────────────────────┤
│  [6] Update     [7] Tavern Helper          │
│  [8] Backup     [9] Restore                │
├────────────────────────────────────────────┤
│  [10] Uninstall [0] Exit                   │
└────────────────────────────────────────────┘
```

Then open `http://127.0.0.1:8000` in your phone browser.

---

## Get Termux first

**Do not use the Google Play build** — it's been unmaintained for years and won't work.

- **F-Droid (recommended)** — <https://f-droid.org/packages/com.termux/>, scroll to the version list and tap *Download APK* next to the latest. You don't need the F-Droid client.
- **GitHub direct** — <https://github.com/termux/termux-app/releases/download/v0.118.3/termux-app_v0.118.3+github-debug_universal.apk>
  (113 MB, universal — runs on any phone. On arm64 you can swap in `..._arm64-v8a.apk` instead, which is only 35 MB.)

Verify with `pkg --version` in Termux.

---

## The menu, item by item

| Item | What it does |
|------|--------------|
| `[1]` Start | Launches in the background and **only reports success once the port actually answers**. If the process dies mid-startup it dumps the log tail instead of lying to you |
| `[2]` `[3]` | Stop / restart. Matches only the Tavern's own process — it will not kill other node processes on your phone |
| `[4]` Status | PID, port probe result, current version, backup count |
| `[5]` Logs | Last 30 lines. Follow live with `tail -f ~/.st-logs/server.log` |
| `[6]` Update | Moves to the latest stable release. **China mirrors lag behind** — if it sees a newer release upstream it offers to pull from GitHub instead |
| `[7]` Tavern Helper | Install / update the Tavern Helper extension |
| `[8]` Backup | Packs `data/` and `config.yaml` into `~/.st-snapshots/` |
| `[9]` Restore | Restores a backup. **It snapshots your current data first** |
| `[10]` Uninstall | Removes the Tavern, keeps your Termux environment |

---

## Keeping it alive

If Android kills Termux, the Tavern goes down with it. Do all three:

- Run Termux in a floating window / split screen
- Settings → Battery → Termux → **Unrestricted**
- Long-press the Termux card → Lock

---

## Where your data lives

| What | Where |
|------|-------|
| Chats, character cards, settings | `~/SillyTavern/data` |
| Config | `~/SillyTavern/config.yaml` |
| Server log | `~/.st-logs/server.log` |
| Backups | `~/.st-snapshots/` |

> ⚠️ `config.yaml` holds your API key. Think before sending a backup to anyone.

To copy it to a PC or cloud drive:

```bash
termux-setup-storage          # once, then restart Termux
tar -czf ~/storage/shared/st-data.tar.gz -C ~/SillyTavern data config.yaml
```

---

## Uninstalling

- **Tavern only** — menu `[10]`, or `rm -rf ~/SillyTavern`
- **Everything including Termux** — Android Settings → Apps → Termux → Uninstall

> ⚠️ Uninstalling Termux wipes your chat logs too. Back up first.

To come back: re-run the `curl` command, then menu `[9]` to restore.

---

## Which sources it downloads from

Everything prefers a China mirror and falls back overseas automatically:

| Content | China | Overseas |
|---------|-------|----------|
| Tavern core | Gitee `mirrors/sillytavern` | GitHub `SillyTavern/SillyTavern` |
| Tavern Helper | GitLab `novi028/JS-Slash-Runner` | GitHub `N0VI028/JS-Slash-Runner` |
| npm deps | npmmirror | npm official |
| apt packages | Tsinghua TUNA | Termux official |

It only goes overseas when every China source has failed. Nothing for you to manage.

---

## Troubleshooting

**Stuck / very slow**
If apt is already on the Tsinghua mirror, the slow step is probably npm. Let it finish. If it's truly wedged, Ctrl+C and re-run — completed steps are skipped.

**`CANNOT LINK ... SSL_set_quic_tls_transport_params`**
Termux packages are out of sync, usually from a manual install. The script detects this and repairs it with `apt full-upgrade` before retrying. You can also do it by hand:

```bash
apt update && apt full-upgrade -y
```

Note it's `apt`, **not `pkg upgrade`** — `pkg` is a shell wrapper that calls curl internally, and curl is exactly what's broken, so it fails alongside it.

**`st` → command not found**
The alias lives in `~/.bashrc`, which only gets re-read in a new session. In the current one, use `bash ~/st.sh`.

**Red error on start**
The script doesn't fake success. Check menu `[5]`. Usually port 8000 is taken, or dependencies are incomplete (just re-run `install.sh`).

**Update says "current source tops out at X, upstream has Y"**
The Gitee mirror lags. Answer `y` to pull from GitHub — slower, but current.

**Does uninstalling lose my chats?**
They're in `~/.st-snapshots/` (inside Termux, so don't uninstall Termux without copying them out first per *Where your data lives*).

---

## Hacking on it

The menu is generated from a `<<'ST_PANEL_EOF'` heredoc inside `install.sh`, written out to `~/st.sh` at install time. That's deliberate: it means a `curl | bash` install still ends up with a working panel, with no second network round-trip. **To change the menu, edit that heredoc.**

Check both after editing:

```bash
bash -n install.sh
sed -n "/<<'ST_PANEL_EOF'/,/^ST_PANEL_EOF$/p" install.sh | sed '1d;$d' | bash -n
```

You can test the panel without a phone — fabricate a `~/SillyTavern` (just needs `data/` and `config.yaml`), point the panel's paths at it, then drive it with piped input:

```bash
printf '8\n\n4\n\n9\n1\nn\n\n0\n' | bash /tmp/panel.sh   # backup → status → restore → exit
```

---

## License

Apache License 2.0 — see [LICENSE](LICENSE). Commercial use, modification and redistribution all permitted.
