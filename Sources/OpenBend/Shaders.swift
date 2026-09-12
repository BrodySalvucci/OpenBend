import Foundation

/// Metal shader source, compiled at launch so the app needs no metallib packaging step.
enum BendShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct VOut {
        float4 position [[position]];
        float2 uv;
    };

    // p0 = (lid angle, reference angle, eye distance, eye height)
    // p1 = (texel width, texel height, aspect, viewport height)
    // p2 = (blur, shadow, visibility, ramp)
    // p3 = (keystone 0…1, optics 0 glass / 1 Duo / 2 True Duo, unused, unused)

    static float hash21(float2 p) {
        return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
    }

    // Frosted-glass treatment: lose a little saturation, lift toward white, add a fine fixed grain.
    static float3 frost(float3 color, float amount, float2 pixel) {
        float luma = dot(color, float3(0.299, 0.587, 0.114));
        color = mix(color, float3(luma), 0.28 * amount);
        color = mix(color, float3(1.0), 0.10 * amount);
        color += (hash21(floor(pixel * 0.5)) - 0.5) * 0.05 * amount;
        return color;
    }

    // MARK: Separable Gaussian blur with the radius as a uniform (no per-radius kernel objects).
    // p = (direction x, direction y, sigma in texels, tap spacing in texels)

    fragment float4 blur_fragment(VOut in [[stage_in]],
                                  constant float4 &p [[buffer(0)]],
                                  texture2d<float> src [[texture(0)]],
                                  sampler smp [[sampler(0)]]) {
        float2 texel = 1.0 / float2(src.get_width(), src.get_height());
        float2 step = float2(p.x, p.y) * texel * p.w;
        float sigma = max(p.z, 0.001);
        float3 acc = float3(0.0);
        float total = 0.0;
        for (int i = -16; i <= 16; ++i) {
            float d = float(i) * p.w;
            float w = exp(-0.5 * d * d / (sigma * sigma));
            acc += src.sample(smp, in.uv + step * float(i)).rgb * w;
            total += w;
        }
        return float4(acc / total, 1.0);
    }

    // A small Gaussian at each successive half-resolution level gives a continuous diffusion
    // pyramid. Fractional LOD then interpolates adjacent blur radii, never sharp + heavy ghosting.
    fragment float4 diffusion_fragment(VOut in [[stage_in]],
                                       constant float4 &p [[buffer(0)]],
                                       texture2d<float> src [[texture(0)]],
                                       sampler smp [[sampler(0)]]) {
        float2 step = p.xy / float2(src.get_width(), src.get_height());
        float3 c = src.sample(smp, in.uv, level(0)).rgb * 0.499116;
        c += (src.sample(smp, in.uv + step, level(0)).rgb
            + src.sample(smp, in.uv - step, level(0)).rgb) * 0.228512;
        c += (src.sample(smp, in.uv + step * 2.0, level(0)).rgb
            + src.sample(smp, in.uv - step * 2.0, level(0)).rgb) * 0.021930;
        return float4(c, 1.0);
    }

    vertex VOut bend_vertex(uint vid [[vertex_id]]) {
        const float2 corners[4] = { float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0), float2(1.0, 1.0) };
        float2 q = corners[vid];
        VOut o;
        o.position = float4(q, 0.0, 1.0);
        o.uv = float2((q.x + 1.0) * 0.5, (1.0 - q.y) * 0.5);
        return o;
    }

    // The panel is a pane of glass over content that stays put. Each panel pixel is cast from
    // the fixed eye onto the plane where the desktop is held (the lid's angle when the bend
    // began). Where the glass still touches the content (the hinge) it is clear; the further it
    // pulls away, the more the content diffuses.
    fragment float4 bend_fragment(VOut in [[stage_in]],
                                  constant float4 &p0 [[buffer(0)]],
                                  constant float4 &p1 [[buffer(1)]],
                                  constant float4 &p2 [[buffer(2)]],
                                  constant float4 &p3 [[buffer(3)]],
                                  texture2d<float> sharp [[texture(0)]],
                                  texture2d<float> soft [[texture(1)]],
                                  texture2d<float> heavy [[texture(2)]],
                                  texture2d<float> diffusion [[texture(3)]],
                                  sampler smp [[sampler(0)]]) {
        float alpha = p0.x;
        float alpha0 = p0.y;
        float3 eye = float3(p0.z, p0.w, 0.0);
        float aspect = p1.z;
        float blur = p2.x;
        float shadow = p2.y;
        float visibility = p2.z;
        float ramp = p2.w;
        float keystone = p3.x;

        // Exact identity avoids a softened menu bar or a color flash when the overlay clears.
        if (ramp < 0.000001 && abs(alpha - alpha0) < 0.000001) {
            return float4(sharp.sample(smp, in.uv, level(0)).rgb, 1.0);
        }

        // Panel pixel → point on the physical screen. Screen is 1 unit tall, hinge at the origin,
        // +x toward the viewer, +y up, z across the panel.
        float s = 1.0 - in.uv.y;                                   // 0 hinge … 1 top of panel
        float z = (in.uv.x - 0.5) * aspect;
        float3 p = float3(s * cos(alpha), s * sin(alpha), z);

        // Cast from the eye through that point onto the reference plane.
        float3 n0 = float3(-sin(alpha0), cos(alpha0), 0.0);
        float3 dir = p - eye;
        float denominator = dot(n0, dir);
        float mu = abs(denominator) > 0.00001 ? -dot(n0, eye) / denominator : -1.0;
        float3 q = eye + mu * dir;
        float t = q.x * cos(alpha0) + q.y * sin(alpha0);           // height on the held desktop
        float lateral = z * (1.0 + keystone * (mu - 1.0));         // perspective narrowing, scaled
        float2 uv = float2(lateral / aspect + 0.5, 1.0 - t);
        if (mu <= 0.0) { uv = float2(0.5, 3.0); }                  // ray misses: treat as far outside

        // How far off the desktop this pixel landed, in desktop units.
        float outside = max(max(-uv.x, uv.x - 1.0), max(-uv.y, uv.y - 1.0));
        outside = max(outside, 0.0);

        if (p3.y > 0.5) {
            // Duo and True Duo share these optics. Leave a contact zone clear at the MacBook
            // hinge. The glass-to-content distance grows toward the top, so blur develops
            // spatially instead of dimming the whole panel.
            float separation = smoothstep(0.12, 0.92, s);
            float diffusionAmount = pow(separation, 1.15);
            float radius = blur * diffusionAmount * 0.055 * p1.w;
            float outsideMix = smoothstep(0.0, 0.12, outside);
            radius = max(radius, outsideMix * (0.025 + 0.025 * ramp) * p1.w);

            // Convert output-pixel radius into capture texels. This keeps softness consistent
            // across Retina scales and window sizes. The Gaussian pyramid is smooth in log space.
            float sourceRadius = radius * float(sharp.get_height()) / max(p1.w, 1.0);
            float lod = log2(1.0 + sourceRadius);
            lod = clamp(lod, 0.0, float(diffusion.get_num_mip_levels() - 1));
            float3 color = diffusion.sample(smp, clamp(uv, 0.0, 1.0), level(lod)).rgb;

            // A broad, quiet reflection follows the curved glass. No white frost or grain:
            // dark surfaces stay dark and the source desktop supplies the material's color.
            float reflection = exp(-pow((s - (0.70 - 0.10 * ramp)) / 0.28, 2.0));
            float grazing = ramp * separation;
            color += (1.0 - color) * (0.024 * reflection * grazing);
            float shade = shadow * (0.08 + 0.50 * s * s);
            color *= (1.0 - shade) * visibility;

            if (p3.y > 1.5) {
                // True Duo draws the narrowing exactly, so the desktop reads as a rectangle
                // standing in space: the further the lid comes down, the more the sides pull in.
                // Past the desktop's edge there is nothing behind the glass. Fading a sample
                // taken out there would fade a copy of the edge pixels, which reads as the
                // content ghosting outward, so the falloff is measured from inside the picture:
                // beyond the edge is exactly black, and the last of the real content dissolves
                // into it. The band opens up with the travel, so a barely-folded lid still meets
                // its own edge cleanly. uv.y == 1 is the hinge, which stays anchored and solid.
                // How far the panel reaches past the desktop at this row, in desktop units.
                // At the hinge it is nothing — the two edges coincide — and it opens up toward
                // the top, which is what draws the wedge.
                float widen = 1.0 + keystone * (mu - 1.0);
                float overshootX = max(0.0, (widen - 1.0) * 0.5);
                float reach = -dot(n0, eye);
                float muTop = reach / max(reach + sin(alpha - alpha0), 0.0001);
                float depth = eye.x * cos(alpha0) + eye.y * sin(alpha0);
                float overshootY = max(0.0, depth + muTop * (cos(alpha - alpha0) - depth) - 1.0);

                // Dissolve the last of the real content into the black, never wider than the
                // overshoot itself, so an edge that still lines up with the panel's own edge
                // (the hinge, and the whole picture before the lid moves) stays untouched.
                // Half a texel of slack keeps that coincident edge on the lit side.
                float band = 0.01 + 0.05 * ramp;
                float fadeX = smoothstep(0.0, max(min(band, overshootX), 0.00001),
                                         min(uv.x, 1.0 - uv.x) + 0.5 * p1.x);
                float fadeY = smoothstep(0.0, max(min(band, overshootY), 0.00001),
                                         uv.y + 0.5 * p1.y);
                color *= min(fadeX, fadeY);
            } else {
                color *= 1.0 - 0.24 * outsideMix;
            }
            return float4(saturate(color), 1.0);
        }

        // Diffusion grows with the gap between glass and content: none at the hinge, full at the top.
        float kin = blur * mix(0.05, 1.0, s);
        // Only reached when keystone > 0: past the content's edge the diffused light spills out
        // (clamped, heavily blurred) and gently falls off.
        float kout = smoothstep(0.0, 0.10, outside) * (0.8 + 0.2 * ramp);
        float k = max(kin, kout);

        float3 color = sharp.sample(smp, uv).rgb;
        if (k > 0.001) {
            color = mix(color, soft.sample(smp, uv).rgb, saturate(k / 0.5));
            color = mix(color, heavy.sample(smp, uv).rgb, saturate((k - 0.5) / 0.5));
        }
        color = frost(color, kin, in.position.xy);
        color *= 1.0 - 0.45 * smoothstep(0.0, 0.35, outside);

        // The lid shades the top of the physical panel first; the panel goes dark as it turns edge-on.
        float shade = shadow * (0.22 + 0.78 * s * s);
        color *= (1.0 - shade) * visibility;
        return float4(color, 1.0);
    }
    """
}
