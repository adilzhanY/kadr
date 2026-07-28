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
    function poke() {
        controlsShown = true;
        hideTimer.restart();
    }
    Timer {
        id: hideTimer
        interval: 2600
        onTriggered: if (!mpv.pause) win.controlsShown = false
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
        onClicked: { mpv.togglePause(); win.poke(); }
        onDoubleClicked: win.toggleFullscreen()
    }

    function toggleFullscreen() {
        win.visibility = win.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen;
    }

    // ---- Reusable pieces ------------------------------------------------

    // P1 swaps this frosted approximation for the real hyprglass lens port.
    component GlassButton: Rectangle {
        id: gbtn
        signal activated()
        property real diameter: 56
        property bool hovered: ma.containsMouse
        width: diameter
        height: diameter
        radius: diameter / 2
        color: Qt.rgba(1, 1, 1, ma.containsMouse ? 0.22 : 0.10)
        border.color: Qt.rgba(1, 1, 1, 0.30)
        border.width: 1
        scale: ma.pressed ? 0.94 : (ma.containsMouse ? 1.12 : 1)
        Behavior on scale { SpringAnimation { spring: 2.8; damping: 0.40; epsilon: 0.004 } }
        MouseArea {
            id: ma
            anchors.fill: parent
            hoverEnabled: true
            onClicked: { gbtn.activated(); win.poke(); }
        }
    }

    component SkipButton: GlassButton {
        id: skipBtn
        property bool forward: true
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
                text: "10"
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
        onActivated: {
            spinAnim.restart();
            mpv.seekBy(forward ? 10 : -10);
        }
    }

    // ---- Center transport cluster ---------------------------------------

    Row {
        id: transport
        anchors.centerIn: parent
        spacing: 34
        opacity: win.controlsShown ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        SkipButton { forward: false; anchors.verticalCenter: parent.verticalCenter }

        GlassButton {
            id: playBtn
            diameter: 76
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(win.primary.r, win.primary.g, win.primary.b, hovered ? 0.75 : 0.55)
            onActivated: mpv.togglePause()

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

        SkipButton { forward: true; anchors.verticalCenter: parent.verticalCenter }
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
                    width: mpv.duration > 0 ? parent.width * mpv.position / mpv.duration : 0
                    radius: parent.radius
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: win.primarySoft }
                        GradientStop { position: 1; color: win.primary }
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
                onPressed: (mouse) => mpv.seek(mouse.x / width * mpv.duration)
                onPositionChanged: (mouse) => {
                    win.poke();
                    if (pressed)
                        mpv.seek(Math.max(0, Math.min(mouse.x / width, 1)) * mpv.duration);
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
            onActivated: {} // settings panel arrives in P3
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

    // ---- Keyboard --------------------------------------------------------

    Item {
        focus: true
        Keys.onPressed: (event) => {
            win.poke();
            switch (event.key) {
            case Qt.Key_Space: mpv.togglePause(); break;
            case Qt.Key_Left: mpv.seekBy(-5); break;
            case Qt.Key_Right: mpv.seekBy(5); break;
            case Qt.Key_Down: mpv.volume = Math.max(0, mpv.volume - 5); break;
            case Qt.Key_Up: mpv.volume = Math.min(130, mpv.volume + 5); break;
            case Qt.Key_F: win.toggleFullscreen(); break;
            case Qt.Key_M: mpv.mute = !mpv.mute; break;
            case Qt.Key_S: mpv.subVisible = !mpv.subVisible; break;
            case Qt.Key_Escape: win.visibility = Window.Windowed; break;
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
                            + " primary=" + win.primary + " dark=" + Theme.dark);
                Qt.quit();
            } else {
                console.log("KADR_SMOKE_FAIL duration=" + mpv.duration + " frames=" + frames);
                Qt.exit(1);
            }
        }
    }
}
