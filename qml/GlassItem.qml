import QtQuick

// Liquid Glass surface: refracts the video underneath through the hyprglass
// lens shader. Defaults mirror the lglass preset in
// ~/.config/end4-themes/lglass/on-reload.sh so kadr's glass matches the shell.
Item {
    id: root

    required property Item videoSource
    property real cornerRadius: height / 2
    property real roundingPower: 2.0
    property real paddingPx: 26
    property color tint: Qt.rgba(0, 0, 0, 0)

    property real refractionStrength: 1.0
    property real lensDistortion: 1.0
    property real chromaticAberration: 0.8
    property real edgeThickness: 0.15
    property real fresnelStrength: 0.7
    property real specularStrength: 0.9
    property real glassOpacity: 1.0
    property real brightness: 1.0
    property real contrast: 1.0
    property real saturation: 1.0
    property real vibrancy: 0.0
    property real vibrancyDarkness: 0.0
    property real adaptiveDim: 0.0
    property real adaptiveBoost: 0.0

    // Region of the video under this item, expanded so edge refraction has
    // pixels to bend inward. mapToItem gives QML bindings nothing to track
    // (ancestor moves, Row layout, reveal animations), so the rect is re-synced
    // every frame right before the scene graph syncs.
    property rect captureRect: Qt.rect(0, 0, 1, 1)

    function syncRect() {
        const p = root.mapToItem(videoSource, -paddingPx, -paddingPx);
        const r = Qt.rect(p.x, p.y, width + 2 * paddingPx, height + 2 * paddingPx);
        if (r.x !== captureRect.x || r.y !== captureRect.y
                || r.width !== captureRect.width || r.height !== captureRect.height)
            captureRect = r;
    }

    Component.onCompleted: syncRect()
    Connections {
        target: root.Window.window
        function onAfterAnimating() { root.syncRect() }
    }

    ShaderEffectSource {
        id: capture
        sourceItem: root.videoSource
        sourceRect: root.captureRect
        live: true
        visible: false
        smooth: true
    }

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: "qrc:/kadr/shaders/glass.frag.qsb"

        property var source: capture
        property size fullSize: Qt.size(root.width, root.height)
        property size uvPadding: Qt.size(
            root.paddingPx / (root.width + 2 * root.paddingPx),
            root.paddingPx / (root.height + 2 * root.paddingPx))
        property real radius: root.cornerRadius
        property real roundingPower: root.roundingPower
        property real edgeThickness: root.edgeThickness
        property real refractionStrength: root.refractionStrength
        property real chromaticAberration: root.chromaticAberration
        property real lensDistortion: root.lensDistortion
        property real fresnelStrength: root.fresnelStrength
        property real specularStrength: root.specularStrength
        property real glassOpacity: root.glassOpacity
        property color tintColor: root.tint
        property real brightness: root.brightness
        property real contrast: root.contrast
        property real saturation: root.saturation
        property real vibrancy: root.vibrancy
        property real vibrancyDarkness: root.vibrancyDarkness
        property real adaptiveDim: root.adaptiveDim
        property real adaptiveBoost: root.adaptiveBoost
    }
}
