// UserInfo.qml
//
// Who is logged in, for the footer. Isolated behind a Loader in
// main.qml so a failure here only degrades the footer.
//
// v0.2.1: this no longer uses org.kde.kcoreaddons (KUser) -- that
// QML module is NOT INSTALLED on the AiO, which is why the footer
// was blank/"?" in every build through 0.2.0. The login name and
// full name now come from the executable data engine instead
// (id / getent), the same engine the footer shortcut buttons use.

import QtQuick
import org.kde.plasma.plasma5support 2.0 as Plasma5Support

Item {
    id: userInfo

    property string name: ""
    property string login: ""
    // Path to the account's face image ("" when none is set).
    property string facePath: ""
    // What the footer shows: full name when the system has one,
    // otherwise the login name.
    property string displayName: name !== "" ? name : login

    Plasma5Support.DataSource {
        id: ds
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            if (data["exit code"] !== undefined) {
                if (data["exit code"] === 0) {
                    const lines = String(data["stdout"] || "").split("\n");
                    if (lines.length > 0 && lines[0].trim() !== "") {
                        userInfo.login = lines[0].trim();
                    }
                    if (lines.length > 1) {
                        userInfo.name = lines[1].trim();
                    }
                    if (lines.length > 2) {
                        userInfo.facePath = lines[2].trim();
                    }
                }
                ds.disconnectSource(sourceName);
            }
        }
    }

    Component.onCompleted: {
        // Line 1: login name. Line 2: full name (may be empty).
        // Line 3: the account's face image path -- the first of the
        // standard locations that exists, empty when none is set.
        ds.connectSource("sh -c 'id -un; getent passwd $(id -u) | cut -d: -f5 | cut -d, -f1; ls ~/.face.icon ~/.face /var/lib/AccountsService/icons/$(id -un) 2>/dev/null | head -1'");
    }
}
