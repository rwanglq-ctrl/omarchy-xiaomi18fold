import QtQuick
import Quickshell
import qs.Commons as OmarchyColors
ShellRoot {
  Timer {
    interval: 1000
    running: true
    onTriggered: {
      const c = OmarchyColors.Color
      if (c.bar.text && c.menu.background && c.notifications.border &&
          OmarchyColors.Border.value("missing-section", "missing-key") === "" &&
          OmarchyColors.Style.resolveStateColor("foreground", "", "", "", "") === c.foreground)
        console.log("PASS shell color roles and Style resolution")
      else
        console.log("FAIL shell color roles")
      Qt.quit()
    }
  }
}
