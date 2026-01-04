Shader"Custom/GlitchGlobalEnhancedWorldTMPro"
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
        _SliceIntensity("Slice Intensity", Range(0,10)) = 0.4
        _GlitchActive("Glitch Active", Float) = 0
    }
    SubShader
    {
        Tags { "Queue"="Transparent" "IgnoreProjector"="True" "RenderType"="Transparent" }
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
            float _GlitchActive; //valor booleano (1 = activo, 0 = inactivo)
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
                float2 worldPos : TEXCOORD3;
            };

            float rand(float2 co)
            {
                return frac(sin(dot(co.xy, float2(12.9898, 78.233))) * 43758.5453);
            }

            v2f vert(appdata_t v)
            {
                v2f o;
                float time = _Time.y * _GlitchSpeed;

                // Escalado X ligado a un aleatorio por v�rtice/tiempo
                float glitchRand = rand(v.vertex.xy + time);
                float scaleLerp = step(0.5, glitchRand) * _GlitchAmount;
                float scaleX = lerp(1.0, _ScaleXAmount, scaleLerp);
                float3 pos = v.vertex.xyz;
                pos.x *= scaleX;
    
                o.vertex = UnityObjectToClipPos(float4(pos, 1));
                o.worldPos = v.vertex.xy;

                // UV base
                float2 uv = TRANSFORM_TEX(v.texcoord, _MainTex);

                // ------- MOVIMIENTO ERR�TICO RGB -------
                float t = floor(time * 15.0);
                float2 randomSeed = v.vertex.xy * 0.3 + t;

                float randR = rand(randomSeed + float2(1.1, 3.3));
                float randG = rand(randomSeed + float2(5.7, 9.1));
                float randB = rand(randomSeed + float2(2.8, 7.4));

                float vibR = sin(time * 50.0 + v.vertex.x * 10.0) * 0.5;
                float vibG = cos(time * 45.0 + v.vertex.y * 8.0) * 0.5;
                float vibB = sin(time * 40.0 + v.vertex.x * 12.0) * 0.5;

                float offAmp = _ChannelOffset * _GlitchAmount;
                float2 offR = float2(randR - 0.5 + vibR, vibG * 0.1) * offAmp * 6;
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

                // Ahora el glitch depende SOLO de _GlitchActive (1 = activo)
                float glitchActive = step(0.5, _GlitchActive); // convierte el float a bool
                float glitchFactor = glitchActive * _GlitchAmount;

                // ---------- Flicker visible solo en glitch ----------
                float randFlick = rand(float2(floor(time * 10.0), 0.0));
                float flicker = 1.0;
                if (glitchActive > 0.0)
                {
                    flicker += (_FlickerIntensity * (randFlick - 0.5) * 2.0);
                }
                flicker = saturate(flicker);

                // ---------- Scanlines visibles solo en glitch ----------
                float scanLine = sin(i.worldPos.y * 200.0 + time * 50.0);
                float scanMask = 1.0;
                if (glitchActive > 0.0)
                {
                    scanMask = lerp(1.0, scanLine * 0.5 + 0.5, _ScanlineIntensity);
                }

                // ---------- Slice glitch (global cut) ----------
                float sliceRand = rand(float2(floor(time * 2.0), 1.0));
                float sliceActive = step(0.75, sliceRand) * _SliceIntensity * glitchFactor;

                // Aplica un desplazamiento horizontal uniforme a todo el texto
                float2 sliceOffset = float2(
                    sliceActive * sin(time * 10.0) * 0.15, 0
                );

                // ---------- Textura RGB ----------
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

                // ---------- Color base ----------
                float3 baseColor = i.color.rgb * _FaceColor.rgb;
                float3 rgbColor = float3(outR, outG, outB) * baseColor;

                // ---------- Aplicar glitch visual ----------
                rgbColor *= flicker * scanMask;
                rgbColor += sliceActive * 0.25;

                float outAlpha = max(max(outR, outG), outB) * i.color.a;
                return float4(rgbColor, outAlpha);
                //gosu pes (Raz)xd
            }
            ENDCG
        }
    }
    FallBack"TextMeshPro/Distance Field"
}
