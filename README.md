# Fenestrae 11

A Windows 11-style application launcher for KDE Plasma 6.

*Fenestrae* — Latin, plural of *fenestra*, "windows." The look of
Windows 11, without the way Windows functions: this launcher
keeps the face and replaces the behavior.

**By Farmer Jay** — https://farmerjay.dev

## What it does

- **Pinned grid, 3 rows x 8**, every icon the same size — no
  exceptions, on any surface.
- **All apps by category** — cards with 2x2 collages of their
  members, or a flat A-Z list. The menu remembers which view
  you left it in.
- **Your category rules win.** An app living in the wrong
  category? A settings field maps any app to any category, and
  your override replaces the categories the app claims for
  itself.
- **No Recommended section** — unless you turn it on in settings.
  Default is off, and stays off.
- **Your pins, your order.** Right-click any app to pin or unpin
  it; right-click a pin to move it earlier or later. Fenestrae
  keeps its own pin list.
- **Search the way it should work.** Type, the first match is
  highlighted, Enter launches it, arrow keys walk the results.
- **A footer that knows you.** Your account picture and name on
  the left — click them to open your account settings. Folder,
  Settings, and power on the right; power asks first, with the
  confirmation and countdown you expect.
- **Fast.** Categories build only their own apps, counts and
  collages are computed once, and search runs on a cached index.

## Requirements

KDE Plasma 6. Developed and tested on Fedora KDE (Plasma 6.7).

## Install

**From the KDE Store:** search "Fenestrae 11" in Discover or in
System Settings / panel "Get New Widgets", or install from
store.kde.org.

**From a release zip:**

```
kpackagetool6 --type Plasma/Applet --install fenestrae11-1.0.0.zip
```

Then right-click your current launcher, choose "Show
Alternatives", and pick Fenestrae 11.

## License

GPL-2.0-or-later — see LICENSE.
