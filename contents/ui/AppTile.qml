// AppTile.qml -- one app in a grid.
// THE ICON LAW: the icon is drawn at tile.iconSize, and every tile on a
// surface uses the same iconSize. No per-app exceptions, ever.
//
// Pinning: when the view sets sourceModel + rowIndex, the tile knows
// its desktop-file ID and right-click offers Pin/Unpin from Start
// (Fenestrae's own pin list, kept by the bridge).

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Item {
    id: tile

    property int iconSize: 48
    // Set by the view: the delegate's model object.
    property var modelData
    // Set by the view when pin toggling should be offered: the QML
    // model object behind the view, and this delegate's row in it.
    property var sourceModel: null
    property int rowIndex: -1
    property bool isPinned: false
    // Pinned-surface mode (v0.3.1): identity/visuals supplied
    // directly (the pin list is Fenestrae's own array, not a Kicker
    // model), and the right-click menu gains Move earlier/later.
    property string forcedDesktopId: ""
    property string iconOverride: ""
    property string nameOverride: ""
    property bool canMove: false

    signal activated(string desktopId)
    signal pinToggleRequested(string desktopId)
    signal moveRequested(string desktopId, int delta)

    // Desktop-file ID (Kicker role 259 -- script data() reads of this
    // role are proven safe on the AiO; only the item object is not).
    readonly property string desktopId: {
        if (forcedDesktopId !== "") {
            return forcedDesktopId;
        }
        if (!sourceModel || rowIndex < 0) {
            return "";
        }
        try {
            return String(sourceModel.data(sourceModel.index(rowIndex, 0), 259) || "");
        } catch (e) {
            return "";
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Kirigami.Units.smallSpacing
        color: Kirigami.Theme.highlightColor
        opacity: mouse.containsMouse ? 0.22 : 0.0
        Behavior on opacity {
            NumberAnimation {
                duration: 90
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: parent.width - Kirigami.Units.smallSpacing * 2
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Icon {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: tile.iconSize
            implicitHeight: tile.iconSize
            source: tile.iconOverride !== "" ? tile.iconOverride : (tile.modelData ? tile.modelData.decoration : "")
            fallback: "application-x-executable"
        }

        PC3.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            maximumLineCount: 1
            font: Kirigami.Theme.smallFont
            text: tile.nameOverride !== "" ? tile.nameOverride : (tile.modelData ? tile.modelData.display : "")
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (event) => {
            if (event.button === Qt.RightButton && tile.desktopId !== "") {
                pinMenu.open();
            } else if (event.button === Qt.LeftButton) {
                tile.activated(tile.desktopId);
            }
        }
    }

    QQC2.Menu {
        id: pinMenu
        QQC2.MenuItem {
            text: tile.isPinned ? "Unpin from Start" : "Pin to Start"
            onTriggered: tile.pinToggleRequested(tile.desktopId)
        }
        QQC2.MenuItem {
            visible: tile.canMove
            text: "Move earlier"
            onTriggered: tile.moveRequested(tile.desktopId, -1)
        }
        QQC2.MenuItem {
            visible: tile.canMove
            text: "Move later"
            onTriggered: tile.moveRequested(tile.desktopId, 1)
        }
    }
}
