// Fenestrae 11 -- main.qml
//
// A Windows 11-style launcher for Plasma 6, built to John's locked
// layout (variant A, 2026-10-28):
//   - search pill on top
//   - Pinned: 3 rows x 8, EVERY icon the same size
//   - All: category cards (2x2 collages), 3 rows x 4 -- or a flat list
//   - Recommended: only when the settings toggle is on (default OFF)
//   - footer: user left; folder / settings / power right
//
// All contact with KDE's private Kicker API lives in KickerBridge.qml.
// This file only talks to the bridge.
//
// v0.2.0 architecture (from the AiO probe series): every surface is a
// real QML view over a Kicker model, because view delegates are the
// only place the launchable item exists. Pinned is Fenestrae's OWN
// pin list (Plasma favorites are per-launcher): a Repeater over the
// all-apps model where non-pinned apps collapse to zero size.

import QtQuick
import QtQml
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ----- state -----
    // "category" | "list" -- persisted (v1.0.0): the menu opens
    // the way the user left it, across shell restarts.
    property string viewMode: Plasmoid.configuration.viewMode || "category"
    onViewModeChanged: {
        Plasmoid.configuration.viewMode = viewMode;
    }
    property string currentCategoryName: ""
    // Search text lives at ROOT scope. (In every 0.1.x/0.2.0 build
    // these bindings referenced the searchField inside the full
    // representation -- a different component scope -- and died with
    // ReferenceError, which is why search never worked.)
    property string searchText: ""
    readonly property bool searching: searchText.length > 0
    readonly property string filterText: searchText.trim().toLowerCase()
    readonly property int pageIndex: searching ? 2 : (currentCategoryName !== "" ? 1 : 0)

    // ----- the bridge (sole owner of the private Kicker API) -----
    KickerBridge {
        id: bridge
        categoryOverrides: {
            try {
                return JSON.parse(Plasmoid.configuration.categoryOverrides || "{}");
            } catch (e) {
                return {};
            }
        }
        onPinsEdited: (ids) => {
            Plasmoid.configuration.pinnedApps = ids;
        }
    }

    Component.onCompleted: {
        bridge.pinnedIds = Plasmoid.configuration.pinnedApps || [];
    }

    // Footer shortcuts have no view delegate to launch through, so
    // they run the desktop file directly (Exec.qml, Loader-isolated).
    Loader {
        id: execLoader
        source: "Exec.qml"
    }

    // THE launch path (v0.2.2, detached in v0.2.12): by desktop-file
    // ID, through the executable engine. Proven on the AiO by the
    // footer buttons, while delegate item.launch() silently does
    // nothing on this system's All-Applications model. gtk-launch
    // searches all the standard application directories (system,
    // user, flatpak); gio on the system path is the fallback. An ID
    // containing "/" is already a full path.
    //
    // v0.2.12 -- the Dragon Player fix. Dragon would not launch
    // from Fenestrae at all while `dragon`, `gtk-launch <id>` and
    // `gio launch` all worked in Konsole (John's tests, 2026-10-29).
    // Mechanism: gtk-launch stays ATTACHED to a non-D-Bus-activated
    // app for the app's whole lifetime (Dragon is one), and the
    // executable engine kills the process it still holds when the
    // source disconnects -- which the menu closing triggers.
    // D-Bus-activated apps (Dolphin, System Settings) survive
    // because their gtk-launch exits on its own after the hand-off.
    // The cure is to launch DETACHED: setsid starts the launcher in
    // its own session, out of the engine's reach, with output
    // dropped so the engine's source completes immediately.
    function launchDesktopFile(desktopId) {
        if (!execLoader.item || !desktopId) {
            return;
        }
        console.log("Fenestrae launch: " + desktopId);
        if (desktopId.indexOf("/") >= 0) {
            execLoader.item.run("setsid -f gio launch '" + desktopId + "' >/dev/null 2>&1");
        } else {
            execLoader.item.run("setsid -f sh -c \"gtk-launch '" + desktopId
                + "' || gio launch '/usr/share/applications/" + desktopId + "'\" >/dev/null 2>&1");
        }
    }

    // Tile activation: desktop ID first; the delegate item is the
    // fallback for entries that expose no ID.
    function activateApp(desktopId, modelObj) {
        root.closeAndLaunch(() => {
            if (desktopId) {
                root.launchDesktopFile(desktopId);
            } else {
                bridge.launchModel(modelObj);
            }
        });
    }

    function closeAndLaunch(action) {
        action();
        root.expanded = false;
    }

    // Whether any app name matches the current search text. Script
    // data() reads are safe (names are role 0); only launching needs
    // a delegate. Used for the search empty-state label.
    // How many configured pins actually resolve to installed apps.
    // (Script data() reads are safe; only launching needs delegates.)
    // The pinned entries IN PIN ORDER (v0.3.1). Dependencies:
    // pinnedIds (reorder/edit), the all-apps model (contents), and
    // membershipStamp (bumps once the models are populated).
    readonly property var pinnedEntries: {
        bridge.membershipStamp;
        return bridge.pinnedEntries();
    }

    function visiblePinCount() {
        return pinnedEntries.length;
    }

    // The open category's member entries (v0.3.3 speed pass):
    // computed once per category/rebuild, so the drill page's
    // Repeater builds tiles ONLY for members -- the pre-0.3.3 page
    // instantiated a tile for every app in the catalog and hid the
    // non-members, which made opening any category pay for all of
    // them. Empty while no category is open.
    readonly property var currentEntries: {
        bridge.membershipStamp;
        return bridge.categoryEntries(currentCategoryName);
    }

    // Search results as plain entries (v1.0.0): matches only, so
    // the results list's keyboard highlight never lands on a
    // hidden row. Rebuilt per keystroke from the bridge caches.
    readonly property var searchEntries: {
        bridge.membershipStamp;
        return searching ? bridge.searchEntries(filterText) : [];
    }

    onExpandedChanged: {
        if (root.expanded) {
            bridge.rebuildCategoryMap();
        } else {
            root.searchText = "";
            root.currentCategoryName = "";
        }
    }

    toolTipMainText: "Fenestrae 11"
    toolTipSubText: "Windows 11's face, your rules underneath."

    // ----- panel button: John's startdark icon -----
    compactRepresentation: MouseArea {
        hoverEnabled: true
        onClicked: root.expanded = !root.expanded
        Image {
            anchors.fill: parent
            anchors.margins: 2
            source: Qt.resolvedUrl("start.png")
            fillMode: Image.PreserveAspectFit
            smooth: true
        }
    }

    // One app row for the List view and search results. The row height
    // collapses to zero when a search filter excludes it (the filter
    // is empty in plain List mode, so every row shows).
    Component {
        id: appRowDelegate
        Item {
            id: rowItem
            readonly property string appName: model.display !== undefined && model.display !== null ? String(model.display) : ""
            readonly property bool matches: root.filterText.length === 0
                || appName.toLowerCase().indexOf(root.filterText) >= 0
            readonly property string rowDesktopId: bridge.desktopIdOf(ListView.view.model, index)
            width: ListView.view ? ListView.view.width : 0
            height: matches ? Kirigami.Units.gridUnit * 2.6 : 0
            visible: matches

            Rectangle {
                anchors.fill: parent
                radius: Kirigami.Units.smallSpacing
                color: Kirigami.Theme.highlightColor
                opacity: rowMouse.containsMouse ? 0.22 : 0.0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 90
                    }
                }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Kirigami.Units.largeSpacing
                anchors.rightMargin: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing
                Kirigami.Icon {
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                    source: model.decoration
                    fallback: "application-x-executable"
                }
                PC3.Label {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    text: rowItem.appName
                }
            }
            MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (event) => {
                    if (event.button === Qt.RightButton && rowItem.rowDesktopId !== "") {
                        rowPinMenu.open();
                    } else if (event.button === Qt.LeftButton) {
                        root.activateApp(rowItem.rowDesktopId, model);
                    }
                }
            }
            QQC2.Menu {
                id: rowPinMenu
                QQC2.MenuItem {
                    text: bridge.isPinned(rowItem.rowDesktopId) ? "Unpin from Start" : "Pin to Start"
                    onTriggered: bridge.togglePin(rowItem.rowDesktopId)
                }
            }
        }
    }

    // ----- the menu itself -----
    fullRepresentation: Item {
        id: menuRoot

        // Root-scope plumbing that needs the search field: focus it
        // when the menu opens, and mirror root.searchText into it
        // when the root clears the text (on close).
        Connections {
            target: root
            function onExpandedChanged() {
                if (root.expanded) {
                    searchField.forceActiveFocus();
                }
            }
            function onSearchTextChanged() {
                if (searchField.text !== root.searchText) {
                    searchField.text = root.searchText;
                }
                if (root.searching) {
                    searchList.currentIndex = 0;
                }
            }
        }
        Layout.preferredWidth: Kirigami.Units.gridUnit * 49
        Layout.preferredHeight: Kirigami.Units.gridUnit * 52
        Layout.minimumWidth: Kirigami.Units.gridUnit * 30
        Layout.minimumHeight: Kirigami.Units.gridUnit * 30

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.gridUnit * 1.6
            spacing: Kirigami.Units.largeSpacing

            // Search pill
            PC3.TextField {
                id: searchField
                Layout.fillWidth: true
                placeholderText: "Search for apps, settings, and documents"
                leftPadding: Kirigami.Units.gridUnit * 1.8
                onTextChanged: {
                    if (root.searchText !== text) {
                        root.searchText = text;
                    }
                }
                // Keyboard (v1.0.0): Enter launches the highlighted
                // result (the first match, until arrows move the
                // highlight); Up/Down move the highlight. Focus
                // stays in the field the whole time.
                onAccepted: {
                    if (root.searching) {
                        const e = root.searchEntries[Math.max(0, searchList.currentIndex)];
                        if (e) {
                            root.activateApp(e.id, null);
                        }
                    }
                }
                Keys.onDownPressed: {
                    if (root.searching) {
                        searchList.incrementCurrentIndex();
                    }
                }
                Keys.onUpPressed: {
                    if (root.searching) {
                        searchList.decrementCurrentIndex();
                    }
                }
                Keys.onEscapePressed: {
                    if (text.length > 0) {
                        text = "";
                    } else if (root.currentCategoryName !== "") {
                        root.currentCategoryName = "";
                    } else {
                        root.expanded = false;
                    }
                }
                Kirigami.Icon {
                    anchors.left: parent.left
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.verticalCenter: parent.verticalCenter
                    width: Kirigami.Units.iconSizes.smallMedium
                    height: width
                    source: "search"
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.pageIndex

                // ============ PAGE 0: HOME ============
                ColumnLayout {
                    spacing: Kirigami.Units.largeSpacing

                    PC3.Label {
                        text: "Pinned"
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                    }

                    // Fenestrae's own pins, IN PIN ORDER (v0.3.1):
                    // a Repeater over Fenestrae's own entries --
                    // uniform tile size, launch by desktop ID
                    // (the proven path), right-click offers
                    // Unpin and Move earlier/later.
                    Flow {
                        id: pinnedFlow
                        Layout.fillWidth: true
                        spacing: 0
                        Repeater {
                            model: root.pinnedEntries
                            delegate: AppTile {
                                // Index-based entry lookup, NOT
                                // modelData: v0.3.1 bound the entry
                                // through the delegate's modelData,
                                // which AppTile's own modelData
                                // property shadows -- the tiles drew
                                // (fallbacks) but every ID arrived
                                // empty, so clicks and Move silently
                                // did nothing (John's test, 2026-10-29).
                                readonly property var entry: root.pinnedEntries[index]
                                width: pinnedFlow.width / Plasmoid.configuration.pinnedColumns
                                height: Kirigami.Units.gridUnit * 5
                                iconSize: Plasmoid.configuration.pinnedIconSize
                                forcedDesktopId: entry ? entry.id : ""
                                iconOverride: entry ? entry.icon : ""
                                nameOverride: entry ? entry.name : ""
                                isPinned: true
                                canMove: true
                                onActivated: (id) => root.activateApp(id, null)
                                onPinToggleRequested: (id) => bridge.togglePin(id)
                                onMoveRequested: (id, delta) => bridge.movePin(id, delta)
                            }
                        }
                    }
                    PC3.Label {
                        visible: bridge.allAppsModel !== null && root.visiblePinCount() === 0
                        text: "Nothing pinned yet -- right-click any app to pin it here."
                        opacity: 0.7
                    }

                    // Recommended -- rendered ONLY when the user turns it
                    // on in settings. Default is off (John's ruling).
                    PC3.Label {
                        visible: Plasmoid.configuration.showRecommended
                        text: "Recommended"
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                    }

                    GridView {
                        visible: Plasmoid.configuration.showRecommended
                        Layout.fillWidth: true
                        Layout.preferredHeight: cellHeight
                        interactive: false
                        model: bridge.recentAppsModel
                        cellWidth: width / Plasmoid.configuration.pinnedColumns
                        cellHeight: Kirigami.Units.gridUnit * 5
                        delegate: AppTile {
                            width: GridView.view.cellWidth
                            height: GridView.view.cellHeight
                            iconSize: Plasmoid.configuration.pinnedIconSize
                            modelData: model
                            sourceModel: bridge.recentAppsModel
                            rowIndex: index
                            isPinned: bridge.isPinned(bridge.desktopIdOf(bridge.recentAppsModel, index))
                            onActivated: (id) => root.activateApp(id, model)
                            onPinToggleRequested: (id) => bridge.togglePin(id)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        PC3.Label {
                            text: "All"
                            font.bold: true
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        QQC2.Button {
                            flat: true
                            text: root.viewMode === "category" ? "View: Category" : "View: List"
                            onClicked: viewMenu.open()
                            QQC2.Menu {
                                id: viewMenu
                                QQC2.MenuItem {
                                    text: "Category"
                                    onTriggered: root.viewMode = "category"
                                }
                                QQC2.MenuItem {
                                    text: "List"
                                    onTriggered: root.viewMode = "list"
                                }
                            }
                        }
                    }

                    // Category cards
                    Flickable {
                        visible: root.viewMode === "category"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: catGrid.height
                        clip: true
                        GridLayout {
                            id: catGrid
                            width: parent.width
                            columns: 4
                            columnSpacing: Kirigami.Units.largeSpacing
                            rowSpacing: Kirigami.Units.largeSpacing
                            Repeater {
                                // Fenestrae's effective categories
                                // (v0.3.0): Plasma's categories with
                                // the user's overrides REGROUPED, plus
                                // any custom override targets. The
                                // stamp references make these bindings
                                // re-run on every membership rebuild.
                                model: bridge.categoryNames
                                delegate: CategoryCard {
                                    Layout.fillWidth: true
                                    visible: {
                                        bridge.membershipStamp;
                                        return bridge.categoryCount(modelData) > 0;
                                    }
                                    title: modelData
                                    iconSize: Plasmoid.configuration.collageIconSize
                                    collageIcons: {
                                        bridge.membershipStamp;
                                        return bridge.collageIcons(modelData, 4);
                                    }
                                    onActivated: {
                                        root.currentCategoryName = modelData;
                                    }
                                }
                            }
                        }
                    }

                    // Flat alphabetical List view: a real ListView
                    // over the all-apps model (delegates launch).
                    ListView {
                        visible: root.viewMode === "list"
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        cacheBuffer: Kirigami.Units.gridUnit * 30
                        model: bridge.allAppsModel
                        delegate: appRowDelegate
                        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
                    }
                }

                // ============ PAGE 1: ONE CATEGORY ============
                ColumnLayout {
                    spacing: Kirigami.Units.largeSpacing
                    RowLayout {
                        QQC2.ToolButton {
                            icon.name: "go-previous"
                            onClicked: {
                                root.currentCategoryName = "";
                            }
                        }
                        PC3.Label {
                            text: root.currentCategoryName
                            font.bold: true
                            font.pointSize: Kirigami.Theme.defaultFont.pointSize + 2
                        }
                    }
                    // One category's apps (v0.3.3 speed pass): a
                    // Flow over the category's member ENTRIES --
                    // the Pinned pattern (plain array, tiles fed by
                    // entry, launch by desktop ID). A GridView over
                    // Kicker's category model cannot regroup, and
                    // the v0.3.0 gated-delegate Flow instantiated
                    // every app in the catalog per category open;
                    // this builds only the members' tiles.
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: drillFlow.height
                        clip: true
                        Flow {
                            id: drillFlow
                            width: parent.width
                            spacing: 0
                            Repeater {
                                model: root.currentEntries
                                delegate: AppTile {
                                    // Index-based entry lookup, NOT
                                    // modelData (same shadowing trap
                                    // as the pinned tiles, v0.3.1).
                                    readonly property var entry: root.currentEntries[index]
                                    width: drillFlow.width / Plasmoid.configuration.pinnedColumns
                                    height: Kirigami.Units.gridUnit * 5
                                    iconSize: Plasmoid.configuration.pinnedIconSize
                                    forcedDesktopId: entry ? entry.id : ""
                                    iconOverride: entry ? entry.icon : ""
                                    nameOverride: entry ? entry.name : ""
                                    isPinned: bridge.isPinned(entry ? entry.id : "")
                                    onActivated: (id) => root.activateApp(id, null)
                                    onPinToggleRequested: (id) => bridge.togglePin(id)
                                }
                            }
                        }
                    }
                    PC3.Label {
                        visible: {
                            bridge.membershipStamp;
                            return root.currentCategoryName !== ""
                                && bridge.categoryCount(root.currentCategoryName) === 0;
                        }
                        text: "No apps in this category."
                        opacity: 0.7
                    }
                }

                // ============ PAGE 2: SEARCH RESULTS ============
                ColumnLayout {
                    spacing: Kirigami.Units.largeSpacing
                    PC3.Label {
                        text: "Results"
                        font.bold: true
                        font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                    }
                    ListView {
                        id: searchList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        cacheBuffer: Kirigami.Units.gridUnit * 30
                        model: root.searchEntries
                        delegate: Item {
                            id: searchRow
                            // Index-based entry lookup, NOT
                            // modelData (the AppTile shadowing trap).
                            readonly property var entry: root.searchEntries[index]
                            width: ListView.view ? ListView.view.width : 0
                            height: Kirigami.Units.gridUnit * 2.6
                            Rectangle {
                                anchors.fill: parent
                                radius: Kirigami.Units.smallSpacing
                                color: Kirigami.Theme.highlightColor
                                opacity: searchRow.ListView.isCurrentItem ? 0.35
                                    : (searchRowMouse.containsMouse ? 0.22 : 0.0)
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 90
                                    }
                                }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Kirigami.Units.largeSpacing
                                anchors.rightMargin: Kirigami.Units.largeSpacing
                                spacing: Kirigami.Units.largeSpacing
                                Kirigami.Icon {
                                    implicitWidth: Kirigami.Units.iconSizes.medium
                                    implicitHeight: Kirigami.Units.iconSizes.medium
                                    source: searchRow.entry ? searchRow.entry.icon : ""
                                    fallback: "application-x-executable"
                                }
                                PC3.Label {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    text: searchRow.entry ? searchRow.entry.name : ""
                                }
                            }
                            MouseArea {
                                id: searchRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: (event) => {
                                    searchList.currentIndex = index;
                                    if (event.button === Qt.RightButton && searchRow.entry) {
                                        searchPinMenu.open();
                                    } else if (event.button === Qt.LeftButton && searchRow.entry) {
                                        root.activateApp(searchRow.entry.id, null);
                                    }
                                }
                            }
                            QQC2.Menu {
                                id: searchPinMenu
                                QQC2.MenuItem {
                                    text: bridge.isPinned(searchRow.entry ? searchRow.entry.id : "") ? "Unpin from Start" : "Pin to Start"
                                    onTriggered: {
                                        if (searchRow.entry) {
                                            bridge.togglePin(searchRow.entry.id);
                                        }
                                    }
                                }
                            }
                        }
                        QQC2.ScrollBar.vertical: QQC2.ScrollBar {}
                    }
                    PC3.Label {
                        visible: root.searching && root.searchEntries.length === 0
                        text: "No apps match."
                        opacity: 0.7
                    }
                }
            }

            Kirigami.Separator {
                Layout.fillWidth: true
            }

            // ============ POWER POPUP ============
            // A real VIEW over the system model -- not a QQC2.Menu
            // fed by an Instantiator. Instantiator-created items have
            // inert model objects on this system (the 0.1.x-0.2.5
            // power menu did nothing at all), while view delegates
            // are the live kind -- the same reason app launching
            // works from grids and lists. Clicking a row activates
            // the entry exactly the way the stock menus do, so KDE's
            // own confirmation screen and countdown come with it.
            QQC2.Popup {
                id: powerPopup
                parent: menuRoot
                width: Kirigami.Units.gridUnit * 13
                height: powerList.contentHeight + Kirigami.Units.largeSpacing * 2
                padding: Kirigami.Units.largeSpacing
                modal: false
                focus: true
                closePolicy: QQC2.Popup.CloseOnEscape | QQC2.Popup.CloseOnPressOutside

                ListView {
                    id: powerList
                    anchors.fill: parent
                    clip: true
                    model: bridge.systemModel
                    delegate: Item {
                        width: ListView.view ? ListView.view.width : 0
                        height: Kirigami.Units.gridUnit * 2.4
                        Rectangle {
                            anchors.fill: parent
                            radius: Kirigami.Units.smallSpacing
                            color: Kirigami.Theme.highlightColor
                            opacity: powerRowMouse.containsMouse ? 0.22 : 0.0
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Kirigami.Units.largeSpacing
                            anchors.rightMargin: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.largeSpacing
                            Kirigami.Icon {
                                implicitWidth: Kirigami.Units.iconSizes.smallMedium
                                implicitHeight: Kirigami.Units.iconSizes.smallMedium
                                source: model.decoration
                                fallback: "system-shutdown"
                            }
                            PC3.Label {
                                Layout.fillWidth: true
                                text: model.display !== undefined && model.display !== null ? String(model.display) : ""
                            }
                        }
                        MouseArea {
                            id: powerRowMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                powerPopup.close();
                                const cmd = bridge.sessionCommandFor(model.display);
                                if (cmd !== "" && execLoader.item) {
                                    root.expanded = false;
                                    execLoader.item.run(cmd);
                                } else {
                                    root.closeAndLaunch(() => bridge.launchModel(model));
                                }
                            }
                        }
                    }
                }
            }

            // ============ FOOTER ============
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing

                Loader {
                    id: userLoader
                    source: "UserInfo.qml"
                }
                // The account button (v0.3.4): avatar + name are
                // one clickable unit that opens System Settings at
                // the Users page -- the Windows 11 behavior John
                // asked for ("link the Avatar to accounts"). The
                // avatar itself is hand-rolled (initials in a circle,
                // like the locked mockup): Kirigami.Avatar is not a
                // type on Fedora 44's Kirigami -- that was the v0.1.0
                // load failure on the AiO.
                Item {
                    id: accountButton
                    Layout.preferredWidth: accountRow.implicitWidth + Kirigami.Units.largeSpacing
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2.4
                    QQC2.ToolTip.text: "Account settings"
                    QQC2.ToolTip.visible: accountMouse.containsMouse
                    Rectangle {
                        anchors.fill: parent
                        radius: Kirigami.Units.smallSpacing
                        color: Kirigami.Theme.highlightColor
                        opacity: accountMouse.containsMouse ? 0.22 : 0.0
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 90
                            }
                        }
                    }
                    MouseArea {
                        id: accountMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (execLoader.item) {
                                root.expanded = false;
                                execLoader.item.run("setsid -f systemsettings kcm_users >/dev/null 2>&1");
                            }
                        }
                    }
                    RowLayout {
                        id: accountRow
                        anchors.left: parent.left
                        anchors.leftMargin: Kirigami.Units.smallSpacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Kirigami.Units.largeSpacing
                    Item {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 2
                    Layout.preferredHeight: Kirigami.Units.gridUnit * 2
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Kirigami.Theme.highlightColor
                    }
                    PC3.Label {
                        anchors.centerIn: parent
                        font.bold: true
                        color: Kirigami.Theme.highlightedTextColor
                        visible: faceLoader.status !== Loader.Ready
                        text: {
                            const n = userLoader.item
                                ? (userLoader.item.displayName || "?")
                                : "?";
                            const parts = n.trim().split(/\s+/);
                            return (parts.length > 1
                                ? (parts[0].charAt(0) + parts[parts.length - 1].charAt(0))
                                : n.slice(0, 2)).toUpperCase();
                        }
                    }
                    // The real avatar, when the account has one:
                    // circular-cropped face image over the initials.
                    Loader {
                        id: faceLoader
                        anchors.fill: parent
                        active: userLoader.item !== null
                                && userLoader.item !== undefined
                                && !!userLoader.item.facePath
                        source: "FaceAvatar.qml"
                        onLoaded: {
                            item.source = "file://" + userLoader.item.facePath;
                        }
                    }
                }
                    PC3.Label {
                        text: userLoader.item ? userLoader.item.displayName : ""
                    }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                QQC2.ToolButton {
                    icon.name: "folder-open"
                    QQC2.ToolTip.text: "Home folder"
                    QQC2.ToolTip.visible: hovered
                    onClicked: root.closeAndLaunch(() => root.launchDesktopFile("org.kde.dolphin.desktop"))
                }
                QQC2.ToolButton {
                    icon.name: "configure"
                    QQC2.ToolTip.text: "System Settings"
                    QQC2.ToolTip.visible: hovered
                    onClicked: root.closeAndLaunch(() => root.launchDesktopFile("systemsettings.desktop"))
                }
                QQC2.ToolButton {
                    id: powerButton
                    icon.name: "system-shutdown"
                    QQC2.ToolTip.text: "Power"
                    QQC2.ToolTip.visible: hovered
                    onClicked: {
                        const p = powerButton.mapToItem(menuRoot, 0, 0);
                        powerPopup.x = p.x + powerButton.width - powerPopup.width;
                        powerPopup.y = p.y - powerPopup.height - Kirigami.Units.smallSpacing;
                        powerPopup.open();
                    }
                }
            }
        }
    }
}
