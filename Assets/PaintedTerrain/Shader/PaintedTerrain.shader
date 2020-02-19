// Unity built-in shader source. Copyright (c) 2016 Unity Technologies. MIT license (see license.txt)

Shader "Nature/Terrain/Painted" {
    Properties {
        [HideInInspector] _Control ("Control (RGBA)", 2D) = "red" {}
        [HideInInspector] _Splat3 ("Layer 3 (A)", 2D) = "white" {}
        [HideInInspector] _Splat2 ("Layer 2 (B)", 2D) = "white" {}
        [HideInInspector] _Splat1 ("Layer 1 (G)", 2D) = "white" {}
        [HideInInspector] _Splat0 ("Layer 0 (R)", 2D) = "white" {}
        [HideInInspector] _Normal3 ("Normal 3 (A)", 2D) = "bump" {}
        [HideInInspector] _Normal2 ("Normal 2 (B)", 2D) = "bump" {}
        [HideInInspector] _Normal1 ("Normal 1 (G)", 2D) = "bump" {}
        [HideInInspector] _Normal0 ("Normal 0 (R)", 2D) = "bump" {}
        // used in fallback on old cards & base map
        [HideInInspector] _MainTex ("BaseMap (RGB)", 2D) = "white" {}
        [HideInInspector] _Color ("Main Color", Color) = (1,1,1,1)
        _Radius("Radius", Range(0, 10)) = 0
    }

    CGINCLUDE
        #pragma surface surf Lambert vertex:SplatmapVert finalcolor:SplatmapFinalColor finalprepass:SplatmapFinalPrepass finalgbuffer:SplatmapFinalGBuffer noinstancing
        #pragma multi_compile_fog
        #include "TerrainSplatmapCommon.cginc"

        uniform int _Radius;
        float4 _Splat0_TexelSize;
        float4 _Splat1_TexelSize;
        float4 _Splat2_TexelSize;
        float4 _Splat3_TexelSize;

        fixed4 PaintedPixel(sampler2D tex, half4 texelSize, half2 uv)
        {
            float3 mean[4] = {
                {0, 0, 0},
                {0, 0, 0},
                {0, 0, 0},
                {0, 0, 0}
            };

            float3 sigma[4] = {
                {0, 0, 0},
                {0, 0, 0},
                {0, 0, 0},
                {0, 0, 0}
            };

            float2 start[4] = {{-_Radius, -_Radius}, {-_Radius, 0}, {0, -_Radius}, {0, 0}};

            float2 pos;
            float3 col;
            for (int k = 0; k < 4; k++) {
                for (int i = 0; i <= _Radius; i++) {
                    for (int j = 0; j <= _Radius; j++) {
                        pos = float2(i, j) + start[k];
                        col = tex2Dlod(tex, float4(uv + float2(pos.x * texelSize.x, pos.y * texelSize.y), 0., 0.)).rgb;
                        mean[k] += col;
                        sigma[k] += col * col;
                    }
                }
            }

            float sigma2;

            float n = pow(_Radius + 1, 2);
            float4 color = tex2D(tex, uv);
            float min = 1;

            for (int l = 0; l < 4; l++) {
                mean[l] /= n;
                sigma[l] = abs(sigma[l] / n - mean[l] * mean[l]);
                sigma2 = sigma[l].r + sigma[l].g + sigma[l].b;

                if (sigma2 < min) {
                    min = sigma2;
                    color.rgb = mean[l].rgb;
                }
            }
            return color;
        }

        void PaintedMix(Input IN, out half4 splat_control, out half weight, out fixed4 mixedDiffuse, inout fixed3 mixedNormal)
        {
            splat_control = tex2D(_Control, IN.tc_Control);
            weight = dot(splat_control, half4(1,1,1,1));

            #if !defined(SHADER_API_MOBILE) && defined(TERRAIN_SPLAT_ADDPASS)
                clip(weight == 0.0f ? -1 : 1);
            #endif

            // Normalize weights before lighting and restore weights in final modifier functions so that the overal
            // lighting result can be correctly weighted.
            splat_control /= (weight + 1e-3f);

            mixedDiffuse = 0.0f;
            mixedDiffuse += splat_control.r * PaintedPixel(_Splat0, _Splat0_TexelSize, IN.uv_Splat0);
            mixedDiffuse += splat_control.g * PaintedPixel(_Splat1, _Splat1_TexelSize, IN.uv_Splat1);
            mixedDiffuse += splat_control.b * PaintedPixel(_Splat2, _Splat2_TexelSize, IN.uv_Splat2);
            mixedDiffuse += splat_control.a * PaintedPixel(_Splat3, _Splat3_TexelSize, IN.uv_Splat3);
        }

        void surf(Input IN, inout SurfaceOutput o)
        {
            half4 splat_control;
            half weight;
            fixed4 mixedDiffuse;
            PaintedMix(IN, splat_control, weight, mixedDiffuse, o.Normal);
            o.Albedo = mixedDiffuse.rgb;
            o.Alpha = weight;
        }
    ENDCG

    Category {
        Tags {
            "Queue" = "Geometry-99"
            "RenderType" = "Opaque"
        }
        // TODO: Seems like "#pragma target 3.0 _TERRAIN_NORMAL_MAP" can't fallback correctly on less capable devices?
        // Use two sub-shaders to simulate different features for different targets and still fallback correctly.
        SubShader { // for sm3.0+ targets
            CGPROGRAM
                #pragma target 3.0
                #pragma multi_compile __ _TERRAIN_NORMAL_MAP
            ENDCG
        }
        SubShader { // for sm2.0 targets
            CGPROGRAM
            ENDCG
        }
    }

    Dependency "AddPassShader" = "Hidden/TerrainEngine/Splatmap/Diffuse-AddPass"
    Dependency "BaseMapShader" = "Diffuse"
    Dependency "Details0"      = "Hidden/TerrainEngine/Details/Vertexlit"
    Dependency "Details1"      = "Hidden/TerrainEngine/Details/WavingDoublePass"
    Dependency "Details2"      = "Hidden/TerrainEngine/Details/BillboardWavingDoublePass"
    Dependency "Tree0"         = "Hidden/TerrainEngine/BillboardTree"

    Fallback "Diffuse"
}
