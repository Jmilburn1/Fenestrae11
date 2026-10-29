// CategoryCard.qml -- a category as a card with a 2x2 collage of the
// category's first four app icons. Every collage icon is drawn at
// card.iconSize -- the same size, in every card. (The icon law again.)

import QtQuick
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3

Item {
    id: card

    property string title: ""
    // Icon-name strings for the collage (the category's first four
    // members under Fenestrae's effective membership, v0.3.0).
    property var collageIcons: []
    property int iconSize: 36
    signal activated()

    implicitHeight: cardRect.height + label.height + Kirigami.Units.smallSpacing * 2

    Rectangle {
        id: cardRect
        width: parent.width
        height: Kirigami.Units.gridUnit * 6
        radius: Kirigami.Units.smallSpacing * 1.5
        color: Kirigami.Theme.alternateBackgroundColor
        // NOT Kirigami.Theme.separatorColor: it is undefined under
        // the Win11OS-dark theme and spammed a QColor error per card.
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.25)
        border.width: 1
        opacity: mouse.containsMouse ? 0.85 : 1.0

        GridView {
            anchors.centerIn: parent
            width: cellWidth * 2
            height: cellHeight * 2
            cellWidth: card.iconSize + Kirigami.Units.smallSpacing * 2
            cellHeight: card.iconSize + Kirigami.Units.smallSpacing * 2
            interactive: false
            clip: true
            model: card.collageIcons
            delegate: Item {
                width: GridView.view.cellWidth
                height: GridView.view.cellHeight
                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: card.iconSize
                    height: card.iconSize
                    source: modelData
                    fallback: "application-x-executable"
                }
            }
        }
    }

    PC3.Label {
        id: label
        anchors.top: cardRect.bottom
        anchors.topMargin: Kirigami.Units.smallSpacing
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: card.title
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: card.activated()
    }
}
