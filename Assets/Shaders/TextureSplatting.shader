// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/Texture Splatting" {
    Properties{
        _MainTex("Splat Map", 2D) = "white" {}
        [NoScaleOffset] _Texture1 ("Texture 1", 2D) = "white" {}
        [NoScaleOffset] _Texture2 ("Texture 2", 2D) = "white" {}
        // Monochrome splat textures allow use of 2 textures. RGB textures allow up to 4
        [NoScaleOffset] _Texture3 ("Texture 3", 2D) = "white" {}
        [NoScaleOffset] _Texture4 ("Texture 4", 2D) = "white" {}
    }

    Subshader {  // A shader can have multiple subshaders
        Pass {  // Each subshader can have multiple passes
            CGPROGRAM
            // Shaders consist of 2 programs each:
            // The Vertex shader is responsible for processing the vertex data of a mesh
            // The Fragment shader is responsible for coloring individual pixels inside the mesh's triangles.
            #pragma vertex MyVertexProgram
            #pragma fragment MyFragmentProgram

            #include "UnityCG.cginc"  // includes some generic functionalities
            
            // Properties need to be declared inside the shaders in order to be accessed
            sampler2D _MainTex;
            float4 _MainTex_ST;  // ST stands for Scale Translation

            sampler2D _Texture1, _Texture2, _Texture3, _Texture4;

            struct Interpolators {
                float4 position: SV_POSITION;
                float2 uv: TEXCOORD0;
                float2 uvSplat : TEXCOORD1;
            };

            struct VertexData {
                float4 position: POSITION;
                float2 uv: TEXCOORD0;
            };

            Interpolators MyVertexProgram(VertexData v) {  // SV_POSITION Stands for System Value Position
                // The vertex program has to return the final coordinates of a vertex
                // out float3 localPosition adds an output parameter to the shader program
                Interpolators i;
                i.position = UnityObjectToClipPos(v.position); // mul(UNITY_MATRIX_MVP, position) Multiply the object-space position with Unity's model-view-projection matrix
                // i.uv = v.uv * _MainTex_ST.xy; + _MainTex_ST.zw  // Every vertex gets multiplied with the tiling vector (Scaling) and added with the offset vector(Translation)
                i.uv = TRANSFORM_TEX(v.uv, _MainTex);  // equivalent to the line above, using unitycg.cginc 
                i.uvSplat = v.uv;
                return i;
            }

            float4 MyFragmentProgram(Interpolators i) : SV_TARGET {
                // The fragment program is supposed to return am RGB value for one pixel
                // return float4(i.uv, 1, 1);
                // return tex2D(_MainTex, i.uv);  // Sample the texture at the object's uv coordinates
                float4 splat = tex2D(_MainTex, i.uvSplat);
                return
                    tex2D(_Texture1, i.uv) * splat.r +  // if the Splat texture is monochrome, any channel can be used.
                    tex2D(_Texture2, i.uv) * splat.g +
                    tex2D(_Texture3, i.uv) * splat.b +
                    tex2D(_Texture4, i.uv) * (1 - splat.r - splat.g - splat.b);  // 4th texture is derived by subtracting the other values
                    
                    ;

            }
            ENDCG
        }
    }
}