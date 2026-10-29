// Exec.qml
//
// Tiny command runner (Plasma's "executable" data engine), used ONLY
// by the footer shortcuts (Home folder / System Settings), which need
// to start an app when no view delegate is involved. Isolated behind
// a Loader in main.qml: if the plasma5support module is ever missing,
// only those two buttons degrade -- the menu itself keeps working.

import QtQuick
import org.kde.plasma.plasma5support 2.0 as Plasma5Support

Item {
    function run(command) {
        executable.connectSource(command);
    }

    Plasma5Support.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => executable.disconnectSource(sourceName)
    }
}
