// KickerBridge.qml
//
// THE BRIDGE. This is the ONLY file in Fenestrae 11 that touches KDE's
// private Kicker API (org.kde.plasma.private.kicker). Everything else in
// the widget talks to this file's properties and functions.
//
// Why: the Kicker models are private API and may change in a future
// Plasma major version. When that day comes, the port is confined to
// this one file instead of the whole widget.
//
// HARD-WON FACTS about this API on the AiO (Plasma 6.7.5, proven by
// the probe series, 2026-10-28 -- do not relearn these the hard way):
//  * The RootModel is ALWAYS two levels here. Even flat+showAllApps
//    returns category rows (12); row "All Applications" holds every
//    app in its sub-model. modelForRow() + data() reads from script
//    DO work: role 0 = name, role 1 = icon-name string, role 259 =
//    desktop-file ID string.
//  * roleNames() is unusable from script (returns nothing iterable).
//  * There is NO rowsAddedTo signal on the QML RootModel.
//  * The launchable item object is NOT reachable from script data()
//    (roles 265/266 are opaque). Launching works ONLY from inside a
//    view delegate, via model.item -- so every surface in Fenestrae
//    is a real view (GridView / ListView / Repeater), never a
//    script-built list. DelegateModel/Instantiator enumeration
//    produces nothing without a view pulling delegates.
//  * favoritesModel is PER-APPLET: a fresh RootModel reports zero
//    favorites while the user's other launcher has its own pins.
//    Fenestrae therefore keeps its OWN pin list (pinnedIds, stored
//    in the widget's config) instead of reading KDE favorites.

import QtQuick
import org.kde.plasma.private.kicker 0.1 as Kicker

Item {
    id: bridge
    visible: false

    // Category overrides from settings: { "desktopId": "Category Name" }.
    // An override WINS over the categories an app's .desktop file claims.
    // (Since v0.3.0 the regrouping below applies them: an overridden
    // app appears ONLY in its override category.)
    property var categoryOverrides: ({})

    // ----- models the UI binds to (all consumed by real views) -----
    // Categorized root: rows are the app categories.
    property var rootModel: rootModelImpl
    // Every app, A-Z: the sub-model of the "All Applications" row of
    // the CATEGORIZED root (showAllApps on). It must come from there,
    // not from a flat root: the flat root's All-Applications entries
    // carry no launchable item in their delegates -- clicking them in
    // v0.2.0 fell back to opening the .desktop file in a text editor.
    // The categorized root's sub-models are the family whose
    // delegates launched correctly from the very first build.
    property var allAppsModel: null
    // Recent apps (row "Recent Applications" of the categorized
    // root), used only by the default-off Recommended section.
    property var recentAppsModel: null
    // Power / session actions for the footer power menu.
    property var systemModel: systemModelImpl

    // ----- Fenestrae's own pins: desktop-file IDs, in config order --
    property var pinnedIds: []
    signal pinsEdited(var ids)

    function isPinned(id) {
        return id !== "" && pinnedIds.indexOf(id) >= 0;
    }

    function togglePin(id) {
        if (!id) {
            return;
        }
        let next = pinnedIds.slice();
        const at = next.indexOf(id);
        if (at >= 0) {
            next.splice(at, 1);
        } else {
            next.push(id);
        }
        pinnedIds = next;
        pinsEdited(next);
    }

    // Move a pin one step earlier (-1) or later (+1) in the order.
    function movePin(id, delta) {
        const at = pinnedIds.indexOf(id);
        if (at < 0) {
            return;
        }
        const to = at + delta;
        if (to < 0 || to >= pinnedIds.length) {
            return;
        }
        let next = pinnedIds.slice();
        next.splice(at, 1);
        next.splice(to, 0, id);
        pinnedIds = next;
        pinsEdited(next);
    }

    // The pinned apps as display entries, IN PIN ORDER (v0.3.1):
    // [{ id, name, icon }] built from the all-apps model by script
    // (data() reads are safe). Pins whose app is gone are skipped.
    function pinnedEntries() {
        const out = [];
        if (!allAppsModel) {
            return out;
        }
        // v0.3.3: names/icons come from the rebuild caches; the
        // pinned IDs are checked against the catalog's ID list.
        const byId = {};
        for (let i = 0; i < allIdsInOrder.length; ++i) {
            const id = allIdsInOrder[i];
            byId[id] = { "name": nameById[id] || "", "icon": iconById[id] || "" };
        }
        for (let k = 0; k < pinnedIds.length; ++k) {
            const id = pinnedIds[k];
            const info = byId[id];
            if (info) {
                out.push({ "id": id, "name": info.name, "icon": info.icon });
            }
        }
        return out;
    }

    // Desktop-file ID of a row in any Kicker model (role 259, proven
    // by probe sweep on the AiO). Script-side data() reads are safe;
    // only the item object is off-limits from here.
    function desktopIdOf(m, row) {
        if (!m || row < 0) {
            return "";
        }
        try {
            return String(m.data(m.index(row, 0), 259) || "");
        } catch (e) {
            return "";
        }
    }

    function nameOf(m, row) {
        if (!m || row < 0) {
            return "";
        }
        try {
            return String(m.data(m.index(row, 0), Qt.DisplayRole) || "");
        } catch (e) {
            return "";
        }
    }

    // Find a top-level row by its display name; -1 when absent.
    function findRow(m, displayName) {
        if (!m) {
            return -1;
        }
        for (let i = 0; i < m.count; ++i) {
            if (nameOf(m, i) === displayName) {
                return i;
            }
        }
        return -1;
    }

    function refreshDerivedModels() {
        if (!allAppsModel && rootModelImpl.count > 0) {
            const row = findRow(rootModelImpl, "All Applications");
            if (row >= 0) {
                allAppsModel = rootModelImpl.modelForRow(row);
            }
        }
        if (!recentAppsModel && rootModelImpl.count > 0) {
            const row = findRow(rootModelImpl, "Recent Applications");
            if (row >= 0) {
                recentAppsModel = rootModelImpl.modelForRow(row);
            }
        }
        scheduleRebuild();
    }

    Component.onCompleted: refreshDerivedModels()

    onCategoryOverridesChanged: scheduleRebuild()

    // ----- category regrouping (v0.3.0) -----
    // Kicker's own category models cannot be edited, so Fenestrae
    // computes membership itself. Script data() reads are safe
    // (bridge facts), so a scan of every category sub-model yields
    // each app's claimed categories. An app's EFFECTIVE categories:
    // its override as the single entry when one is set -- the
    // override replaces ALL claimed membership, including the
    // Recent Applications row, which this UI presents as a
    // category card -- otherwise its claimed list, unchanged.
    // Views render from allAppsModel delegates (the launchable
    // family) gated by inCategory(); the cards read categoryNames
    // + collageIcons()/categoryCount(). membershipStamp bumps on
    // every rebuild so views can subscribe to it inside bindings.
    property var claimedById: ({})
    property var iconById: ({})
    property var categoryNames: []
    property int membershipStamp: 0
    // Speed-pass caches (v0.3.3), all rebuilt inside
    // rebuildCategoryMap() in passes it already makes:
    //   nameById / allIdsInOrder -- so pinnedEntries() and
    //     categoryEntries() read plain JS data instead of walking
    //     the model with data() calls per row, per binding run.
    //   lowerNames -- lowercase app names in all-apps order, so a
    //     search keystroke scans cached strings, not model reads.
    //   categoryCounts / categoryCollages -- so the home cards'
    //     count and collage bindings are O(1) map reads instead of
    //     a full catalog walk per card (12 cards x 2 walks on every
    //     menu open was the visible drag).
    property var nameById: ({})
    property var allIdsInOrder: []
    property var lowerNames: []
    property var categoryCounts: ({})
    property var categoryCollages: ({})

    function scheduleRebuild() {
        rebuildTimer.restart();
    }

    Timer {
        id: rebuildTimer
        interval: 400
        onTriggered: bridge.rebuildCategoryMap()
    }

    function rebuildCategoryMap() {
        const claimed = {};
        const icons = {};
        const names = [];
        const namesByIdLocal = {};
        const idsInOrder = [];
        const lowers = [];
        if (allAppsModel) {
            for (let i = 0; i < allAppsModel.count; ++i) {
                const id = desktopIdOf(allAppsModel, i);
                if (id) {
                    try {
                        icons[id] = String(allAppsModel.data(allAppsModel.index(i, 0), 1) || "");
                    } catch (e) {
                        icons[id] = "";
                    }
                    const nm = nameOf(allAppsModel, i);
                    namesByIdLocal[id] = nm;
                    if (idsInOrder.indexOf(id) < 0) {
                        idsInOrder.push(id);
                        // lowerNames stays parallel to
                        // allIdsInOrder (searchEntries indexes
                        // them together) -- push only for new IDs.
                        lowers.push(nm.toLowerCase());
                    }
                }
            }
        }
        for (let r = 0; r < rootModelImpl.count; ++r) {
            const cname = nameOf(rootModelImpl, r);
            if (!cname || cname === "All Applications") {
                continue;
            }
            const sub = rootModelImpl.modelForRow(r);
            if (!sub) {
                continue;
            }
            if (names.indexOf(cname) < 0) {
                names.push(cname);
            }
            for (let i = 0; i < sub.count; ++i) {
                const id = desktopIdOf(sub, i);
                if (!id) {
                    continue;
                }
                if (!claimed[id]) {
                    claimed[id] = [];
                }
                if (claimed[id].indexOf(cname) < 0) {
                    claimed[id].push(cname);
                }
            }
        }
        // Custom override targets become cards of their own, after
        // Plasma's categories, in the order the settings list them.
        for (const id in categoryOverrides) {
            const target = categoryOverrides[id];
            if (typeof target === "string" && target !== ""
                    && target !== "All Applications"
                    && names.indexOf(target) < 0) {
                names.push(target);
            }
        }
        claimedById = claimed;
        iconById = icons;
        categoryNames = names;
        nameById = namesByIdLocal;
        allIdsInOrder = idsInOrder;
        lowerNames = lowers;
        // One counting pass over the catalog fills every card's
        // count and collage, so the bindings never walk it again.
        const counts = {};
        const collages = {};
        for (let k = 0; k < idsInOrder.length; ++k) {
            const id = idsInOrder[k];
            const cats = effectiveCategories(id);
            for (let c = 0; c < cats.length; ++c) {
                const cat = cats[c];
                counts[cat] = (counts[cat] || 0) + 1;
                if (icons[id]) {
                    if (!collages[cat]) {
                        collages[cat] = [];
                    }
                    if (collages[cat].length < 8) {
                        collages[cat].push(icons[id]);
                    }
                }
            }
        }
        categoryCounts = counts;
        categoryCollages = collages;
        membershipStamp += 1;
    }

    // All search matches as entries (v1.0.0), in A-Z order, from
    // the caches: [{ id, name, icon }]. The search page renders
    // these directly, so its list contains ONLY matches -- which
    // is what makes keyboard navigation honest (no hidden rows
    // for the highlight to vanish into).
    function searchEntries(lowerText) {
        const out = [];
        if (!lowerText) {
            return out;
        }
        for (let i = 0; i < lowerNames.length; ++i) {
            if (lowerNames[i].indexOf(lowerText) >= 0) {
                const id = allIdsInOrder[i];
                if (id) {
                    out.push({
                        "id": id,
                        "name": nameById[id] || "",
                        "icon": iconById[id] || ""
                    });
                }
            }
        }
        return out;
    }

    // Search helper over the cached lowercase names (v0.3.3):
    // true when any app name contains the (already lowercased) text.
    function anyMatch(lowerText) {
        if (!lowerText) {
            return false;
        }
        for (let i = 0; i < lowerNames.length; ++i) {
            if (lowerNames[i].indexOf(lowerText) >= 0) {
                return true;
            }
        }
        return false;
    }

    function effectiveCategories(id) {
        const o = categoryOverrides[id];
        if (typeof o === "string" && o !== "") {
            return [o];
        }
        return claimedById[id] || [];
    }

    function inCategory(id, categoryName) {
        if (!id || !categoryName) {
            return false;
        }
        return effectiveCategories(id).indexOf(categoryName) >= 0;
    }

    function categoryCount(categoryName) {
        // v0.3.3: precomputed in rebuildCategoryMap(); this used to
        // walk the whole catalog per call (once per card binding).
        return categoryCounts[categoryName] || 0;
    }

    // First `max` member icon names, in all-apps (A-Z) order.
    // v0.3.3: sliced from the precomputed collage cache (the cache
    // keeps up to 8; the cards ask for 4).
    function collageIcons(categoryName, max) {
        const c = categoryCollages[categoryName];
        return c ? c.slice(0, max) : [];
    }

    // Member entries [{id, name, icon}] of one category, A-Z --
    // the drill-in page's data (v0.3.3 speed pass: the page
    // builds tiles ONLY for its category's members, from this
    // plain array, instead of instantiating a tile per app in
    // the whole catalog behind a visibility gate).
    function categoryEntries(categoryName) {
        const out = [];
        if (!allAppsModel || !categoryName) {
            return out;
        }
        for (let i = 0; i < allAppsModel.count; ++i) {
            const id = desktopIdOf(allAppsModel, i);
            if (id && inCategory(id, categoryName)) {
                out.push({
                    "id": id,
                    "name": nameById[id] || nameOf(allAppsModel, i),
                    "icon": iconById[id] || ""
                });
            }
        }
        return out;
    }

    Kicker.RootModel {
        id: rootModelImpl
        autoPopulate: true
        flat: false
        sorted: true
        showAllApps: true
        showRecentApps: true
        showRecentDocs: false
        showPowerSession: false
        onCountChanged: bridge.refreshDerivedModels()
    }

    Kicker.SystemModel {
        id: systemModelImpl
        favoritesModel: rootModelImpl.favoritesModel
    }

    // Session actions, keyed by the SystemModel row's display text.
    // The systemModel delegates' own item activation does nothing on
    // this system (same dead delegate-item path as the app models),
    // so power actions run as commands through the Exec engine.
    // Shut Down / Reboot / Log Out call org.kde.LogoutPrompt
    // (promptShutDown / promptReboot / promptLogout) via gdbus --
    // the D-Bus-activated front door that shows KDE's confirmation
    // screen with its countdown (proven by John's pre-test and the
    // v0.2.11 install, 2026-10-28). Closed doors, for the record:
    // systemctl (instant, no prompt), qdbus6/qdbus (not installed),
    // org.kde.Shutdown (executes with no prompt), the classic
    // ksmserver logout method (removed in Plasma 6), and running
    // ksmserver-logout-greeter bare (hangs the session -- never
    // again). Suspend and Lock stay direct. Returns "" for rows we
    // do not map.
    function sessionCommandFor(displayText) {
        const d = String(displayText || "").toLowerCase();
        if (d.indexOf("shut down") >= 0 || d.indexOf("power off") >= 0) {
            return "gdbus call --session --dest org.kde.LogoutPrompt --object-path /LogoutPrompt --method org.kde.LogoutPrompt.promptShutDown";
        }
        if (d.indexOf("reboot") >= 0 || d.indexOf("restart") >= 0) {
            return "gdbus call --session --dest org.kde.LogoutPrompt --object-path /LogoutPrompt --method org.kde.LogoutPrompt.promptReboot";
        }
        if (d.indexOf("suspend") >= 0 || d.indexOf("sleep") >= 0 || d.indexOf("hibernate") >= 0) {
            return "systemctl suspend";
        }
        if (d.indexOf("log out") >= 0 || d.indexOf("logout") >= 0) {
            return "gdbus call --session --dest org.kde.LogoutPrompt --object-path /LogoutPrompt --method org.kde.LogoutPrompt.promptLogout";
        }
        if (d.indexOf("lock") >= 0) {
            return "loginctl lock-session";
        }
        if (d.indexOf("switch user") >= 0) {
            return "dm-tool switch-to-greeter";
        }
        return "";
    }

    // Launch the app behind a view delegate.
    // `m` is the delegate's `model` object -- the ONLY place the
    // launchable item is reachable (see facts above).
    function launchModel(m) {
        if (!m) {
            return;
        }
        if (m.item && typeof m.item.launch === "function") {
            m.item.launch();
        }
        // Deliberately NO url fallback: in v0.2.0 a missing item made
        // the fallback open the app's .desktop file in a text editor.
        // A launch that cannot happen must do nothing, never that.
    }
}
