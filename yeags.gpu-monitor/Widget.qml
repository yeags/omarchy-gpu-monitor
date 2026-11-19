import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
    id: root
    moduleName: "yeags.gpu-monitor"
    manageIpc: false
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    property var devices: []
    property string selectedId: ""
    property var histories: ({})
    property string statusKey: "loading"
    property bool received: false
    readonly property int sampleSeconds: Math.max(1, Math.min(60, Number(setting("interval", 2)) || 2))
    readonly property var device: devices.find(function(d) { return d.id === selectedId }) || devices[0] || null
    readonly property var history: device ? (histories[device.id] || []) : []
    readonly property color foreground: bar ? bar.barForeground : Commons.Color.foreground
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("metrics.py").toString().replace(/^file:\/\//, ""))

    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    function metric(value, suffix, decimals) {
        return typeof value === "number" && isFinite(value) ? Commons.I18n.formatNumber(value, decimals || 0) + suffix : "—"
    }
    function refresh() {
        if (!worker.running) {
            received = false
            worker.running = true
        }
    }
    function fail() {
        devices = []
        histories = ({})
        statusKey = "failed"
    }
    Component.onCompleted: refresh()
    Timer { interval: root.sampleSeconds * 1000; running: true; repeat: true; onTriggered: root.refresh() }

    Process {
        id: worker
        command: ["python3", root.helper]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.received = true
                try {
                    if (text.length > 65536) throw new Error("Oversized snapshot")
                    var result = JSON.parse(text)
                    if (!Array.isArray(result.devices) || result.devices.length > 16) throw new Error("Invalid snapshot")
                    var next = {}
                    result.devices.forEach(function(d) {
                        var samples = (root.histories[d.id] || []).slice(-59)
                        samples.push(typeof d.utilization === "number" ? Math.max(0, Math.min(100, d.utilization)) : null)
                        next[d.id] = samples
                    })
                    root.histories = next
                    root.devices = result.devices
                    root.statusKey = result.devices.length ? "" : "empty"
                } catch (error) { root.fail() }
            }
        }
        onExited: function(code) { if (code !== 0 || !root.received) root.fail() }
    }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "GPU " + root.metric(root.device ? root.device.utilization : null, "%")
        // Static tooltip: sensor/device text never enters the shell's rich-text sink.
        tooltipText: strings.t("title")
        onPressed: function(mouseButton) { if (mouseButton === Qt.LeftButton) root.toggle() }
    }

    component Label: Text {
        textFormat: Text.PlainText
        color: root.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
    }

    KeyboardPanel {
        anchorItem: button
        owner: root
        bar: root.bar
        open: root.opened
        contentWidth: Style.space(420)
        contentHeight: fittedContentHeight(content.implicitHeight)
        focusTarget: content

        Flickable {
            anchors.fill: parent
            contentHeight: content.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ColumnLayout {
                id: content
                width: parent.width
                spacing: Style.space(12)
                focus: true
                Keys.onEscapePressed: root.close()

                Label { text: strings.t("title"); font.bold: true; font.pixelSize: Style.font.body * 1.35 }
                RowLayout {
                    Layout.fillWidth: true
                    Repeater {
                        model: root.devices
                        delegate: Controls.Button {
                            required property var modelData
                            text: modelData.vendor
                            checkable: true
                            checked: root.device && root.device.id === modelData.id
                            onClicked: root.selectedId = modelData.id
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Controls.Button { text: strings.t("refresh"); enabled: !worker.running; onClicked: root.refresh() }
                }
                Label {
                    Layout.fillWidth: true
                    visible: !!root.device
                    text: root.device ? root.device.name : ""
                    wrapMode: Text.WrapAnywhere
                    font.bold: true
                }
                Label {
                    Layout.fillWidth: true
                    visible: root.statusKey !== "" || (!!root.device && root.device.status !== "ok")
                    text: strings.t(root.statusKey || (root.device ? root.device.status : "empty"))
                    wrapMode: Text.WordWrap
                    opacity: 0.75
                }
                Repeater {
                    model: [
                        {label: strings.t("utilization"), value: root.metric(root.device ? root.device.utilization : null, "%")},
                        {label: strings.t("memory"), value: root.metric(root.device ? root.device.memoryUsed : null, " MiB") + " / " + root.metric(root.device ? root.device.memoryTotal : null, " MiB")},
                        {label: strings.t("temperature"), value: root.metric(root.device ? root.device.temperature : null, " °C")},
                        {label: strings.t("power"), value: root.metric(root.device ? root.device.power : null, " W", 1) + " / " + root.metric(root.device ? root.device.powerLimit : null, " W")},
                        {label: strings.t("clocks"), value: root.metric(root.device ? root.device.coreClock : null, " MHz") + " / " + root.metric(root.device ? root.device.memoryClock : null, " MHz")},
                        {label: strings.t("fan"), value: root.metric(root.device ? root.device.fan : null, "%")}
                    ]
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Label { text: modelData.label; opacity: 0.7; Layout.fillWidth: true }
                        Label { text: modelData.value }
                    }
                }
                Label { text: strings.t("history").arg(Commons.I18n.formatNumber(60)); opacity: 0.7 }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: Style.space(70)
                    color: Qt.alpha(root.foreground, 0.05)
                    Row {
                        anchors.fill: parent
                        spacing: 1
                        Repeater {
                            model: 60
                            delegate: Rectangle {
                                required property int index
                                readonly property var sample: root.history[index - (60 - root.history.length)]
                                width: Math.max(0, (parent.width - 59) / 60)
                                height: typeof sample === "number" ? Math.max(1, parent.height * sample / 100) : 0
                                y: parent.height - height
                                color: root.foreground
                                opacity: 0.75
                            }
                        }
                    }
                }
                Label {
                    text: strings.t("sampling").arg(Commons.I18n.formatNumber(root.sampleSeconds))
                    opacity: 0.6
                    font.pixelSize: Style.font.body * 0.85
                }
            }
        }
    }
}
