import QtQuick
import qs.Ui

// Bar icon that toggles the macropad remap menu — an alternative to the
// SUPER+M keybinding for anyone who'd rather click it.
BarWidget {
  id: root
  moduleName: "eddari.macropad"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "⌨"
    horizontalMargin: 7.5
    onPressed: function(button) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle eddari.macropad")
    }
  }
}
