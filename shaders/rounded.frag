#version 440

// Samples a texture clipped to a rounded rectangle with antialiased corners.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;      // item size in px
    float radius;   // corner radius in px
} u;

layout(binding = 1) uniform sampler2D source;

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * u.size;
    vec2 halfSize = u.size * 0.5;
    vec2 q = abs(p) - halfSize + u.radius;
    float sdf = min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - u.radius;
    float alpha = 1.0 - smoothstep(-1.0, 0.5, sdf);
    fragColor = texture(source, qt_TexCoord0) * alpha * u.qt_Opacity;
}
