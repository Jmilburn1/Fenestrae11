// FaceAvatar.qml
//
// The account's face image, cropped to a circle. Loaded through a
// Loader in main.qml: it uses QtQuick.Effects for the circular
// mask, and if that module is ever unavailable the Loader simply
// fails and the footer keeps the initials circle instead of
// breaking the whole widget.

import QtQuick
import QtQuick.Effects

Item {
    id: faceRoot
    property url source: ""

    Image {
        id: img
        anchors.fill: parent
        source: faceRoot.source
        fillMode: Image.PreserveAspectCrop
        smooth: true
        visible: false
    }

    Rectangle {
        id: maskRect
        width: faceRoot.width
        height: faceRoot.height
        radius: width / 2
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: img
        maskEnabled: true
        maskSource: maskRect
        maskThresholdMin: 0.5
        maskSpreadAtMin: 0.0
    }
}
