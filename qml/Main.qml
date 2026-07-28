import QtCore
import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Kadr

Window {
    id: win
    width: 1280
    height: 720
    visible: true
    color: "black"
    title: mpv.mediaTitle !== "" ? mpv.mediaTitle + "  ·  kadr" : "kadr"

    readonly property color primary: Theme.color("primary", "#c64671")
    readonly property color primarySoft: Theme.color("inverse_primary", "#ffb1c4")
    readonly property string uiFont: "SF Pro Rounded"

    property bool controlsShown: true
    property bool settingsOpen: false
    property bool previewForced: false   // KADR_SHOT verification only
    property int skipInterval: 10
    property string glassTheme: "liquid"

    // Subtitle style menu: one entry per option page. `values` are what mpv
    // receives; background color/opacity combine into sub-back-color.
    readonly property var subOptionDefs: [
        { key: "subFont", title: "Font family",
          options: ["SF Pro Rounded", "SF Pro Display", "SF Pro Text", "SF Mono", "Sans Serif"],
          values: ["SF Pro Rounded", "SF Pro Display", "SF Pro Text", "SF Mono", "sans-serif"] },
        { key: "subSize", title: "Font size",
          options: ["50%", "75%", "100%", "150%", "200%"],
          values: [22, 33, 44, 66, 88] },
        { key: "subColor", title: "Font color",
          options: ["White", "Yellow", "Green", "Cyan", "Red", "Blue", "Black"],
          values: ["#FFFFFF", "#FFE082", "#66BB6A", "#4DD0E1", "#EF5350", "#42A5F5", "#000000"] },
        { key: "subBackColor", title: "Background color",
          options: ["None", "Black", "White"],
          values: ["", "000000", "FFFFFF"] },
        { key: "subBackOpacity", title: "Background opacity",
          options: ["25%", "50%", "75%", "100%"],
          values: [0.25, 0.5, 0.75, 1.0] },
        { key: "subStrokeColor", title: "Stroke color",
          options: ["Black", "White"],
          values: ["#CC000000", "#FFFFFF"] },
        { key: "subStroke", title: "Stroke thickness",
          options: ["None", "Thin", "Normal", "Thick"],
          values: [0, 1.2, 2.2, 3.8] }
    ]

    function applySubStyle() {
        const byKey = {};
        for (const d of subOptionDefs)
            byKey[d.key] = d;
        const pick = (k) => byKey[k].values[store[k + "Idx"]];
        mpv.setProp("sub-font", pick("subFont"));
        mpv.setProp("sub-font-size", pick("subSize"));
        mpv.setProp("sub-color", pick("subColor"));
        mpv.setProp("sub-border-color", pick("subStrokeColor"));
        mpv.setProp("sub-border-size", pick("subStroke"));
        const backRgb = pick("subBackColor");
        if (backRgb === "") {
            mpv.setProp("sub-back-color", "#00000000");
        } else {
            const a = Math.round(pick("subBackOpacity") * 255)
                .toString(16).padStart(2, "0").toUpperCase();
            mpv.setProp("sub-back-color", "#" + a + backRgb);
        }
    }

    Settings {
        id: store
        property string glassTheme: "liquid"
        property int skipInterval: 10
        property real speed: 1.0
        property int subFontIdx: 0
        property int subSizeIdx: 2
        property int subColorIdx: 0
        property int subBackColorIdx: 0
        property int subBackOpacityIdx: 2
        property int subStrokeColorIdx: 0
        property int subStrokeIdx: 2
    }
    onGlassThemeChanged: if (envTheme === "") store.glassTheme = glassTheme
    onSkipIntervalChanged: store.skipInterval = skipInterval
    Connections {
        target: mpv
        function onSpeedChanged() { store.speed = mpv.speed }
    }
    function poke() {
        controlsShown = true;
        hideTimer.restart();
    }
    Timer {
        id: hideTimer
        interval: 2600
        onTriggered: if (!mpv.pause && !win.settingsOpen && !holdControls) win.controlsShown = false
    }
    Component.onCompleted: {
        skipInterval = store.skipInterval;
        glassTheme = envTheme !== "" ? envTheme : store.glassTheme;
        mpv.speed = store.speed;
        applySubStyle();
        if (holdControls) settingsOpen = true;
    }

    function fmt(s) {
        if (isNaN(s) || s < 0) s = 0;
        const h = Math.floor(s / 3600);
        const m = Math.floor((s % 3600) / 60);
        const sec = Math.floor(s % 60);
        const mm = (h > 0 && m < 10 ? "0" : "") + m;
        const ss = (sec < 10 ? "0" : "") + sec;
        return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss;
    }

    MpvObject {
        id: mpv
        anchors.fill: parent
        onFileLoaded: pause = false
        Component.onCompleted: if (cliFile !== "") loadFile(cliFile)
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: win.controlsShown ? Qt.ArrowCursor : Qt.BlankCursor
        onPositionChanged: win.poke()
        onClicked: {
            if (win.settingsOpen)
                win.settingsOpen = false;
            else
                mpv.togglePause();
            win.poke();
        }
        onDoubleClicked: win.toggleFullscreen()
        onWheel: (wheel) => {
            const step = wheel.angleDelta.y > 0 ? 5 : -5;
            mpv.volume = Math.max(0, Math.min(130, mpv.volume + step));
            win.showVolume();
            win.poke();
        }
    }

    function toggleFullscreen() {
        win.visibility = win.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen;
    }

    // ---- Reusable pieces ------------------------------------------------

    // Real hyprglass lens: each button refracts the video underneath it.
    component GlassButton: Item {
        id: gbtn
        signal activated()
        property real diameter: 56
        property bool hovered: ma.containsMouse
        property bool pressed: ma.pressed
        property color tint: Qt.rgba(0, 0, 0, ma.containsMouse ? 0.20 : 0.10)
        width: diameter
        height: diameter
        scale: ma.pressed ? 0.94 : (ma.containsMouse ? 1.12 : 1)
        Behavior on scale { SpringAnimation { spring: 2.8; damping: 0.40; epsilon: 0.004 } }
        GlassItem {
            anchors.fill: parent
            videoSource: mpv
            tint: gbtn.tint
            blurOnly: win.glassTheme === "blur"
        }
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, gbtn.hovered ? 0.42 : 0.28)
            border.width: 1
        }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { gbtn.activated(); win.poke(); }
        }
    }

    component SkipButton: GlassButton {
        id: skipBtn
        property bool forward: true

        // Keyboard skips replay the full click feedback: press dip + ring spin.
        property real pulse: 1
        transform: Scale {
            origin.x: skipBtn.width / 2
            origin.y: skipBtn.height / 2
            xScale: skipBtn.pulse
            yScale: skipBtn.pulse
        }
        SequentialAnimation {
            id: pressPulse
            NumberAnimation { target: skipBtn; property: "pulse"; to: 0.88; duration: 70; easing.type: Easing.OutQuad }
            SpringAnimation { target: skipBtn; property: "pulse"; to: 1; spring: 2.8; damping: 0.40; epsilon: 0.004 }
        }
        function doSkip() {
            spinAnim.restart();
            mpv.seekBy(forward ? win.skipInterval : -win.skipInterval);
        }
        function trigger() {
            pressPulse.restart();
            doSkip();
        }
        Item {
            id: skipIcon
            anchors.centerIn: parent
            width: skipBtn.diameter * 0.62
            height: width
            Item {
                id: ringBox
                anchors.fill: parent
                Shape {
                    width: 24; height: 24
                    preferredRendererType: Shape.CurveRenderer
                    transform: Scale { xScale: skipIcon.width / 24; yScale: skipIcon.height / 24 }
                    ShapePath {
                        strokeWidth: 2
                        strokeColor: "white"
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathSvg { path: skipBtn.forward ? "M12 5 A 7 7 0 1 0 19 12" : "M12 5 A 7 7 0 1 1 5 12" }
                    }
                    ShapePath {
                        strokeColor: "transparent"
                        fillColor: "white"
                        PathSvg { path: skipBtn.forward ? "M11.2 2 L11.2 8 L16 5 Z" : "M12.8 2 L12.8 8 L8 5 Z" }
                    }
                }
            }
            Text {
                anchors.centerIn: parent
                text: win.skipInterval
                color: "white"
                font.family: win.uiFont
                font.bold: true
                font.pixelSize: skipIcon.width * 0.30
            }
        }
        NumberAnimation {
            id: spinAnim
            target: ringBox
            property: "rotation"
            from: 0
            to: skipBtn.forward ? 360 : -360
            duration: 700
            easing.type: Easing.OutCubic
        }
        onActivated: doSkip()
    }

    // ---- Center transport cluster ---------------------------------------

    Row {
        id: transport
        anchors.centerIn: parent
        spacing: 34
        opacity: win.controlsShown ? 1 : 0
        visible: opacity > 0
        scale: win.controlsShown ? 1 : 0.86
        Behavior on opacity { NumberAnimation { duration: 180 } }
        Behavior on scale { SpringAnimation { spring: 2.8; damping: 0.40; epsilon: 0.004 } }

        SkipButton { id: skipBack; forward: false; anchors.verticalCenter: parent.verticalCenter }

        GlassButton {
            id: playBtn
            diameter: 76
            anchors.verticalCenter: parent.verticalCenter
            onActivated: mpv.togglePause()

            Item {
                id: glyphBox
                anchors.fill: parent
                Shape {
                    anchors.centerIn: parent
                    width: 24; height: 24
                    visible: mpv.pause
                    preferredRendererType: Shape.CurveRenderer
                    transform: Scale {
                        origin.x: 12; origin.y: 12
                        xScale: playBtn.diameter * 0.52 / 24
                        yScale: playBtn.diameter * 0.52 / 24
                    }
                    ShapePath {
                        strokeWidth: 1.6
                        strokeColor: "white"
                        fillColor: "white"
                        joinStyle: ShapePath.RoundJoin
                        capStyle: ShapePath.RoundCap
                        PathSvg { path: "M7.3 6.9v10.2c0 .95 1.05 1.53 1.85 1.02l8-5.1c.74-.47.74-1.57 0-2.04l-8-5.1c-.8-.51-1.85.07-1.85 1.02z" }
                    }
                }
                Row {
                    anchors.centerIn: parent
                    visible: !mpv.pause
                    spacing: playBtn.diameter * 0.11
                    Repeater {
                        model: 2
                        Rectangle {
                            width: playBtn.diameter * 0.13
                            height: playBtn.diameter * 0.38
                            radius: width / 2
                            color: "white"
                        }
                    }
                }
            }
            SequentialAnimation {
                id: glyphPop
                NumberAnimation { target: glyphBox; property: "scale"; to: 1.22; duration: 80; easing.type: Easing.OutQuad }
                SpringAnimation { target: glyphBox; property: "scale"; to: 1; spring: 2.8; damping: 0.40; epsilon: 0.004 }
            }
            Connections {
                target: mpv
                function onPauseChanged() { glyphPop.restart() }
            }
        }

        SkipButton { id: skipFwd; forward: true; anchors.verticalCenter: parent.verticalCenter }
    }

    // ---- Bottom line: times, seek, subtitles, settings -------------------

    RowLayout {
        id: bottomBar
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width * 0.9
        spacing: 14
        opacity: win.controlsShown ? 1 : 0
        visible: opacity > 0
        transform: Translate {
            y: win.controlsShown ? 0 : 30
            Behavior on y { SpringAnimation { spring: 2.8; damping: 0.40; epsilon: 0.02 } }
        }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Text {
            text: win.fmt(mpv.position)
            color: "white"
            font.family: win.uiFont
            font.bold: true
            font.pixelSize: 15
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.6)
        }

        Item {
            id: seekArea
            Layout.fillWidth: true
            height: 26
            property bool active: seekMa.containsMouse || seekMa.pressed

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: seekArea.active ? 12 : 7
                radius: height / 2
                color: Qt.rgba(1, 1, 1, 0.22)
                Behavior on height { SpringAnimation { spring: 2.8; damping: 0.40; epsilon: 0.02 } }

                Rectangle {
                    id: fill
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    // While dragging, track the cursor directly; otherwise follow
                    // playback with a short glide.
                    property real shownRatio: seekMa.pressed
                        ? Math.max(0, Math.min(seekMa.mouseX / seekArea.width, 1))
                        : (mpv.duration > 0 ? mpv.position / mpv.duration : 0)
                    width: parent.width * shownRatio
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: win.primarySoft }
                        GradientStop { position: 1; color: win.primary }
                    }
                    Behavior on width {
                        enabled: !seekMa.pressed
                        NumberAnimation { duration: 150 }
                    }
                }
            }
            Rectangle {
                id: seekPreview
                readonly property bool showing: (seekArea.active || win.previewForced) && mpv.duration > 0
                readonly property real hoverRatio: Math.max(0, Math.min(seekMa.mouseX / seekArea.width, 1))
                readonly property real hoverTime: hoverRatio * mpv.duration
                property real thumbLastSeek: -1

                visible: opacity > 0
                opacity: showing ? 1 : 0
                scale: showing ? 1 : 0.82
                transformOrigin: Item.Bottom
                Behavior on opacity { NumberAnimation { duration: 150 } }
                Behavior on scale { SpringAnimation { spring: 2.8; damping: 0.40; epsilon: 0.004 } }

                x: Math.max(0, Math.min(seekMa.mouseX - width / 2, seekArea.width - width))
                anchors.bottom: parent.top
                anchors.bottomMargin: 12
                width: 210
                height: 146
                radius: 14
                color: Qt.rgba(0, 0, 0, 0.55)
                border.color: Qt.rgba(1, 1, 1, 0.30)
                border.width: 1

                onShowingChanged: {
                    if (showing && seekArea.active) {
                        thumbMpv.seek(hoverTime);
                        thumbLastSeek = hoverTime;
                    }
                }

                Item {
                    x: 5
                    y: 5
                    width: 200
                    height: 113
                    MpvObject {
                        id: thumbMpv
                        thumbnailMode: true
                        anchors.fill: parent
                        Component.onCompleted: if (cliFile !== "") loadFile(cliFile)
                    }
                    ShaderEffectSource {
                        id: thumbSrc
                        sourceItem: thumbMpv
                        hideSource: true
                        live: true
                    }
                    ShaderEffect {
                        anchors.fill: parent
                        fragmentShader: "qrc:/kadr/shaders/rounded.frag.qsb"
                        property var source: thumbSrc
                        property size size: Qt.size(width, height)
                        property real radius: 10
                    }
                }
                Text {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 5
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: win.fmt(seekPreview.hoverTime)
                    color: "white"
                    font.family: win.uiFont
                    font.bold: true
                    font.pixelSize: 13
                }
                Timer {
                    id: thumbThrottle
                    interval: 80
                    onTriggered: {
                        if (Math.abs(seekPreview.hoverTime - seekPreview.thumbLastSeek) > 0.5) {
                            thumbMpv.seek(seekPreview.hoverTime);
                            seekPreview.thumbLastSeek = seekPreview.hoverTime;
                        }
                    }
                }
            }
            Rectangle {
                id: knob
                anchors.verticalCenter: parent.verticalCenter
                x: fill.width - width / 2
                width: 16
                height: 16
                radius: 8
                color: "white"
                scale: seekArea.active ? 1 : 0
                Behavior on scale { SpringAnimation { spring: 2.8; damping: 0.40; epsilon: 0.004 } }
            }
            MouseArea {
                id: seekMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                onPressed: (mouse) => mpv.seek(mouse.x / width * mpv.duration)
                onPositionChanged: (mouse) => {
                    win.poke();
                    if (pressed)
                        mpv.seek(Math.max(0, Math.min(mouse.x / width, 1)) * mpv.duration);
                    if (seekPreview.showing && !thumbThrottle.running)
                        thumbThrottle.start();
                }
            }
        }

        Text {
            text: win.fmt(mpv.duration)
            color: "white"
            font.family: win.uiFont
            font.bold: true
            font.pixelSize: 15
            style: Text.Raised
            styleColor: Qt.rgba(0, 0, 0, 0.6)
        }

        GlassButton {
            diameter: 40
            opacity: mpv.subVisible ? 1 : 0.45
            onActivated: mpv.subVisible = !mpv.subVisible
            Shape {
                anchors.centerIn: parent
                width: 24; height: 24
                preferredRendererType: Shape.CurveRenderer
                transform: Scale { origin.x: 12; origin.y: 12; xScale: 0.8; yScale: 0.8 }
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: "white"
                    PathSvg { path: "M4 4h16a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2zm2 6h3v2H6v-2zm5 0h7v2h-7v-2zM6 14h7v2H6v-2zm9 0h3v2h-3v-2z" }
                }
            }
        }

        GlassButton {
            diameter: 40
            onActivated: win.settingsOpen = !win.settingsOpen
            Shape {
                anchors.centerIn: parent
                width: 24; height: 24
                preferredRendererType: Shape.CurveRenderer
                transform: Scale { origin.x: 12; origin.y: 12; xScale: 0.8; yScale: 0.8 }
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: "white"
                    PathSvg { path: "M19.14 12.94a7.5 7.5 0 0 0 0-1.88l2.03-1.58a.5.5 0 0 0 .12-.64l-1.92-3.32a.5.5 0 0 0-.6-.22l-2.39.96a7.3 7.3 0 0 0-1.62-.94l-.36-2.54a.5.5 0 0 0-.5-.42h-3.84a.5.5 0 0 0-.5.42l-.36 2.54c-.59.24-1.13.56-1.62.94l-2.39-.96a.5.5 0 0 0-.6.22L2.71 8.84a.5.5 0 0 0 .12.64l2.03 1.58a7.5 7.5 0 0 0 0 1.88l-2.03 1.58a.5.5 0 0 0-.12.64l1.92 3.32c.13.22.39.31.6.22l2.39-.96c.49.38 1.03.7 1.62.94l.36 2.54c.04.24.25.42.5.42h3.84c.25 0 .46-.18.5-.42l.36-2.54a7.3 7.3 0 0 0 1.62-.94l2.39.96c.21.09.47 0 .6-.22l1.92-3.32a.5.5 0 0 0-.12-.64l-2.03-1.58zM12 15.5A3.5 3.5 0 1 1 12 8.5a3.5 3.5 0 0 1 0 7z" }
                }
            }
        }
    }

    // ---- Settings panel --------------------------------------------------

    // Reusable pieces for the YouTube-style settings menu

    component MenuRow: Item {
        id: mrow
        property string label
        property string value: ""
        signal activated()
        width: parent ? parent.width : 0
        height: 44
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: Qt.rgba(1, 1, 1, mrowMa.containsMouse ? 0.10 : 0)
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: mrow.label
            color: "white"
            font.family: win.uiFont
            font.pixelSize: 14
        }
        Row {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: mrow.value
                color: Qt.rgba(1, 1, 1, 0.65)
                font.family: win.uiFont
                font.pixelSize: 13
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "›"
                color: Qt.rgba(1, 1, 1, 0.65)
                font.family: win.uiFont
                font.bold: true
                font.pixelSize: 16
            }
        }
        MouseArea {
            id: mrowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mrow.activated()
        }
    }

    component OptionRow: Item {
        id: orow
        property string label
        property bool selected: false
        signal activated()
        width: parent ? parent.width : 0
        height: 40
        Rectangle {
            anchors.fill: parent
            radius: 10
            color: Qt.rgba(1, 1, 1, orowMa.containsMouse ? 0.10 : 0)
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            text: orow.selected ? "✓" : ""
            color: "white"
            font.family: win.uiFont
            font.bold: true
            font.pixelSize: 14
        }
        Text {
            anchors.left: parent.left
            anchors.leftMargin: 38
            anchors.verticalCenter: parent.verticalCenter
            text: orow.label
            color: "white"
            font.family: win.uiFont
            font.pixelSize: 14
        }
        MouseArea {
            id: orowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: orow.activated()
        }
    }

    component MenuPage: Item {
        id: mpage
        required property string name
        default property alias content: pageCol.data
        width: parent ? parent.width : 0
        implicitHeight: pageCol.implicitHeight
        visible: opacity > 0
        opacity: settingsPanel.page === name ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        onVisibleChanged: {
            if (visible) {
                settingsPanel.contentHeight = implicitHeight;
                slideAnim.from = 18 * settingsPanel.navDir;
                slideAnim.restart();
            }
        }
        onImplicitHeightChanged: if (visible) settingsPanel.contentHeight = implicitHeight
        NumberAnimation {
            id: slideAnim
            target: mpage
            property: "x"
            to: 0
            duration: 220
            easing.type: Easing.OutCubic
        }
        Column {
            id: pageCol
            width: mpage.width
            spacing: 2
        }
    }

    Item {
        id: settingsPanel
        anchors.bottom: bottomBar.top
        anchors.bottomMargin: 16
        anchors.right: bottomBar.right
        width: 360
        height: 58 + contentHeight + 20
        transformOrigin: Item.BottomRight
        opacity: win.settingsOpen ? 1 : 0
        scale: win.settingsOpen ? 1 : 0.68
        visible: opacity > 0
        transform: Translate {
            y: win.settingsOpen ? 0 : 26
            Behavior on y { SpringAnimation { spring: 2.8; damping: 0.40; epsilon: 0.02 } }
        }
        Behavior on opacity { NumberAnimation { duration: 220 } }
        Behavior on scale { SpringAnimation { spring: 2.8; damping: 0.40; epsilon: 0.004 } }
        Behavior on height { SpringAnimation { spring: 2.8; damping: 0.40; epsilon: 0.5 } }

        // page navigation state
        property string page: "root"
        property int navDir: 1
        property var activeDef: null
        property real contentHeight: 180

        function navigate(to, dir) {
            navDir = dir;
            page = to;
        }
        function goBack() {
            navigate(page === "option" ? "subtitles" : "root", -1);
        }
        function titleFor(p) {
            if (p === "speed") return "Playback speed";
            if (p === "subtitles") return "Subtitles";
            if (p === "theme") return "Theme";
            if (p === "skip") return "Skip interval";
            if (p === "option") return activeDef ? activeDef.title : "";
            return "Settings";
        }

        // return to the root page once the close animation finished
        Timer {
            id: pageResetTimer
            interval: 260
            onTriggered: settingsPanel.navigate("root", -1)
        }
        Connections {
            target: win
            function onSettingsOpenChanged() {
                if (!win.settingsOpen)
                    pageResetTimer.start();
            }
        }

        GlassItem {
            anchors.fill: parent
            videoSource: mpv
            cornerRadius: 24
            tint: Qt.rgba(0, 0, 0, 0.45)
            blurOnly: win.glassTheme === "blur"
        }
        Rectangle {
            anchors.fill: parent
            radius: 24
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.28)
            border.width: 1
        }
        MouseArea {
            // swallow clicks so the panel doesn't toggle pause underneath
            anchors.fill: parent
            hoverEnabled: true
            onPositionChanged: win.poke()
        }

        // header: back chevron + title
        Item {
            x: 22
            y: 14
            width: parent.width - 44
            height: 26
            Text {
                id: backBtn
                visible: settingsPanel.page !== "root"
                anchors.verticalCenter: parent.verticalCenter
                text: "‹"
                color: "white"
                font.family: win.uiFont
                font.bold: true
                font.pixelSize: 22
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: settingsPanel.goBack()
                }
            }
            Text {
                x: settingsPanel.page === "root" ? 0 : 24
                anchors.verticalCenter: parent.verticalCenter
                text: settingsPanel.titleFor(settingsPanel.page)
                color: "white"
                font.family: win.uiFont
                font.bold: true
                font.pixelSize: 15
                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }
        }
        Rectangle {
            x: 22
            y: 48
            width: parent.width - 44
            height: 1
            color: Qt.rgba(1, 1, 1, 0.14)
        }

        Item {
            id: pages
            x: 22
            y: 58
            width: parent.width - 44
            height: settingsPanel.contentHeight
            clip: true

            MenuPage {
                name: "root"
                Component.onCompleted: settingsPanel.contentHeight = implicitHeight
                MenuRow {
                    label: "Subtitles"
                    onActivated: settingsPanel.navigate("subtitles", 1)
                }
                MenuRow {
                    label: "Playback speed"
                    value: mpv.speed === 1 ? "Normal"
                        : (Number.isInteger(mpv.speed) ? mpv.speed.toFixed(1) : mpv.speed.toString()) + "x"
                    onActivated: settingsPanel.navigate("speed", 1)
                }
                MenuRow {
                    label: "Theme"
                    value: win.glassTheme === "blur" ? "Blur" : "Liquid Glass"
                    onActivated: settingsPanel.navigate("theme", 1)
                }
                MenuRow {
                    label: "Skip interval"
                    value: win.skipInterval + "s"
                    onActivated: settingsPanel.navigate("skip", 1)
                }
            }

            MenuPage {
                name: "speed"
                Item { width: parent.width; height: 6 }
                Text {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: mpv.speed.toFixed(2) + "x"
                    color: "white"
                    font.family: win.uiFont
                    font.bold: true
                    font.pixelSize: 26
                }
                Item { width: parent.width; height: 8 }
                Item {
                    width: parent.width
                    height: 44
                    Rectangle {
                        id: speedMinus
                        width: 36
                        height: 36
                        radius: 18
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(1, 1, 1, minusMa.containsMouse ? 0.22 : 0.12)
                        Text {
                            anchors.centerIn: parent
                            text: "−"
                            color: "white"
                            font.family: win.uiFont
                            font.bold: true
                            font.pixelSize: 18
                        }
                        MouseArea {
                            id: minusMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mpv.speed = Math.max(0.25, Math.round((mpv.speed - 0.25) * 4) / 4)
                        }
                    }
                    Rectangle {
                        id: speedPlus
                        width: 36
                        height: 36
                        radius: 18
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(1, 1, 1, plusMa.containsMouse ? 0.22 : 0.12)
                        Text {
                            anchors.centerIn: parent
                            text: "+"
                            color: "white"
                            font.family: win.uiFont
                            font.bold: true
                            font.pixelSize: 18
                        }
                        MouseArea {
                            id: plusMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mpv.speed = Math.min(3, Math.round((mpv.speed + 0.25) * 4) / 4)
                        }
                    }
                    Item {
                        id: spdSlider
                        anchors.left: speedMinus.right
                        anchors.right: speedPlus.left
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        height: 36
                        readonly property real ratio: Math.max(0, Math.min((mpv.speed - 0.25) / 2.75, 1))
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Qt.rgba(1, 1, 1, 0.35)
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width * spdSlider.ratio
                            height: 4
                            radius: 2
                            color: "white"
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: parent.width * spdSlider.ratio - 8
                            width: 16
                            height: 16
                            radius: 8
                            color: "white"
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                            function apply(mx) {
                                const r = Math.max(0, Math.min(mx / width, 1));
                                mpv.speed = Math.round((0.25 + r * 2.75) * 20) / 20;
                            }
                            onPressed: (mouse) => apply(mouse.x)
                            onPositionChanged: (mouse) => { if (pressed) apply(mouse.x); }
                        }
                    }
                }
                Item { width: parent.width; height: 10 }
                Row {
                    spacing: 8
                    Repeater {
                        model: [1.0, 1.25, 1.5, 2.0, 3.0]
                        Rectangle {
                            required property real modelData
                            readonly property bool selected: Math.abs(mpv.speed - modelData) < 0.01
                            width: speedChipText.implicitWidth + 24
                            height: 34
                            radius: 17
                            color: selected
                                ? Qt.rgba(win.primary.r, win.primary.g, win.primary.b, 0.85)
                                : Qt.rgba(1, 1, 1, 0.12)
                            border.color: Qt.rgba(1, 1, 1, selected ? 0.5 : 0.25)
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                id: speedChipText
                                anchors.centerIn: parent
                                text: Number.isInteger(parent.modelData)
                                    ? parent.modelData.toFixed(1) : parent.modelData.toString()
                                color: "white"
                                font.family: win.uiFont
                                font.bold: true
                                font.pixelSize: 13
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mpv.speed = parent.modelData
                            }
                        }
                    }
                }
                Item {
                    width: parent.width
                    height: 18
                    Text {
                        x: 12
                        y: 2
                        text: "Normal"
                        color: Qt.rgba(1, 1, 1, 0.55)
                        font.family: win.uiFont
                        font.pixelSize: 11
                    }
                }
            }

            MenuPage {
                name: "subtitles"
                Repeater {
                    model: win.subOptionDefs
                    MenuRow {
                        required property var modelData
                        label: modelData.title
                        value: modelData.options[store[modelData.key + "Idx"]]
                        onActivated: {
                            settingsPanel.activeDef = modelData;
                            settingsPanel.navigate("option", 1);
                        }
                    }
                }
            }

            MenuPage {
                name: "option"
                Repeater {
                    model: settingsPanel.activeDef ? settingsPanel.activeDef.options : []
                    OptionRow {
                        required property int index
                        required property var modelData
                        label: modelData
                        selected: settingsPanel.activeDef !== null
                            && store[settingsPanel.activeDef.key + "Idx"] === index
                        onActivated: {
                            store[settingsPanel.activeDef.key + "Idx"] = index;
                            win.applySubStyle();
                        }
                    }
                }
            }

            MenuPage {
                name: "theme"
                OptionRow {
                    label: "Liquid Glass"
                    selected: win.glassTheme === "liquid"
                    onActivated: win.glassTheme = "liquid"
                }
                OptionRow {
                    label: "Blur"
                    selected: win.glassTheme === "blur"
                    onActivated: win.glassTheme = "blur"
                }
            }

            MenuPage {
                name: "skip"
                Repeater {
                    model: [2, 5, 10]
                    OptionRow {
                        required property var modelData
                        label: modelData + " seconds"
                        selected: win.skipInterval === modelData
                        onActivated: win.skipInterval = modelData
                    }
                }
            }
        }
    }

    // ---- Volume OSD ------------------------------------------------------

    function showVolume() {
        volumeOsd.opacity = 1;
        volumeOsdTimer.restart();
    }
    Timer {
        id: volumeOsdTimer
        interval: 1200
        onTriggered: volumeOsd.opacity = 0
    }
    Rectangle {
        id: volumeOsd
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 22
        width: volRow.implicitWidth + 34
        height: 40
        radius: 20
        color: Qt.rgba(0, 0, 0, 0.55)
        border.color: Qt.rgba(1, 1, 1, 0.30)
        border.width: 1
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 150 } }
        Row {
            id: volRow
            anchors.centerIn: parent
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: mpv.mute ? "Muted" : "Volume " + Math.round(mpv.volume) + "%"
                color: "white"
                font.family: win.uiFont
                font.bold: true
                font.pixelSize: 14
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 70
                height: 6
                radius: 3
                color: Qt.rgba(1, 1, 1, 0.22)
                Rectangle {
                    width: parent.width * Math.min(mpv.volume, 100) / 100
                    height: parent.height
                    radius: parent.radius
                    color: mpv.mute ? Qt.rgba(1, 1, 1, 0.4) : win.primary
                    Behavior on width { NumberAnimation { duration: 120 } }
                }
            }
        }
    }

    // ---- Keyboard --------------------------------------------------------

    Item {
        focus: true
        Keys.onPressed: (event) => {
            win.poke();
            switch (event.key) {
            case Qt.Key_Space: mpv.togglePause(); break;
            case Qt.Key_Left: skipBack.trigger(); break;
            case Qt.Key_Right: skipFwd.trigger(); break;
            case Qt.Key_Down: mpv.volume = Math.max(0, mpv.volume - 5); win.showVolume(); break;
            case Qt.Key_Up: mpv.volume = Math.min(130, mpv.volume + 5); win.showVolume(); break;
            case Qt.Key_F: win.toggleFullscreen(); break;
            case Qt.Key_M: mpv.mute = !mpv.mute; win.showVolume(); break;
            case Qt.Key_S: mpv.subVisible = !mpv.subVisible; break;
            case Qt.Key_Escape:
                if (win.settingsOpen)
                    win.settingsOpen = false;
                else
                    win.visibility = Window.Windowed;
                break;
            case Qt.Key_Q: Qt.quit(); break;
            default: return;
            }
            event.accepted = true;
        }
    }

    // ---- Headless smoke test (KADR_SMOKE=1) ------------------------------

    Timer {
        running: smokeTest
        interval: 6000
        onTriggered: {
            const frames = mpv.updateCount();
            if (mpv.duration > 0 && frames > 30) {
                console.log("KADR_SMOKE_OK duration=" + mpv.duration + " frames=" + frames
                            + " speed=" + mpv.speed + " theme=" + win.glassTheme
                            + " skip=" + win.skipInterval + " primary=" + win.primary + " dark=" + Theme.dark);
                if (shotPath !== "") {
                    mpv.seek(780);
                    shotTimer.start();
                } else {
                    Qt.quit();
                }
            } else {
                console.log("KADR_SMOKE_FAIL duration=" + mpv.duration + " frames=" + frames);
                Qt.exit(1);
            }
        }
    }
    Timer {
        id: shotTimer
        interval: 2200
        onTriggered: {
            hideTimer.stop();
            win.controlsShown = true;
            win.settingsOpen = true;
            win.previewForced = true;
            shotThumbTimer.start();
        }
    }
    Timer {
        id: shotThumbTimer
        interval: 700
        onTriggered: {
            thumbMpv.seek(795);
            grabTimer.start();
        }
    }
    Timer {
        id: grabTimer
        interval: 700
        onTriggered: {
            console.log("KADR_SHOT_PRE speed=" + mpv.speed);
            win.contentItem.grabToImage((result) => {
                result.saveToFile(shotPath);
                console.log("KADR_SHOT_SAVED " + shotPath + " speed=" + mpv.speed);
                Qt.quit();
            });
        }
    }
}
