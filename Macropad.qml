import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// Omarchy shell "menu" plugin: pick a macropad control, then press the
// real-keyboard shortcut you want assigned to it. The actual capture,
// key-name translation, and ch57x-keyboard-tool upload happen in the
// bundled omarchy-macropad-apply.py, spawned detached on selection — this
// component is just the picker.
Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property int selectedIndex: 0

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  readonly property string applyScript: pluginDir + "omarchy-macropad-apply.py"

  readonly property var slots: [
    { label: "Key 1", slot: "button1" },
    { label: "Key 2", slot: "button2" },
    { label: "Key 3", slot: "button3" },
    { label: "Knob ↺ turn left (CCW)", slot: "knob_ccw" },
    { label: "Knob press (click)", slot: "knob_press" },
    { label: "Knob ↻ turn right (CW)", slot: "knob_cw" }
  ]

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int rowHeight: Math.max(Style.space(40), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int cardWidth: Math.min(Style.space(360), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(rowHeight * slots.length + contentMargin * 2, panel.height - Style.gapsOut * 2)

  function open(payloadJson) {
    root.opened = true
    root.selectedIndex = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "eddari.macropad")
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  function activateIndex(index) {
    if (index < 0 || index >= root.slots.length) return
    var chosen = root.slots[index]
    root.dismiss()
    Quickshell.execDetached(["python3", root.applyScript, chosen.slot])
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "eddari-macropad"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Escape) {
            root.dismiss()
            event.accepted = true
          } else if (event.key === Qt.Key_Up) {
            root.selectedIndex = (root.selectedIndex - 1 + root.slots.length) % root.slots.length
            event.accepted = true
          } else if (event.key === Qt.Key_Down) {
            root.selectedIndex = (root.selectedIndex + 1) % root.slots.length
            event.accepted = true
          } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateIndex(root.selectedIndex)
            event.accepted = true
          }
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Repeater {
          model: root.slots.length

          Rectangle {
            required property int index
            readonly property bool hasCursor: index === root.selectedIndex

            width: parent.width
            height: root.rowHeight
            radius: root.cornerRadius
            color: hasCursor ? root.selectedBackground : "transparent"

            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.md
              text: root.slots[index].label
              color: hasCursor ? root.selectedText : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onContainsMouseChanged: if (containsMouse) root.selectedIndex = index
              onClicked: root.activateIndex(index)
            }
          }
        }
      }
    }
  }
}
