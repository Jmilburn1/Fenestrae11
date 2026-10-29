import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.configuration

Kirigami.FormLayout {
    property alias cfg_showRecommended: showRecommended.checked
    property alias cfg_categoryOverrides: overridesField.text

    QQC2.CheckBox {
        id: showRecommended
        Kirigami.FormData.label: "Sections:"
        text: "Show Recommended section"
    }

    QQC2.Label {
        text: "Off by default, and stays off unless you turn it on here."
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        Layout.fillWidth: true
        wrapMode: Text.Wrap
    }

    QQC2.TextArea {
        id: overridesField
        Kirigami.FormData.label: "Category overrides (JSON):"
        Layout.fillWidth: true
        Layout.minimumHeight: Kirigami.Units.gridUnit * 6
        wrapMode: TextEdit.Wrap
        placeholderText: "{ \"org.kde.kate\": \"Developer Tools\" }"
    }

    QQC2.Label {
        text: "Map a desktop-file ID to a category name. Your override wins over the categories the app claims for itself. Leave as {} for none."
        font: Kirigami.Theme.smallFont
        opacity: 0.7
        Layout.fillWidth: true
        wrapMode: Text.Wrap
    }
}
