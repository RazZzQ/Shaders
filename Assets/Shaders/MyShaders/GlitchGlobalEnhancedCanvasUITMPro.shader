Shader"Custom/GlitchGlobalEnhancedCanvasUITMPro"
{
    Properties
    {
        _FaceColor("Face Color", Color) = (1,1,1,1)
        _MainTex("Font Atlas", 2D) = "white" {}
        _GlitchAmount("Glitch Amount", Range(0,1)) = 0.5
        _GlitchSpeed("Glitch Speed", Range(0,10)) = 5.0
        _ScaleXAmount("X Scale Amount", Range(1,2)) = 1.2
        _ChannelOffset("RGB Offset", Range(0,0.2)) = 0.02
        _FlickerIntensity("Flicker Intensity", Range(0,1)) = 0.4
        _ScanlineIntensity("Scanline Intensity", Range(0,1)) = 0.2
        _SliceIntensity("Slice Intensity", Range(0,50)) = 0.4
        _GlitchActive("Glitch Active", Float) = 0
    }

    SubShader
    {
        Tags { "Queue"="Transparent" "RenderType"="Transparent" "IgnoreProjector"="True" }
        LOD 250

        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            Cull Off
            ZWrite Off
            Lighting Off
            Fog { Mode Off }

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            sampler2D _MainTex;
            float4 _FaceColor;
            float _GlitchAmount;
            float _GlitchSpeed;
            float _ScaleXAmount;
            float _ChannelOffset;
            float _FlickerIntensity;
            float _ScanlineIntensity;
            float _SliceIntensity;
            float _GlitchActive;
            float4 _MainTex_ST;

            struct appdata_t
            {
                float4 vertex : POSITION;
                float4 color : COLOR;
                float2 texcoord : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float4 color : COLOR;
                float2 uvR : TEXCOORD0;
                float2 uvG : TEXCOORD1;
                float2 uvB : TEXCOORD2;
                float3 localPos : TEXCOORD3; // posici�n local para Canvas World Space
            };

            float rand(float2 co)
            {
                return frac(sin(dot(co.xy, float2(12.9898, 78.233))) * 43758.5453);
            }

            v2f vert(appdata_t v)
            {
                v2f o;
                float time = _Time.y * _GlitchSpeed;

                            // posici�n en espacio objeto ? clip space
                o.vertex = UnityObjectToClipPos(v.vertex);

                            // guardamos posici�n local (para canvas world space)
                o.localPos = v.vertex.xyz;

                            // random para escalado X glitch
                float glitchRand = rand(v.texcoord + time);
                float scaleLerp = step(0.5, glitchRand) * _GlitchAmount;
                float scaleX = lerp(1.0, _ScaleXAmount, scaleLerp);
                float3 pos = v.vertex.xyz;
                pos.x *= scaleX;

                o.vertex = UnityObjectToClipPos(float4(pos, 1));

                            // UVs base
                float2 uv = TRANSFORM_TEX(v.texcoord, _MainTex);
                float t = floor(time * 15.0);

                            // offset RGB din�mico
                float randR = rand(v.texcoord + float2(1.1, 3.3) + t);
                float randG = rand(v.texcoord + float2(5.7, 9.1) + t);
                float randB = rand(v.texcoord + float2(2.8, 7.4) + t);

                float vibR = sin(time * 50.0 + v.texcoord.x * 10.0) * 0.5;
                float vibG = cos(time * 45.0 + v.texcoord.y * 8.0) * 0.5;
                float vibB = sin(time * 40.0 + v.texcoord.x * 12.0) * 0.5;

                float offAmp = _ChannelOffset * _GlitchAmount;
                float2 offR = float2(randR - 0.5 + vibR, vibG * 0.1) * offAmp * 5;
                float2 offG = float2(vibR * 0.2, randG - 0.5 + vibG) * offAmp * 4;
                float2 offB = float2(randB - 0.5 + vibB, vibB * 0.2) * offAmp * 4;

                o.uvR = uv + offR;
                o.uvG = uv + offG;
                o.uvB = uv + offB;

                o.color = v.color;
                return o;
            }

            fixed4 frag(v2f i) : SV_Target
            {
                float time = _Time.y * _GlitchSpeed;
                float glitchActive = step(0.5, _GlitchActive);
                float glitchFactor = glitchActive * _GlitchAmount;

                            // flicker
                float randFlick = rand(float2(floor(time * 10.0), 0.0));
                float flicker = 1.0;
                if (glitchActive > 0.0)
                    flicker += (_FlickerIntensity * (randFlick - 0.5) * 2.0);
                flicker = saturate(flicker);

                            // ---------- Scanlines ----------
                            // basado en posici�n local (Canvas world space)
                float scan_local = sin(i.localPos.y * 500.0 + time * 50.0);
                float scanMask = lerp(1.0, scan_local * 0.5 + 0.5, _ScanlineIntensity);

                            // ---------- Slice glitch ----------
                float sliceBand = frac(i.localPos.y * 12.0 + time * 0.6);
                float sliceRand = rand(float2(floor(sliceBand * 10.0), floor(time * 2.0)));
                float sliceActive = step(0.85, sliceRand) * _SliceIntensity * glitchFactor;
                float2 sliceOffset = float2(sliceActive * sin(time * 25.0 + i.localPos.y * 30.0) * 0.1, 0);

                            // ---------- RGB sampling ----------
                float4 sR = tex2D(_MainTex, i.uvR + sliceOffset);
                float4 sG = tex2D(_MainTex, i.uvG + sliceOffset);
                float4 sB = tex2D(_MainTex, i.uvB + sliceOffset);

                float aR = sR.a;
                float aG = sG.a;
                float aB = sB.a;

                float fw = 0.25 * max(max(fwidth(aR), fwidth(aG)), fwidth(aB));
                float edgeLow = 0.5 - fw;
                float edgeHigh = 0.5 + fw;

                float outR = smoothstep(edgeLow, edgeHigh, aR);
                float outG = smoothstep(edgeLow, edgeHigh, aG);
                float outB = smoothstep(edgeLow, edgeHigh, aB);

                float3 baseColor = i.color.rgb * _FaceColor.rgb;
                float3 rgbColor = float3(outR, outG, outB) * baseColor;

                rgbColor *= flicker * scanMask;
                rgbColor += sliceActive * 0.25;

                float outAlpha = max(max(outR, outG), outB) * i.color.a;
                return float4(rgbColor, outAlpha);
            }
            ENDCG
        }
    }
    FallBack"TextMeshPro/Distance Field"
}
