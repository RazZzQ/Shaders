Shader "Custom/TMP_CRT_Glitch"
{
Properties
    {
        _MainTex ("Font Atlas", 2D) = "white" {}
        _FaceColor ("Face Color", Color) = (1,1,1,1)
        _OutlineColor ("Outline Color", Color) = (0,0,0,1)
        _OutlineThickness ("Outline Thickness", Range(0,0.2)) = 0.04

        _GlitchIntensity ("Glitch Intensity", Range(0,1)) = 0.5
        _RGBSplit ("RGB Split", Range(0,0.05)) = 0.02
        _Speed ("Speed", Range(0,10)) = 1.5
        _BurstFrequency ("Burst Frequency", Range(0.2,10)) = 3.0
        _BurstDuration ("Burst Duration", Range(0.05,1)) = 0.25
        _ScaleAmount ("Scale Amount X", Range(0,1)) = 0.4
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" }
        Blend SrcAlpha OneMinusSrcAlpha
        Cull Off
        ZWrite Off

        Pass
        {
        Name "GlitchPass"
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            struct v2f
            {
                float4 pos : SV_POSITION;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;
            float4 _FaceColor;
            float4 _OutlineColor;
            float _OutlineThickness;
            float _GlitchIntensity;
            float _RGBSplit;
            float _Speed;
            float _BurstFrequency;
            float _BurstDuration;
            float _ScaleAmount;

                        // pseudo-random
            float hash11(float x)
            {
                return frac(sin(x * 127.1) * 43758.5453);
            }

            v2f vert(appdata v)
            {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                o.color = v.color;
                return o;
            }

            half4 frag(v2f i) : SV_Target
            {
                float t = _Time.y * _Speed;

                            // Create periodic bursts
                float burstPhase = frac(t / _BurstFrequency);
                float glitchActive = step(burstPhase, _BurstDuration); // 1 during glitch, 0 otherwise
                float smoothActive = smoothstep(0.0, 0.2, glitchActive);

                            // Generate random hue per burst (based on floor of burst count)
                float burstID = floor(t / _BurstFrequency);
                float rnd = hash11(burstID * 3.33);
                float3 randomHue = normalize(float3(
                                abs(sin(rnd * 6.283 + 0.0)),
                                abs(sin(rnd * 6.283 + 2.094)), // +120°
                                abs(sin(rnd * 6.283 + 4.188)) // +240°
                            ));

                            // Scale X during glitch burst
                float scaleX = lerp(1.0, 1.0 + _ScaleAmount, smoothActive);
                float2 uvScaled = (i.uv - 0.5) * float2(scaleX, 1.0) + 0.5;

                            // Apply RGB split offsets only when active
                float offset = _RGBSplit * glitchActive;
                float2 uvR = uvScaled + float2(offset, 0.0);
                float2 uvG = uvScaled;
                float2 uvB = uvScaled - float2(offset, 0.0);

                half4 sR = tex2D(_MainTex, uvR);
                half4 sG = tex2D(_MainTex, uvG);
                half4 sB = tex2D(_MainTex, uvB);

                            // Choose correct SDF channel (alpha or red)
                float sdf = sG.a > 0.001 ? sG.a : sG.r;
                float smoothing = 0.08;
                float alpha = smoothstep(0.5 - smoothing, 0.5 + smoothing, sdf);
                float outline = smoothstep(0.5 - _OutlineThickness - smoothing, 0.5 - smoothing, sdf);

                            // Combine RGB channels into glitch color
                float3 rgbSplit = float3(sR.r, sG.g, sB.b);

                            // Base color logic
                float3 baseColor = lerp(_OutlineColor.rgb, _FaceColor.rgb, outline);

                            // Apply RGB split + random hue during glitch
                float3 glitchColor = lerp(baseColor, rgbSplit * randomHue * _FaceColor.rgb, glitchActive);

                            // Composite final
                float3 finalColor = glitchColor * i.color.rgb;
                float finalAlpha = alpha * i.color.a * _FaceColor.a;

                return half4(finalColor, finalAlpha);
            }
            ENDHLSL
        }
    }
}
