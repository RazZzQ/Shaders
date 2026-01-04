Shader "Lpk/LightModel/ToonLightBase"
{
    Properties
    {
        _BaseMap            ("Texture", 2D)                       = "white" {}
        _BaseColor          ("Color", Color)                      = (0.5,0.5,0.5,1)

        [Space]
        _ShadowStep         ("ShadowStep", Range(0, 1))           = 0.5
        _ShadowStepSmooth   ("ShadowStepSmooth", Range(0, 1))     = 0.04

        [Space]
        _SpecularStep       ("SpecularStep", Range(0, 1))         = 0.6
        _SpecularStepSmooth ("SpecularStepSmooth", Range(0, 1))   = 0.05
        [HDR]_SpecularColor ("SpecularColor", Color)              = (1,1,1,1)

        [Space]
        _RimStep            ("RimStep", Range(0, 1))              = 0.65
        _RimStepSmooth      ("RimStepSmooth",Range(0,1))          = 0.4
        _RimColor           ("RimColor", Color)                   = (1,1,1,1)

        [Space]
        _OutlineWidth      ("OutlineWidth", Range(0.0, 1.0))      = 0.15
        [HDR]_OutlineColor ("OutlineColor", Color)                = (0.0, 0.0, 0.0, 1)

        [Space]
        [Header(Fade and Dissolve)]
        [Toggle(_USE_DISSOLVE)] _UseDissolve ("Use Dissolve", Float) = 0
        _Opacity ("Opacity", Range(0,1)) = 1
        _DissolveMap ("Dissolve Noise", 2D) = "white" {}
        _Dissolve ("Dissolve Amount", Range(0,1)) = 0
        _DissolveSoft ("Dissolve Softness", Range(0,0.5)) = 0.05
        [HDR]_DissolveEdgeColor ("Dissolve Edge Color", Color) = (1,1,1,1)
        _DissolveEdgeWidth ("Dissolve Edge Width", Range(0,1)) = 0.15
    }

    SubShader
    {
        // IMPORTANTE: para opacidad real (fade) usamos Transparent
        Tags { "RenderType"="Opaque" "Queue"="AlphaTest" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode"="UniversalForward" }

            // Blend para transparencia
            //Blend SrcAlpha OneMinusSrcAlpha
            ZWrite On

            HLSLPROGRAM
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x

            #pragma vertex vert
            #pragma fragment frag

            // Dissolve toggle
            #pragma shader_feature_local _USE_DISSOLVE

            // Main light shadows
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

            // Additional lights (Forward)
            #pragma multi_compile _ _ADDITIONAL_LIGHTS

            // Forward+ (Cluster light loop)
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP

            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_DissolveMap);
            SAMPLER(sampler_DissolveMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BaseMap_ST;
                float  _ShadowStep;
                float  _ShadowStepSmooth;
                float  _SpecularStep;
                float  _SpecularStepSmooth;
                float4 _SpecularColor;
                float  _RimStepSmooth;
                float  _RimStep;
                float4 _RimColor;

                float  _Opacity;
                float  _Dissolve;
                float  _DissolveSoft;
                float4 _DissolveEdgeColor;
                float  _DissolveEdgeWidth;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv         : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float  fogCoord   : TEXCOORD3;
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vert(Attributes input)
            {
                Varyings output = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                VertexPositionInputs vpos = GetVertexPositionInputs(input.positionOS.xyz);

                output.positionCS = vpos.positionCS;
                output.positionWS = vpos.positionWS;
                output.normalWS   = TransformObjectToWorldNormal(input.normalOS);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.fogCoord   = ComputeFogFactor(output.positionCS.z);

                return output;
            }

            float ToonStep(float x, float stepValue, float smoothValue)
            {
                return smoothstep(stepValue - smoothValue, stepValue + smoothValue, x);
            }

            float Dither8x8(float2 positionCS)
            {
                // positionCS en pixeles (aprox). Usamos SV_POSITION -> input.positionCS
                // Patrón simple con ruido interleaved (barato y funciona bien)
                float2 p = positionCS.xy;
                float n = frac(52.9829189 * frac(dot(p, float2(0.06711056, 0.00583715))));
                return n; // 0..1
            }
            float4 frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(input);

                float2 uv = input.uv;

                float4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv);
                float alpha = saturate(_Opacity) * baseMap.a * _BaseColor.a;
                float d = Dither8x8(input.positionCS.xy);  // Agrega dithering usando la posición del píxel
                clip(alpha - d);  // Recorta el píxel si no pasa el threshold de opacidad
                // ===== Dissolve (opcional) =====
                #if defined(_USE_DISSOLVE)
                float noise = SAMPLE_TEXTURE2D(_DissolveMap, sampler_DissolveMap, uv).r;

                // threshold: cuando _Dissolve sube, se va revelando
                // Para "aparece poco a poco": usa _Dissolve de 1 -> 0 (o invierte en la animación)
                float threshold = _Dissolve;

                // mask 0..1 (suavizado)
                float mask = smoothstep(threshold - _DissolveSoft, threshold + _DissolveSoft, noise);

                // recorta pixeles (si quieres que desaparezca por completo donde no hay mask)
                clip(mask - 0.001);

                // borde brillante
                float edge = smoothstep(threshold, threshold + max(1e-5, _DissolveSoft), noise) -
                             smoothstep(threshold + _DissolveSoft * (1.0 + _DissolveEdgeWidth), threshold + _DissolveSoft * (2.0 + _DissolveEdgeWidth), noise);

                // alpha también afectado por el mask
                alpha *= mask;
                #else
                float edge = 0.0;
                #endif

                float3 N = normalize(input.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(input.positionWS);

                // ===== Main light (directional) =====
                float4 shadowCoord = TransformWorldToShadowCoord(input.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                float3 L = normalize(mainLight.direction);
                float3 H = normalize(V + L);

                float NV = dot(N, V);
                float NH = saturate(dot(N, H));
                float NL = saturate(dot(N, L));

                float shadowNL = ToonStep(NL, _ShadowStep, _ShadowStepSmooth);

                float specularNH = smoothstep(
                    (1 - _SpecularStep * 0.05) - _SpecularStepSmooth * 0.05,
                    (1 - _SpecularStep * 0.05) + _SpecularStepSmooth * 0.05,
                    NH
                );

                float rim = smoothstep(
                    (1 - _RimStep) - _RimStepSmooth * 0.5,
                    (1 - _RimStep) + _RimStepSmooth * 0.5,
                    0.5 - NV
                );

                float mainAtt = mainLight.shadowAttenuation;
                float3 diffuse  = mainLight.color * baseMap.rgb * _BaseColor.rgb * shadowNL * mainAtt;
                float3 specular = _SpecularColor.rgb * shadowNL * specularNH * mainAtt;
                float3 ambient  = rim * _RimColor.rgb + SampleSH(N) * _BaseColor.rgb * baseMap.rgb;

                // ===== Additional lights =====
                #if defined(_ADDITIONAL_LIGHTS)
                    InputData inputData = (InputData)0;
                    inputData.positionWS = input.positionWS;
                    inputData.normalWS = N;
                    inputData.viewDirectionWS = V;
                    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);

                    #if USE_CLUSTER_LIGHT_LOOP
                    UNITY_LOOP for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
                    {
                        Light light = GetAdditionalLight(lightIndex, inputData.positionWS, half4(1,1,1,1));

                        float3 Ladd = normalize(light.direction);
                        float3 Hadd = normalize(V + Ladd);

                        float NLadd = saturate(dot(N, Ladd));
                        float NHadd = saturate(dot(N, Hadd));

                        float shadowStepAdd = ToonStep(NLadd, _ShadowStep, _ShadowStepSmooth);

                        float specAdd = smoothstep(
                            (1 - _SpecularStep * 0.05) - _SpecularStepSmooth * 0.05,
                            (1 - _SpecularStep * 0.05) + _SpecularStepSmooth * 0.05,
                            NHadd
                        );

                        float att = light.distanceAttenuation * light.shadowAttenuation;

                        diffuse  += light.color * baseMap.rgb * _BaseColor.rgb * shadowStepAdd * att;
                        specular += light.color * _SpecularColor.rgb * specAdd * 0.5 * att;
                    }
                    #endif

                    uint pixelLightCount = GetAdditionalLightsCount();
                    LIGHT_LOOP_BEGIN(pixelLightCount)
                        Light light = GetAdditionalLight(lightIndex, inputData.positionWS, half4(1,1,1,1));

                        float3 Ladd = normalize(light.direction);
                        float3 Hadd = normalize(V + Ladd);

                        float NLadd = saturate(dot(N, Ladd));
                        float NHadd = saturate(dot(N, Hadd));

                        float shadowStepAdd = ToonStep(NLadd, _ShadowStep, _ShadowStepSmooth);

                        float specAdd = smoothstep(
                            (1 - _SpecularStep * 0.05) - _SpecularStepSmooth * 0.05,
                            (1 - _SpecularStep * 0.05) + _SpecularStepSmooth * 0.05,
                            NHadd
                        );

                        float att = light.distanceAttenuation * light.shadowAttenuation;

                        diffuse  += light.color * baseMap.rgb * _BaseColor.rgb * shadowStepAdd * att;
                        specular += light.color * _SpecularColor.rgb * specAdd * 0.5 * att;
                    LIGHT_LOOP_END
                #endif

                float3 finalColor = diffuse + ambient + specular;

                // borde dissolve suma emisión
                #if defined(_USE_DISSOLVE)
                finalColor += edge * _DissolveEdgeColor.rgb;
                #endif

                finalColor = MixFog(finalColor, input.fogCoord);
                return float4(finalColor, alpha);
            }
            ENDHLSL
        }

        // ===== Outline =====
        Pass
        {
            Name "Outline"
            Cull Front
            Tags { "LightMode"="SRPDefaultUnlit" }

            // Para que el outline también obedezca opacidad
            //Blend SrcAlpha OneMinusSrcAlpha
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma shader_feature_local _USE_DISSOLVE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_DissolveMap);
            SAMPLER(sampler_DissolveMap);

            struct appdata
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv     : TEXCOORD0;
            };

            struct v2f
            {
                float4 pos     : SV_POSITION;
                float2 uv      : TEXCOORD0;
                float  fogCoord: TEXCOORD1;
            };

            float _OutlineWidth;
            float4 _OutlineColor;

            float _Opacity;
            float _Dissolve;
            float _DissolveSoft;

            v2f vert(appdata v)
            {
                v2f o;
                float3 posOS = v.vertex.xyz + v.normal * (_OutlineWidth * 0.1);
                float4 posCS = TransformObjectToHClip(posOS);
                o.pos = posCS;
                o.uv = v.uv;
                o.fogCoord = ComputeFogFactor(posCS.z);
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                float alpha = saturate(_Opacity) * _OutlineColor.a;

                #if defined(_USE_DISSOLVE)
                float noise = SAMPLE_TEXTURE2D(_DissolveMap, sampler_DissolveMap, i.uv).r;
                float mask = smoothstep(_Dissolve - _DissolveSoft, _Dissolve + _DissolveSoft, noise);
                clip(mask - 0.001);
                alpha *= mask;
                #endif

                float3 finalColor = MixFog(_OutlineColor.rgb, i.fogCoord);
                return float4(finalColor, alpha);
            }
            ENDHLSL
        }

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }
}
