#version 440

// hyprglass "liquid lens" ported from ~/.local/lib/hyprglass/hyprglass.so to a
// Qt ShaderEffect. Instead of the wallpaper behind a window, it refracts the
// video captured under the control (source = padded region grabbed from the
// player), so the glass bends the movie itself.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 fullSize;              // item size in px
    vec2 srcOrigin;             // item origin in normalized video-texture coords
    vec2 srcSpan;               // item size in normalized video-texture coords
    float radius;               // corner radius in px
    float roundingPower;
    float edgeThickness;
    float refractionStrength;
    float chromaticAberration;
    float lensDistortion;
    float fresnelStrength;
    float specularStrength;
    float glassOpacity;
    vec4 tintColor;             // premultiplied (Qt converts QColor)
    float brightness;
    float contrast;
    float saturation;
    float vibrancy;
    float vibrancyDarkness;
    float adaptiveDim;
    float adaptiveBoost;
    float mode;                 // 0 = liquid lens, 1 = plain frosted blur
    float blurRadius;           // blur kernel radius in item px (mode 1)
} u;

layout(binding = 1) uniform sampler2D source;

// item UV -> video texture UV; offsets outside [0,1] naturally read the real
// neighboring video pixels instead of a clamped padding border
vec4 sampleBlurred(vec2 wuv) {
    vec2 vuv = u.srcOrigin + wuv * u.srcSpan;
    return texture(source, clamp(vuv, 0.001, 0.999));
}

float lpNorm(vec2 v, float p) {
    return pow(pow(abs(v.x), p) + pow(abs(v.y), p), 1.0 / p);
}

float getCornerSDF(vec2 uv) {
    vec2 p = (uv - 0.5) * u.fullSize;
    vec2 halfSize = u.fullSize * 0.5;
    float clampedR = min(u.radius, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - halfSize + clampedR;
    return min(max(q.x, q.y), 0.0) + lpNorm(max(q, vec2(0.0)), u.roundingPower) - clampedR;
}

vec2 refractionDir(vec2 uv) {
    vec2 toCenterPx = (vec2(0.5) - uv) * u.fullSize;
    float len = length(toCenterPx);
    return len > 0.1 ? toCenterPx / len : vec2(0.0);
}

void main() {
    vec2 uv = qt_TexCoord0;

    float cornerSdf = getCornerSDF(uv);
    if (cornerSdf > 0.0)
        discard;
    float cornerAlpha = 1.0 - smoothstep(-1.5, 0.5, cornerSdf);
    if (cornerAlpha < 0.001)
        discard;

    float tintA = u.tintColor.a;
    vec3 tintRGB = tintA > 0.001 ? u.tintColor.rgb / tintA : vec3(0.0);

    // Blur theme: frosted disc blur + tint, none of the lens effects.
    if (u.mode > 0.5) {
        vec3 acc = sampleBlurred(uv).rgb;
        float total = 1.0;
        for (int ring = 1; ring <= 2; ++ring) {
            float rad = u.blurRadius * float(ring) * 0.5;
            for (int i = 0; i < 8; ++i) {
                float a = 6.2831853 * (float(i) + 0.5 * float(ring)) / 8.0;
                vec2 off = vec2(cos(a), sin(a)) * rad / u.fullSize;
                acc += sampleBlurred(uv + off).rgb;
                total += 1.0;
            }
        }
        vec3 frosted = mix(acc / total, tintRGB, tintA);
        float frostedA = u.glassOpacity * cornerAlpha;
        fragColor = vec4(frosted * frostedA, frostedA) * u.qt_Opacity;
        return;
    }

    float minDim = min(u.fullSize.x, u.fullSize.y);
    float bezelWidthPx = u.edgeThickness * minDim;

    // edgeProximity: 1.0 at boundary, exponential decay inward
    float edgeProximity = exp(cornerSdf / bezelWidthPx);
    vec2 inwardDir = refractionDir(uv);

    // Edge refraction: offset sampling inward, like the curved thick edge of a slab
    float refractionPx = u.refractionStrength * 50.0;
    float refractionMag = edgeProximity * refractionPx;
    vec2 baseOffset = inwardDir * refractionMag / u.fullSize;

    // Chromatic aberration: blue refracts more than red
    float chromaSpread = u.chromaticAberration * 0.35;
    vec2 offsetR = baseOffset * (1.0 - chromaSpread);
    vec2 offsetG = baseOffset;
    vec2 offsetB = baseOffset * (1.0 + chromaSpread);

    // Center dome lens, fading near edges
    vec2 domeUV = vec2(0.0);
    if (u.lensDistortion > 0.001) {
        vec2 c = (uv - 0.5) * 2.0;
        vec2 dGrad = vec2(
            -4.0 * c.x * (1.0 - c.y * c.y),
            -4.0 * c.y * (1.0 - c.x * c.x)
        );
        float lensMaxPx = u.lensDistortion * minDim * 0.006;
        float lensFade = 1.0 - edgeProximity;
        domeUV = dGrad * lensMaxPx * lensFade / u.fullSize;
    }

    vec3 color;
    vec2 uvR = uv + offsetR + domeUV;
    vec2 uvG = uv + offsetG + domeUV;
    vec2 uvB = uv + offsetB + domeUV;
    if (u.chromaticAberration > 0.001 && edgeProximity > 0.01) {
        color.r = sampleBlurred(uvR).r;
        color.g = sampleBlurred(uvG).g;
        color.b = sampleBlurred(uvB).b;
    } else {
        color = sampleBlurred(uvG).rgb;
    }

    // Frosted tint / tone mapping
    float blurredLum = dot(color, vec3(0.2126, 0.7152, 0.0722));
    color = mix(vec3(blurredLum), color, u.saturation);
    float lumCurve = smoothstep(0.25, 0.55, blurredLum);
    color *= u.brightness * (1.0 - u.adaptiveDim * lumCurve);
    color += vec3(u.adaptiveBoost * (1.0 - lumCurve) * 0.5);
    color = mix(vec3(0.5), color, u.contrast);
    float currentLum = dot(color, vec3(0.2126, 0.7152, 0.0722));
    float sat = max(color.r, max(color.g, color.b)) - min(color.r, min(color.g, color.b));
    float darkFactor = 1.0 - u.vibrancyDarkness * (1.0 - blurredLum);
    color = mix(vec3(currentLum), color, 1.0 + u.vibrancy * sat * darkFactor);

    // Color tint overlay
    color = mix(color, tintRGB, tintA);

    // Fresnel rim glow
    if (u.fresnelStrength > 0.001) {
        float fresnel = edgeProximity * edgeProximity * u.fresnelStrength * 0.15;
        color += vec3(1.0) * fresnel;
    }

    // Specular top highlight
    if (u.specularStrength > 0.001) {
        float topBias = pow(max(1.0 - uv.y, 0.0), 2.0);
        float spec = topBias * edgeProximity * edgeProximity * u.specularStrength * 0.08;
        color += vec3(1.0, 0.99, 0.97) * spec;
    }

    // Inner shadow (bottom rim)
    {
        float bottomBias = pow(uv.y, 2.0);
        float shadow = bottomBias * edgeProximity * edgeProximity * 0.06;
        color *= 1.0 - shadow;
    }

    float glassA = u.glassOpacity * cornerAlpha;
    fragColor = vec4(color * glassA, glassA) * u.qt_Opacity;
}
