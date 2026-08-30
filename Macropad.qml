import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// Omarchy shell "menu" plugin: pick a macropad control, press the real
// shortcut you want assigned to it, then confirm before it's written to the
// device. The actual capture, key-name translation, and
// ch57x-keyboard-tool upload happen in the bundled
// omarchy-macropad-apply.py — this component is the picker + confirm UI.
Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property int selectedIndex: 0

  // "list" -> "capturing" -> "confirm" | "message" -> back to "list"
  // "list" -> "led" (live-cycles the backlight, applies as you go) -> "list"
  property string pickerState: "list"
  property string capturedToken: ""
  property string messageText: ""
  property var currentValues: ({})
  property int ledMode: 0

  // Empirically-picked wraparound range for the Next/Previous cycle — see
  // LED_MODE_COUNT's comment in omarchy-macropad-apply.py for why this isn't
  // a confirmed mode count.
  readonly property int ledModeCount: 16

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  readonly property string applyScript: pluginDir + "omarchy-macropad-apply.py"

  readonly property var slots: [
    { label: "Key 1", slot: "button1" },
    { label: "Key 2", slot: "button2" },
    { label: "Key 3", slot: "button3" },
    { label: "Knob ↺ turn left (CCW)", slot: "knob_ccw" },
    { label: "Knob press (click)", slot: "knob_press" },
    { label: "Knob ↻ turn right (CW)", slot: "knob_cw" },
    { label: "LED backlight", slot: "led" }
  ]

  function rowLabel(index) {
    var s = root.slots[index]
    if (s.slot === "led")
      return s.label + "  →  mode " + (root.currentValues.led_mode || 0)
    var value = root.currentValues[s.slot]
    return value ? s.label + "  →  " + value : s.label
  }

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
  property int cardWidth: Math.min(Style.space(480), panel.width - Style.gapsOut * 2)
  property int listCardHeight: Math.min(rowHeight * slots.length + contentMargin * 2, panel.height - Style.gapsOut * 2)
  property int messageCardHeight: Math.min(Style.space(160), panel.height - Style.gapsOut * 2)
  property int cardHeight: pickerState === "list" ? listCardHeight : messageCardHeight

  function refreshCurrentValues() {
    currentProc.running = false
    currentProc.command = ["python3", root.applyScript, "current"]
    currentProc.running = true
  }

  function open(payloadJson) {
    root.opened = true
    root.selectedIndex = 0
    root.pickerState = "list"
    root.capturedToken = ""
    root.messageText = ""
    root.refreshCurrentValues()
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

  function backToList() {
    root.pickerState = "list"
    root.capturedToken = ""
    root.messageText = ""
    root.refreshCurrentValues()
  }

  function activateIndex(index) {
    if (index < 0 || index >= root.slots.length) return
    root.selectedIndex = index
    if (root.slots[index].slot === "led") {
      root.ledMode = root.currentValues.led_mode || 0
      root.pickerState = "led"
      return
    }
    root.pickerState = "capturing"
    captureProc.running = false
    captureProc.command = ["python3", root.applyScript, "capture", root.slots[index].slot]
    captureProc.running = true
  }

  function stepLed(delta) {
    root.ledMode = (root.ledMode + delta + root.ledModeCount) % root.ledModeCount
    Quickshell.execDetached(["python3", root.applyScript, "led", String(root.ledMode)])
  }

  function handleCaptureResult(rawText) {
    var data = ({})
    try { data = JSON.parse(rawText || "{}") } catch (e) { data = ({}) }

    if (data.status === "ok" && data.token) {
      root.capturedToken = data.token
      root.pickerState = "confirm"
    } else if (data.status === "cancelled") {
      root.backToList()
    } else {
      root.messageText = "Not captured: " + (data.message || "unknown error")
      root.pickerState = "message"
    }
  }

  function confirmApply() {
    var s = root.slots[root.selectedIndex]
    Quickshell.execDetached(["python3", root.applyScript, "apply", s.slot, root.capturedToken])
    root.dismiss()
  }

  Process {
    id: captureProc
    stdout: StdioCollector {
      onStreamFinished: root.handleCaptureResult(text)
    }
  }

  Process {
    id: currentProc
    stdout: StdioCollector {
      onStreamFinished: {
        try { root.currentValues = JSON.parse(text || "{}") } catch (e) { root.currentValues = ({}) }
      }
    }
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
      onClicked: if (root.pickerState === "list") root.dismiss()
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
          if (root.pickerState === "list") {
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
          } else if (root.pickerState === "confirm") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.confirmApply()
              event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
              root.backToList()
              event.accepted = true
            }
          } else if (root.pickerState === "message") {
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Escape) {
              root.backToList()
              event.accepted = true
            }
          } else if (root.pickerState === "led") {
            if (event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
              root.stepLed(1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up || event.key === Qt.Key_Left) {
              root.stepLed(-1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Escape) {
              root.backToList()
              event.accepted = true
            }
          }
          // "capturing": keys are ignored here — the real capture happens at
          // the raw evdev level in the spawned process, independent of
          // Wayland focus, including Esc-to-cancel.
        }
      }

      // --- List state ---
      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        visible: root.pickerState === "list"

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
              text: root.rowLabel(index)
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

      // --- Capturing / confirm / message states ---
      Column {
        anchors.centerIn: parent
        width: parent.width
        spacing: Style.spacing.md
        visible: root.pickerState !== "list"

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.title
          text: {
            if (root.pickerState === "capturing")
              return "Press the shortcut for " + root.slots[root.selectedIndex].label + " now…"
            if (root.pickerState === "confirm")
              return root.slots[root.selectedIndex].label + "  →  " + root.capturedToken
            if (root.pickerState === "led")
              return "LED backlight — mode " + root.ledMode
            return root.messageText
          }
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          color: root.foreground
          opacity: 0.65
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          text: {
            if (root.pickerState === "capturing") return "Esc alone to cancel"
            if (root.pickerState === "confirm") return "Enter to confirm · Esc to cancel"
            if (root.pickerState === "led") return "↑/↓ to cycle, applied live · Enter or Esc when done"
            return "Enter or Esc to go back"
          }
        }
      }
    }
  }
}
