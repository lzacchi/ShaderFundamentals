// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/Simple Shader" {
    Properties{
        _Tint ("Tint", Color) = (1,1,1,1)  // Property is defined as property_name(str, type)
        _MainTex("Texture", 2D) = "white" {}
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
            float4 _Tint;  
            sampler2D _MainTex;
            float4 _MainTex_ST;  // ST stands for Scale Translation

            struct Interpolators {
                float4 position: SV_POSITION;
                float2 uv: TEXCOORD0;
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
                return i;
            }

            float4 MyFragmentProgram(Interpolators i) : SV_TARGET {
                // The fragment program is supposed to return am RGB value for one pixel
                // return float4(i.uv, 1, 1);
                return tex2D(_MainTex, i.uv);  // Sample the texture at the object's uv coordinates
            }
            ENDCG
        }
    }
}