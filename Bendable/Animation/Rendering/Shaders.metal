#include <metal_stdlib>
using namespace metal;

// Layout must stay in step with `RenderUniforms` in RenderUniforms.swift.
struct Uniforms {
    float2 scale;
    float2 translate;
    float foldAngle;
    float foldPosition;
    float perspective;
    float curvature;
    float creaseHighlight;
    float aspect;
    float blur;
    float blurGradient;
    float wash;
    float cornerRadius;
    float brightness;
    float opacity;
    float vignette;
    float edgeOcclusion;
    float maskOpenness;
    uint maskKind;
    uint blades;
    uint useTexture;
    float maxLOD;
    uint effectKind;
    float effectProgress;
    float sunSize;
    float glow;
    float exposure;
    float warmth;
    float horizon;
    float darkness;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float depth;
};

// The image is one sheet creased along a horizontal line. Everything below the crease
// stays put; everything above rotates about it and away from the viewer. Rather than
// pre-dividing by w on the CPU, the rotated point is emitted with a real clip-space w,
// so the rasteriser gives perspective-correct texture interpolation for free.
vertex VertexOut foldVertex(uint vid [[vertex_id]],
                            const device float2 *grid [[buffer(0)]],
                            constant Uniforms &u [[buffer(1)]]) {
    float2 uv = grid[vid];
    float2 ndc = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    ndc = ndc * u.scale + u.translate;

    float aspect = max(u.aspect, 0.001);
    float xModel = ndc.x * aspect;
    float creaseY = -1.0 + 2.0 * clamp(u.foldPosition, 0.0, 1.0);
    float above = ndc.y - creaseY;

    float c = cos(u.foldAngle);
    float s = sin(u.foldAngle);

    float yRotated = ndc.y;
    float zRotated = 0.0;
    if (above > 0.0) {
        yRotated = creaseY + above * c;
        zRotated = above * s;

        // Folding panels do not crease to a sharp line: the material bows just past
        // the hinge and flattens out again further along. The falloff is wide because
        // a narrow one puts a visible kink where the bow ends.
        float nearCrease = smoothstep(0.0, 0.30, above) * (1.0 - smoothstep(0.30, 1.6, above));
        zRotated += u.curvature * s * nearCrease;
    }

    // A large viewing distance degenerates to an orthographic projection, which is what
    // `perspective == 0` should give.
    // A long viewing distance: the panel should foreshorten strongly in height while
    // its sides converge only gently, which is how a display reads at arm's length.
    // A short distance turns the keystone into a caricature.
    float distance = mix(40.0, 5.0, clamp(u.perspective, 0.0, 1.0));
    float w = max((distance + zRotated) / distance, 0.001);

    // x and y are left in NDC and the divide is done by w during rasterisation, which
    // both applies the perspective and makes the texture coordinates perspective
    // correct. Pre-multiplying by w here would cancel the divide and project
    // orthographically.
    VertexOut out;
    out.position = float4(xModel / aspect, yRotated, 0.0, w);
    out.uv = uv;
    out.depth = zRotated;
    return out;
}

static float maskCoverage(constant Uniforms &u, float2 uv) {
    float2 p = float2(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0);
    float openness = clamp(u.maskOpenness, 0.0, 1.0);

    switch (u.maskKind) {
        case 1: {
            // Regular polygon iris. Distance to the polygon is the largest projection
            // of the point onto the blade normals.
            float2 q = float2(p.x * u.aspect, p.y);
            float bladeCount = max(float(u.blades), 3.0);
            float d = -1e9;
            for (uint i = 0; i < u.blades && i < 16; ++i) {
                float a = (float(i) / bladeCount) * 6.2831853 + 0.3;
                d = max(d, dot(q, float2(cos(a), sin(a))));
            }
            // Scaled so that full openness exactly circumscribes the frame. Any more
            // slack than that and the first third of the travel does nothing visible.
            float radius = openness * sqrt(u.aspect * u.aspect + 1.0);
            return smoothstep(radius - 0.006, radius + 0.006, d);
        }
        case 2: {
            return smoothstep(openness - 0.004, openness + 0.004, abs(p.y));
        }
        case 3: {
            // Slats. Each one shuts from its own two edges toward its centre line, so
            // the picture is cut into shrinking bands rather than wiped from one side.
            float slats = max(float(u.blades), 2.0);
            float withinSlat = fract((p.y + 1.0) * 0.5 * slats);
            float fromCentre = abs(withinSlat - 0.5) * 2.0;
            // Widen the edge as the slats close: a fixed one aliases badly once a band
            // is only a few pixels tall.
            float softness = 0.004 + 0.02 * (1.0 - openness);
            return smoothstep(openness - softness, openness + softness, fromCentre);
        }
        default:
            return 0.0;
    }
}

// Defocus by mip level alone is cheap but shows the mip grid once the level is high.
// Five taps spread across one texel of the selected level dissolve that structure into
// the smooth fields a real defocus produces, still in a single pass.
static float3 defocusSample(texture2d<float> source, sampler samp, float2 uv, float lod) {
    if (lod < 0.01) {
        return source.sample(samp, uv, level(0.0)).rgb;
    }
    float2 texel = exp2(lod) / float2(source.get_width(), source.get_height());
    float3 sum = source.sample(samp, uv, level(lod)).rgb * 0.32;
    const float2 offsets[4] = {
        float2( 0.92,  0.39), float2(-0.39,  0.92),
        float2(-0.92, -0.39), float2( 0.39, -0.92),
    };
    for (uint i = 0; i < 4; ++i) {
        sum += source.sample(samp, uv + offsets[i] * texel, level(lod)).rgb * 0.17;
    }
    return sum;
}

// Tiny stable blue-noise-like dither. The render target is 8-bit sRGB, so adding less
// than one code value before encoding removes long bands without visible grain.
static float interleavedGradientNoise(float2 pixel) {
    return fract(52.9829189 * fract(dot(pixel, float2(0.06711056, 0.00583715))));
}

static float3 sunsetHDR(float2 uv, float2 pixel, constant Uniforms &u) {
    float t = saturate(u.effectProgress);
    float horizon = mix(0.47, 0.69, saturate(u.horizon));
    float warmControl = mix(0.55, 1.35, saturate(u.warmth));

    // Separate zenith and horizon palettes retain atmospheric depth. Broad,
    // overlapping transitions avoid the flat two-stop gradient look.
    float golden = smoothstep(0.16, 0.44, t);
    float red = smoothstep(0.42, 0.69, t);
    float twilight = smoothstep(0.64, 0.90, t);

    float3 zenith = mix(float3(0.12, 0.46, 1.08), float3(0.22, 0.35, 0.78), golden);
    zenith = mix(zenith, float3(0.35, 0.10, 0.20) * warmControl, red);
    zenith = mix(zenith, float3(0.035, 0.045, 0.16), twilight);

    float3 atHorizon = mix(float3(0.58, 0.82, 1.18), float3(1.42, 0.48, 0.075) * warmControl, golden);
    atHorizon = mix(atHorizon, float3(1.05, 0.075, 0.025) * warmControl, red);
    atHorizon = mix(atHorizon, float3(0.16, 0.07, 0.24), twilight);

    float vertical = saturate(uv.y / max(horizon, 0.01));
    float atmosphericDepth = pow(vertical, 0.72);
    float3 color = mix(zenith, atHorizon, atmosphericDepth);

    // A cooler upper-air veil and a warm low haze keep the field from reading as a
    // mathematical gradient while remaining temporally stable at a parked lid angle.
    color += float3(0.035, 0.07, 0.16) * (1.0 - vertical) * (1.0 - twilight);
    float horizonDistance = abs(uv.y - horizon);
    float haze = exp(-horizonDistance * horizonDistance * 420.0);
    float3 hazeColor = mix(float3(0.45, 0.60, 0.80), float3(1.30, 0.28, 0.055), saturate(golden + red));
    color += hazeColor * haze * mix(0.12, 0.38, saturate(u.glow)) * (1.0 - twilight * 0.72);

    // The sun descends linearly in world space. The hard disk crosses the horizon at
    // roughly 70% closed; atmospheric extinction removes it only after the crossing.
    float aspect = max(u.aspect, 0.001);
    float2 sunCenter = float2(0.52, mix(0.22, horizon + 0.22, t));
    float2 fromSun = float2((uv.x - sunCenter.x) * aspect, uv.y - sunCenter.y);
    float distanceToSun = length(fromSun);
    float radius = mix(0.025, 0.078, saturate(u.sunSize));
    float disk = 1.0 - smoothstep(radius * 0.82, radius, distanceToSun);
    float bloomWidth = mix(0.055, 0.24, saturate(u.glow));
    float bloom = exp(-distanceToSun * distanceToSun / max(bloomWidth * bloomWidth, 0.0001));
    float belowHorizon = smoothstep(horizon - radius * 0.35, horizon + radius * 1.35, sunCenter.y);
    float sunRiseIn = smoothstep(0.045, 0.15, t);
    float sunVisibility = sunRiseIn * (1.0 - smoothstep(0.73, 0.86, t))
        * (1.0 - belowHorizon * 0.88);
    float3 sunTint = mix(float3(1.0, 0.94, 0.66), float3(1.0, 0.19, 0.035), saturate(red * warmControl));
    color += sunTint * bloom * mix(0.55, 2.8, saturate(u.glow)) * sunVisibility;
    color += float3(7.0, 5.0, 2.2) * disk * sunVisibility;

    // Below the optical horizon, dense air removes blue light and then rolls into a
    // dark foreground. It also cleanly occludes the lower part of the setting disk.
    float below = smoothstep(horizon - 0.003, horizon + 0.055, uv.y);
    float3 lower = mix(atHorizon * 0.62, float3(0.018, 0.012, 0.035), twilight);
    color = mix(color, lower, below * mix(0.28, 0.76, twilight));

    // Darkness controls when twilight deepens, but the terminal ramp always reaches
    // true black so the nearly-closed overlay meets the system sleep transition.
    float earlyDark = smoothstep(0.73, 0.98, t) * saturate(u.darkness);
    color *= 1.0 - earlyDark * 0.93;
    color *= 1.0 - smoothstep(0.965, 1.0, t);

    // Exponential exposure is a smooth highlight rolloff: the sun can be many times
    // brighter than the sky internally without clipping to a flat cartoon-white disk.
    float exposure = mix(0.72, 1.75, saturate(u.exposure));
    color = 1.0 - exp(-max(color, float3(0.0)) * exposure);
    float dither = (interleavedGradientNoise(pixel) - 0.5) / 255.0
        * (1.0 - smoothstep(0.94, 1.0, t));
    return saturate(color + dither);
}

fragment float4 foldFragment(VertexOut in [[stage_in]],
                             constant Uniforms &u [[buffer(0)]],
                             texture2d<float> source [[texture(0)]],
                             sampler samp [[sampler(0)]]) {
    if (u.effectKind == 1) {
        float alpha = saturate(u.opacity);
        float3 color = sunsetHDR(in.uv, in.position.xy, u);
        return float4(color * alpha, alpha);
    }

    // The panel turns about its bottom edge, so the top is what swings away from the
    // viewer. Grading the effects along that axis is what makes a completely flat,
    // undistorted image read as a display folding shut.
    float away = smoothstep(0.05, 0.95, 1.0 - in.uv.y);
    float ramp = mix(1.0, away, clamp(u.blurGradient, 0.0, 1.0));

    float3 color = float3(0.0);
    if (u.useTexture != 0) {
        color = defocusSample(source, samp, in.uv, clamp(u.blur, 0.0, 1.0) * ramp * u.maxLOD);
    }

    if (u.wash > 0.0 && u.useTexture != 0) {
        // Colour drains before light does, as a panel turns away. It drains toward grey
        // and then toward nothing, never toward white. Lifting it would fight the very
        // thing the panel is fading into.
        float amount = clamp(u.wash * ramp, 0.0, 1.0);
        float luma = dot(color, float3(0.2126, 0.7152, 0.0722));
        color = mix(color, float3(luma), amount * 0.8);
    }

    color *= max(u.brightness, 0.0);

    if (u.edgeOcclusion > 0.0) {
        // Light falls off along the panel, and it has to fall to nothing: the far edge
        // sits against the black the overlay is painted on, and anything short of the
        // same black shows as a seam.
        //
        // The falloff runs along the panel's own length rather than by depth alone.
        // Depth is the physical quantity, but it is near zero at the hinge however far
        // the panel has turned, which leaves the whole lower half at full brightness and
        // the picture reading as lit rather than fading. Depth still contributes, so a
        // panel barely turned is barely darkened.
        float along = saturate(away * 0.7 + saturate(in.depth * 0.72) * 0.3);
        color *= 1.0 - u.edgeOcclusion * along * along;
    }

    if (u.vignette > 0.0) {
        float2 p = float2(in.uv.x * 2.0 - 1.0, in.uv.y * 2.0 - 1.0);
        float r = length(p * float2(1.0, 0.86));
        color *= 1.0 - u.vignette * smoothstep(0.35, 1.3, r);
    }

    if (u.creaseHighlight > 0.0) {
        // Light catching the bend. Measured in image space so it stays welded to the
        // crease in the content rather than to a fixed line on screen, and faded at
        // the sides so it reads as a sheen rather than a drawn line.
        float creaseUV = 1.0 - clamp(u.foldPosition, 0.0, 1.0);
        float band = 1.0 - smoothstep(0.0, 0.018, abs(in.uv.y - creaseUV));
        float acrossPanel = 1.0 - smoothstep(0.25, 0.5, abs(in.uv.x - 0.5));
        color += u.creaseHighlight * band * band * acrossPanel * 0.16;
    }

    float alpha = clamp(u.opacity, 0.0, 1.0);
    if (u.maskKind != 0) {
        alpha *= maskCoverage(u, in.uv);
    }

    if (u.cornerRadius > 0.0) {
        // Rounded-rectangle distance in image space, so the corners follow the
        // content through the transform instead of sitting on the screen.
        float2 halfExtent = float2(u.aspect, 1.0);
        float2 p = (in.uv - 0.5) * 2.0 * halfExtent;
        float radius = min(u.cornerRadius, min(halfExtent.x, halfExtent.y));
        float2 q = abs(p) - (halfExtent - radius);
        float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
        alpha *= 1.0 - smoothstep(-0.004, 0.004, d);
    }

    // The layer is composited with premultiplied alpha.
    return float4(saturate(color) * alpha, alpha);
}
