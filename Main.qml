import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import flatPdfQt2

ApplicationWindow {
    id: root
    width: 760
    height: 500
    visible: true
    title: qsTr("flatPDF")

    property string inputPath: ""
    property string outputPath: ""
    property bool outputManuallySet: false
    property bool processing: false
    property string conversionPreset: "Standard"
    property string estimateText: ""
    readonly property var pdfFlattener: PdfFlattener
    readonly property var presetDefs: ({
        "Senza Perdite": { dpi: 300, quality: 100, imageFormat: "png" },
        "Massima": { dpi: 300, quality: 95, imageFormat: "jpg" },
        "Standard": { dpi: 150, quality: 85, imageFormat: "jpg" },
        "Bassa": { dpi: 100, quality: 60, imageFormat: "jpg" }
    })

    function urlToLocal(u) {
        const s = String(u)
        if (s.startsWith("file:")) {
            try {
                return decodeURIComponent(s.replace(/^file:\/\//, ""))
            } catch(e) {
                return s
            }
        }
        return s
    }
    function defaultOutFor(u) {
        const p = urlToLocal(u)
        const lower = p.toLowerCase()
        const idx = lower.lastIndexOf('.pdf')
        const base = idx >= 0 ? p.slice(0, idx) : p
        return base + "-flat.pdf"
    }
    function applyPreset(name) {
        const cfg = presetDefs[name] || presetDefs["Standard"]
        conversionPreset = name
        resetEstimate()
        dpiBox.editText = String(cfg.dpi)
        dpiBox.lastValid = String(cfg.dpi)
        qualityBox.editText = String(cfg.quality)
        qualityBox.lastValid = String(cfg.quality)
        formatBox.currentIndex = cfg.imageFormat === "png" ? 0 : 1
        pdfFlattener.dpi = cfg.dpi
        pdfFlattener.quality = cfg.quality
        pdfFlattener.imageFormat = cfg.imageFormat
    }
    function currentDpi() {
        return parseInt(dpiBox.editText.length > 0 ? dpiBox.editText : dpiBox.lastValid, 10)
    }
    function currentQuality() {
        return parseInt(qualityBox.editText.length > 0 ? qualityBox.editText : qualityBox.lastValid, 10)
    }
    function currentFormat() {
        return formatBox.currentIndex === 0 ? "png" : "jpg"
    }
    function resetEstimate() {
        estimateText = ""
    }
    function calculateEstimate() {
        const result = pdfFlattener.estimateWithOptions(root.inputPath,
                                                        root.currentDpi(),
                                                        root.currentQuality(),
                                                        root.currentFormat())
        if (result.success) {
            estimateText = "Circa " + result.estimatedMiB + " MiB"
        } else {
            statusDialog.title = "Errore"
            statusDialog.text = result.error
            statusDialog.informativeText = ""
            statusDialog.open()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        GroupBox {
            title: "Impostazioni"
            Layout.fillWidth: true

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 0
                anchors.leftMargin: 8
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        text: "Modalità"
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ComboBox {
                        id: presetBox
                        model: ["Senza Perdite", "Massima", "Standard", "Bassa"]
                        currentIndex: 2
                        Component.onCompleted: root.applyPreset(currentText)
                        onActivated: root.applyPreset(currentText)
                        Layout.preferredWidth: 170
                    }

                    Label {
                        text: "Formato"
                        Layout.alignment: Qt.AlignVCenter
                    }
                    ComboBox {
                        id: formatBox
                        model: ["PNG", "JPG"]
                        onActivated: {
                            pdfFlattener.imageFormat = root.currentFormat()
                            root.resetEstimate()
                        }
                        Layout.preferredWidth: 100
                    }

                    Item { Layout.fillWidth: true }
                }

                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        text: "DPI"
                        Layout.alignment: Qt.AlignVCenter
                    }

                    ComboBox {
                        id: dpiBox
                        editable: true
                        model: ["72", "100", "150", "300", "600"]
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator { bottom: 50; top: 1200 }
                        property string lastValid: "150"

                        onActivated: {
                            lastValid = currentText
                            pdfFlattener.dpi = parseInt(currentText, 10)
                            root.resetEstimate()
                        }

                        onAccepted: {
                            if (acceptableInput) {
                                lastValid = editText
                                pdfFlattener.dpi = parseInt(editText, 10)
                                root.resetEstimate()
                            } else {
                                editText = lastValid
                            }
                        }

                        onEditTextChanged: {
                            if (!acceptableInput && editText.length > 0)
                                pdfFlattener.dpi = parseInt(lastValid, 10)
                        }

                        onFocusChanged: if (!focus && !acceptableInput) editText = lastValid
                    }

                    Label {
                        text: "Qualità"
                        Layout.alignment: Qt.AlignVCenter
                    }
                    ComboBox {
                        id: qualityBox
                        editable: true
                        model: ["60","85","90","95","100"]
                        inputMethodHints: Qt.ImhDigitsOnly
                        validator: IntValidator { bottom: 10; top: 100 }
                        property string lastValid: "85"

                        onActivated: {
                            lastValid = currentText
                            pdfFlattener.quality = parseInt(currentText, 10)
                            root.resetEstimate()
                        }

                        onAccepted: {
                            if (acceptableInput) {
                                lastValid = editText
                                pdfFlattener.quality = parseInt(editText, 10)
                                root.resetEstimate()
                            } else {
                                editText = lastValid
                            }
                        }

                        onEditTextChanged: {
                            if (!acceptableInput && editText.length > 0)
                                pdfFlattener.quality = parseInt(lastValid, 10)
                        }

                        onFocusChanged: if (!focus && !acceptableInput) editText = lastValid
                        Layout.alignment: Qt.AlignVCenter
                    }

                    Rectangle {
                        id: estimateControl
                        Layout.preferredWidth: 260
                        Layout.preferredHeight: 44
                        Layout.alignment: Qt.AlignVCenter
                        radius: 10
                        color: "#050505"
                        border.width: 1
                        border.color: estimateMouse.containsMouse ? "#6e6e73" : "#3a3a3c"
                        opacity: root.inputPath.length > 0 && !root.processing ? 1.0 : 0.55

                        Text {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            verticalAlignment: Text.AlignVCenter
                            text: root.estimateText.length > 0 ? root.estimateText : "Fai clic per calcolare"
                            color: root.estimateText.length > 0 ? "#f5f5f7" : "#d2d2d7"
                            font.pixelSize: 15
                            font.weight: root.estimateText.length > 0 ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }

                        MouseArea {
                            id: estimateMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            enabled: root.inputPath.length > 0 && !root.processing && root.estimateText.length === 0
                            onClicked: root.calculateEstimate()
                        }
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }

        GroupBox {
            title: "File"
            Layout.fillWidth: true

            ColumnLayout {
                anchors.fill: parent
                 anchors.margins: 0
                anchors.leftMargin: 8
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    TextField {
                        id: inputField
                        Layout.fillWidth: true
                        placeholderText: "Seleziona PDF di input…"
                        text: root.inputPath
                        readOnly: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Button {
                        text: "Scegli…"
                        onClicked: openDialog.open()
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    TextField {
                        id: outputField
                        Layout.fillWidth: true
                        placeholderText: "Seleziona destinazione…"
                        text: root.outputPath
                        readOnly: true
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Button {
                        text: "Scegli…"
                        onClicked: saveDialog.open()
                        Layout.alignment: Qt.AlignVCenter
                    }
                }
            }
        }


        Rectangle {
            id: dropZone
            Layout.fillWidth: true
            Layout.preferredHeight: 140
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.topMargin: 4
            Layout.bottomMargin: 0
            radius: 12
            color: Qt.rgba(0.12, 0.12, 0.12, 0.9)
            border.width: dropArea.validDrag ? 3 : 1
            border.color: dropArea.validDrag ? "#4CAF50" : "#555555"
            Behavior on border.color { ColorAnimation { duration: 120 } }
            Behavior on border.width { NumberAnimation { duration: 120 } }

            Column {
                anchors.centerIn: parent
                spacing: 6
                Text {
                    text: qsTr("Trascina qui il PDF da convertire")
                    color: "#f0f0f0"
                    font.pixelSize: 16
                }
                Text {
                    text: qsTr("Oppure usa i pulsanti Seleziona")
                    color: "#bbbbbb"
                    font.pixelSize: 12
                }
            }

            DropArea {
                id: dropArea
                anchors.fill: parent
                property bool validDrag: false

                onEntered: function(drag) {
                    const hasPdf = drag.hasUrls && drag.urls.some(function(url) {
                        return url.toString().toLowerCase().endsWith(".pdf");
                    });
                    validDrag = hasPdf;
                    drag.accepted = hasPdf;
                }

                onExited: validDrag = false

                onDropped: function(drop) {
                    validDrag = false;
                    if (!drop.hasUrls || drop.urls.length === 0)
                        return;

                    const urlStr = drop.urls[0].toString();
                    if (!urlStr.toLowerCase().endsWith(".pdf")) {
                        statusDialog.title = "Errore"
                        statusDialog.text = qsTr("Trascina solo file PDF.")
                        statusDialog.informativeText = ""
                        statusDialog.open()
                        return;
                    }

                    root.inputPath = urlStr;
                    root.resetEstimate()
                    inputField.text = root.inputPath;
                    if (!root.outputManuallySet) {
                        root.outputPath = root.defaultOutFor(urlStr);
                        outputField.text = root.outputPath;
                    }

                    drop.acceptProposedAction();
                }
            }
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            Layout.bottomMargin: 0

            Button {
                id: convertButton
                text: "Converti"
                highlighted: true
                enabled: !root.processing && root.inputPath.length > 0 && root.outputPath.length > 0
                onClicked: {
                    pdfFlattener.flattenWithOptions(root.inputPath, root.outputPath,
                                                    root.currentDpi(), root.currentQuality(),
                                                    root.currentFormat(), true)
                }
                Layout.alignment: Qt.AlignVCenter
            }

            BusyIndicator {
                id: busyIndicator
                running: false
                Layout.alignment: Qt.AlignVCenter
            }
        }
    }

    Connections {
        target: pdfFlattener
        function onProcessingStarted() {
            root.processing = true
            busyIndicator.running = true
        }
        function onProcessingFinished() {
            root.processing = false
            busyIndicator.running = false
        }
        function onFinished(success, outputPath, error) {
            if (success) {
                statusDialog.title = "Successo"
                statusDialog.text = "Conversione completata."
                statusDialog.informativeText = outputPath
                statusDialog.open()
            } else {
                statusDialog.title = "Errore"
                statusDialog.text = error
                statusDialog.informativeText = ""
                statusDialog.open()
            }
        }
    }

    FileDialog {
        id: openDialog
        title: "Seleziona PDF"
        fileMode: FileDialog.OpenFile
        nameFilters: ["PDF files (*.pdf)"]
        onAccepted: {
            const u = openDialog.selectedFile
            root.inputPath = u
            root.resetEstimate()
            inputField.text = root.inputPath
            if (!root.outputManuallySet) {
                root.outputPath = root.defaultOutFor(u)
                outputField.text = root.outputPath
            }
        }
    }
    FileDialog {
        id: saveDialog
        title: "Salva come"
        fileMode: FileDialog.SaveFile
        nameFilters: ["PDF files (*.pdf)"]
        onAccepted: {
            const p = saveDialog.selectedFile
            root.outputPath = p
            root.resetEstimate()
            outputField.text = root.outputPath
            root.outputManuallySet = true
        }
    }

    MessageDialog {
        id: statusDialog
        buttons: MessageDialog.Ok
    }
}
