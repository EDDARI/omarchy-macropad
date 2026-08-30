import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// Omarchy shell "menu" plugin: pick a macropad control, press the real
// shortcut you want assigned to it (or browse LED modes with live preview),
// then confirm before anything is written to the device. Rows, header, and
// selection styling follow the same conventions as Omarchy's built-in menu
// (omarchy.menu's Menu.qml) — BorderSurface rows with a reserved left
// accent border, heading-weight label + dim caption detail line, theme
// tokens pulled from the same [menu] section — so this reads as a native
// part of the shell rather than a bolted-on popup. The actual capture,
// key-name translation, and ch57x-keyboard-tool calls happen in the
// bundled omarchy-macropad-apply.py — this component is just the UI.
Item {
  id: root

  // Injected by omarchy-shell when this plugin is summoned.
  property var shell: null
  property var manifest: null

  property bool opened: false
  property int selectedIndex: 0

  // "list" -> "capturing" -> "confirm" | "message" -> back to "list"
  // "list" -> "led" (browse a mode list, live preview on every move,
  //          Enter locks it in, Esc reverts to what it was) -> "list"
  property string pickerState: "list"
  property string capturedToken: ""
  property string messageText: ""
  property var currentValues: ({})
  property int ledCursor: 0
  property int ledOriginalMode: 0
  property bool ledPreviewed: false
  property bool ledApplying: false

  // Empirically-picked upper bound for the mode list — see LED_MODE_COUNT's
  // comment in omarchy-macropad-apply.py for why this isn't a confirmed
  // mode count.
  readonly property int ledModeCount: 16

  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")
  readonly property string applyScript: pluginDir + "omarchy-macropad-apply.py"

  readonly property var slots: [
    { label: "Key 1", slot: "button1", icon: "①" },
    { label: "Key 2", slot: "button2", icon: "②" },
    { label: "Key 3", slot: "button3", icon: "③" },
    { label: "Knob turn left (CCW)", slot: "knob_ccw", icon: "↺" },
    { label: "Knob press", slot: "knob_press", icon: "●" },
    { label: "Knob turn right (CW)", slot: "knob_cw", icon: "↻" },
    { label: "LED backlight", slot: "led", icon: "◉" }
  ]

  function rowDetail(index) {
    var s = root.slots[index]
    if (s.slot === "led") return "mode " + (root.currentValues.led_mode || 0)
    var value = root.currentValues[s.slot]
    return value || "not assigned"
  }

  function ledRowDetail(index) {
    return index === root.ledOriginalMode ? "current" : ""
  }

  function headerTitle() {
    if (root.pickerState === "led") return "LED backlight"
    if (root.pickerState === "capturing") return "Capture shortcut"
    if (root.pickerState === "confirm") return "Confirm"
    return "Macropad"
  }

  // --- Theme tokens, wired the same way as Omarchy's built-in menu so a
  // theme's [menu] section (colors, selected-border, corner radius, fonts,
  // spacing scale) applies here identically. ---
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  property color selectedBorder: Color.menu.selectedBorder
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", selectedBorder, 0)
  readonly property real rowReservedBorderLeft: Border.left(selectedBorderSpec)
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(34), Style.font.heading + Style.spacing.controlPaddingY * 2)
  property int rowSpacing: Style.spacing.xs
  property int rowHeight: Math.max(Style.space(56), Style.font.heading + Style.font.bodySmall + Style.space(4) + Style.spacing.rowPaddingX * 2)
  property int ledHintLineHeight: Style.font.bodySmall + Style.space(6)
  property int cardWidth: Math.min(Style.space(480), panel.width - Style.gapsOut * 2)

  property int listBodyHeight: slots.length * rowHeight + (slots.length - 1) * rowSpacing
  property int ledVisibleRows: Math.min(ledModeCount, 6)
  property int ledBodyHeight: ledHintLineHeight + Style.space(4)
    + ledVisibleRows * rowHeight + (ledVisibleRows - 1) * rowSpacing
  property int messageBodyHeight: Style.space(90)

  property int bodyHeight: {
    var raw = messageBodyHeight
    if (pickerState === "list") raw = listBodyHeight
    else if (pickerState === "led") raw = ledBodyHeight
    var maxRaw = panel.height - Style.gapsOut * 2 - contentMargin * 2 - headerHeight - contentSpacing
    return Math.max(rowHeight, Math.min(raw, maxRaw))
  }

  property int cardHeight: Math.min(contentMargin * 2 + headerHeight + contentSpacing + bodyHeight, panel.height - Style.gapsOut * 2)

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
      root.ledCursor = root.currentValues.led_mode || 0
      root.ledOriginalMode = root.ledCursor
      root.ledPreviewed = false
      root.pickerState = "led"
      return
    }
    root.pickerState = "capturing"
    captureProc.running = false
    captureProc.command = ["python3", root.applyScript, "capture", root.slots[index].slot]
    captureProc.running = true
  }

  // Moving through the list previews live: every cursor change sends that
  // mode straight to the device (debounced so holding an arrow key or
  // scrolling fast doesn't flood it with commands), so the user can see the
  // difference between modes before committing to one.
  function moveLedCursor(toIndex) {
    var next = ((toIndex % root.ledModeCount) + root.ledModeCount) % root.ledModeCount
    if (next === root.ledCursor) return
    root.ledCursor = next
    root.ledPreviewed = true
    ledPreviewTimer.restart()
  }

  function finalizeLedMode() {
    if (root.ledApplying) return
    root.ledApplying = true
    ledApplyProc.running = false
    ledApplyProc.command = ["python3", root.applyScript, "led", String(root.ledCursor)]
    ledApplyProc.running = true
  }

  function cancelLedPreview() {
    ledPreviewTimer.stop()
    if (root.ledPreviewed && root.ledCursor !== root.ledOriginalMode)
      Quickshell.execDetached(["python3", root.applyScript, "led", String(root.ledOriginalMode), "quiet"])
    root.backToList()
  }

  Timer {
    id: ledPreviewTimer
    interval: 120
    repeat: false
    onTriggered: Quickshell.execDetached(["python3", root.applyScript, "led", String(root.ledCursor), "quiet"])
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

  Process {
    id: ledApplyProc
    stdout: StdioCollector {
      onStreamFinished: {
        root.ledApplying = false
        root.backToList()
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
            if (event.key === Qt.Key_Escape) {
              root.cancelLedPreview()
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              root.moveLedCursor(root.ledCursor - 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              root.moveLedCursor(root.ledCursor + 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.finalizeLedMode()
              event.accepted = true
            }
          }
          // "capturing": keys are ignored here — the real capture happens at
          // the raw evdev level in the spawned process, independent of
          // Wayland focus, including Esc-to-cancel.
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        // --- Header: same treatment as Omarchy's built-in menu (a plain
        // heading-weight line naming the current context). ---
        Rectangle {
          width: parent.width
          height: root.headerHeight
          color: "transparent"

          Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.headerTitle()
            color: root.foreground
            opacity: 0.85
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            font.weight: Font.Medium
            elide: Text.ElideRight
          }
        }

        Item {
          width: parent.width
          height: root.bodyHeight

          // --- List state ---
          ListView {
            anchors.fill: parent
            visible: root.pickerState === "list"
            interactive: false
            clip: true
            spacing: root.rowSpacing
            model: root.slots.length
            currentIndex: root.selectedIndex
            highlightFollowsCurrentItem: true

            delegate: BorderSurface {
              id: slotRow
              required property int index
              readonly property bool hasCursor: index === root.selectedIndex
              readonly property var slotData: root.slots[index]

              width: ListView.view.width
              height: root.rowHeight
              radius: root.cornerRadius
              color: hasCursor ? root.selectedBackground : "transparent"
              borderSpec: hasCursor ? root.selectedBorderSpec : Border.none()

              Text {
                id: slotIcon
                text: slotRow.slotData.icon
                color: slotRow.hasCursor ? root.selectedText : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.iconLarge
                width: Style.space(28)
                horizontalAlignment: Text.AlignHCenter
                anchors.left: parent.left
                anchors.leftMargin: root.rowReservedBorderLeft + Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
              }

              Column {
                anchors.left: slotIcon.right
                anchors.leftMargin: Style.space(8)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: slotRow.slotData.label
                  color: slotRow.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.heading
                  font.weight: Font.Medium
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: root.rowDetail(slotRow.index)
                  color: slotRow.hasCursor ? root.selectedText : root.foreground
                  opacity: 0.55
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) root.selectedIndex = slotRow.index
                onClicked: root.activateIndex(slotRow.index)
              }
            }
          }

          // --- LED mode list state ---
          Column {
            anchors.fill: parent
            visible: root.pickerState === "led"
            spacing: Style.space(4)

            Text {
              id: ledHint
              width: parent.width
              height: root.ledHintLineHeight
              verticalAlignment: Text.AlignVCenter
              text: "↑/↓ or scroll to preview  ·  Enter to pick  ·  Esc to cancel"
              color: root.foreground
              opacity: 0.55
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }

            ListView {
              id: ledListView
              width: parent.width
              height: parent.height - ledHint.height - parent.spacing
              clip: true
              spacing: root.rowSpacing
              model: root.ledModeCount
              currentIndex: root.ledCursor
              highlightFollowsCurrentItem: true

              // Scrolling over the list previews modes live, same as ↑/↓.
              WheelHandler {
                onWheel: function(event) {
                  if (event.angleDelta.y === 0) return
                  root.moveLedCursor(root.ledCursor + (event.angleDelta.y > 0 ? -1 : 1))
                }
              }

              delegate: BorderSurface {
                id: ledDelegate
                required property int index
                readonly property bool hasCursor: index === root.ledCursor

                width: ListView.view.width
                height: root.rowHeight
                radius: root.cornerRadius
                color: hasCursor ? root.selectedBackground : "transparent"
                borderSpec: hasCursor ? root.selectedBorderSpec : Border.none()

                Text {
                  id: ledIcon
                  text: "◉"
                  color: ledDelegate.hasCursor ? root.selectedText : root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.iconLarge
                  width: Style.space(28)
                  horizontalAlignment: Text.AlignHCenter
                  anchors.left: parent.left
                  anchors.leftMargin: root.rowReservedBorderLeft + Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                  anchors.left: ledIcon.right
                  anchors.leftMargin: Style.space(8)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: "Mode " + ledDelegate.index
                    color: ledDelegate.hasCursor ? root.selectedText : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: root.ledRowDetail(ledDelegate.index)
                    visible: text.length > 0
                    color: ledDelegate.hasCursor ? root.selectedText : root.foreground
                    opacity: 0.55
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onContainsMouseChanged: if (containsMouse) root.moveLedCursor(ledDelegate.index)
                  onClicked: root.finalizeLedMode()
                }
              }
            }
          }

          // --- Capturing / confirm / message states ---
          Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: Style.spacing.md
            visible: root.pickerState === "capturing" || root.pickerState === "confirm" || root.pickerState === "message"

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
                return "Enter or Esc to go back"
              }
            }
          }
        }
      }
    }
  }
}
