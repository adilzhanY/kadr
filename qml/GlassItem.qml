import QtQuick

// Liquid Glass surface: refracts the video underneath through the hyprglass
// lens shader. Defaults mirror the lglass preset in
// ~/.config/end4-themes/lglass/on-reload.sh so kadr's glass matches the shell.
//
// The shader samples the video item's texture directly (an FBO item is a
// texture provider) - no ShaderEffectSource, no per-frame copy passes.
Item {
    id: root

    required property Item videoSource
    property real cornerRadius: height / 2
    property real roundingPower: 2.0
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

    // This item's rect in normalized video-texture coordinates. mapToItem
    // gives QML bindings nothing to track (ancestor moves, Row layout, reveal
    // animations), so it is re-synced every frame before the scene graph syncs.
    property vector2d srcOrigin: Qt.vector2d(0, 0)
    property vector2d srcSpan: Qt.vector2d(1, 1)

    function syncRect() {
        if (videoSource.width <= 0 || videoSource.height <= 0)
            return;
        const p = root.mapToItem(videoSource, 0, 0);
        const o = Qt.vector2d(p.x / videoSource.width, p.y / videoSource.height);
        const s = Qt.vector2d(width / videoSource.width, height / videoSource.height);
        if (o !== srcOrigin) srcOrigin = o;
        if (s !== srcSpan) srcSpan = s;
    }

    Component.onCompleted: syncRect()
    Connections {
        target: root.Window.window
        function onAfterAnimating() { root.syncRect() }
    }

    ShaderEffect {
        anchors.fill: parent
        fragmentShader: "qrc:/kadr/shaders/glass.frag.qsb"

        property var source: root.videoSource
        property size fullSize: Qt.size(root.width, root.height)
        property vector2d srcOrigin: root.srcOrigin
        property vector2d srcSpan: root.srcSpan
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
