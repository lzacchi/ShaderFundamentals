// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/Simple Lighting Shader" {
    Properties {
        // Properties are defined as property_name(str, type)
        _Tint ("Tint", Color) =  (1, 1, 1, 1)
        _MainTex ("Albedo", 2D) = "white" {}
        // _SpecularTint ("Speculat Tint", Color) =  (0.5, 0.5, 0.5, 0.5)
        _Smoothness ("Smoothness", Range(0,1)) = 0.5
        [Gamma]
        _Metallic ("Metallic", Range(0, 1)) = 0
    }

    Subshader {
        // A shader can have multiple subshaders
        Pass {
            Tags { "LightMode" = "ForwardBase" }            // First pass when using Forward Rendering. It gives access to the main directional light
            // Each subshader can have multiple passes
            CGPROGRAM
            
            // Target is set to 3.0 to make sure Unity selects the best BRDF function
            #pragma target 3.0
            
            // Shaders consist of 2 programs each:
            // The Vertex shader is responsible for processing the vertex data of a mesh
            // The Fragment shader is responsible for coloring individual pixels inside the mesh's triangles.
            
            #pragma vertex MyVertexProgram
            #pragma fragment MyFragmentProgram

            #include "CGIncludes/UnityCG.cginc"
            // #include "CGIncludes/UnityStandardBRDF.cginc"
            // #include "CGIncludes/UnityStandardUtils.cginc"
            #include "CGIncludes/UnityPBSLighting.cginc"


            // Properties need to be declared inside the shaders in order to be accessed
            float4 _Tint;
            // float4 _SpecularTint;
            float _Metallic;
            sampler2D _MainTex;
            float4 _MainTex_ST;            // ST stands for Scale Translation
            float _Smoothness;

            struct VertexData {
                float4 position : POSITION;
                float3 normal : NORMAL;                // Unity's cube and sphere meshes contain normal data, which can be passed directly to the vertex shader.
                float2 uv : TEXCOORD0;
            };

            struct Interpolators {
                float4 position : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : TEXCOORD1;
                float3 worldPos : TEXCOORD2;                // Required for specular highlights
            };

            Interpolators MyVertexProgram(VertexData v) {
                // SV_POSITION Stands for System Value Position
                // The vertex program has to return the final coordinates of a vertex
                // out float3 localPosition adds an output parameter to the shader program
                Interpolators i;
                i.position = UnityObjectToClipPos(v.position);
                i.worldPos = mul(unity_ObjectToWorld, v.position);
                // mul(UNITY_MATRIX_MVP, position) Multiply the object-space position with Unity's model-view-projection matrix
                // i.uv = v.uv * _MainTex_ST.xy; + _MainTex_ST.zw  // Every vertex gets multiplied with the tiling vector (Scaling) and added with the offset vector(Translation)
                // i.normal = mul(unity_ObjectToWorld, float4(v.normal, 0));           // unity_ObjectToWorld is the 4x4 object-to-world matrix. By multiplying this matrix with the vertex normal,
                // we can transform it to world space. The fourth homogenous coordinate is zero since it's a direction.
                // i.normal = mul(transpose((float3x3)unity_ObjectToWorld), v.normal); // Alternatively, we can multiply the 3x3 part of the matrix.
                // The matrix is transposed, because the scaling transformation should be inverted to preserve the correct normal vectors.
                i.normal = UnityObjectToWorldNormal(v.normal);
                // Of course, Unity has a function that implements that operation.
                i.uv = TRANSFORM_TEX(v.uv, _MainTex);
                // equivalent to the line above, using unitycg.cginc
                return i;
            }

            float4 MyFragmentProgram(Interpolators i) : SV_TARGET {
                // The fragment program is supposed to return an RGB value for one pixel

                // the transformation scaled the normals, so they need to be normalized.
                i.normal = normalize(i.normal);

                float3 lightDir = _WorldSpaceLightPos0.xyz;
                float3 lightColor = _LightColor0.rgb;

                // view direction can be found by subtracting the surface position from the camera position
                float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);

                // Albedo is a material's intrinsic color. The texture and tint can be used to represent it.
                // Subtracting specular tint from the albedo values guarantees that the sum of the reflected light is never greater than the receiving light
                float3 albedo = tex2D(_MainTex, i.uv).rgb * _Tint.rgb;
                float3 specularTint = albedo * _Metallic;
                float oneMinusReflectivity = 1 - _Metallic;

                // float maxComponent = max(specularTint.r, max(specularTint.g, specularTint.b));
                // albedo *= 1 - maxComponent; // Unity has a function that implements the energy conservation:
                // albedo = EnergyConservationBetweenDiffuseAndSpecular(albedo, specularTint.rgb, oneMinusReflectivity);

                // albedo = DiffuseAndSpecularFromMetallic(albedo, _Metallic, specularTint, oneMinusReflectivity);

                // float3 diffuse = albedo * lightColor * DotClamped(lightDir, i.normal);

                // Blinn-Phong model for reflection, using a vector halfway between the light direction and the view direction
                // float3 halfVector = normalize(lightDir + viewDir);
                // float3 specular = specularTint.rgb * lightColor * pow(DotClamped(halfVector, i.normal), _Smoothness * 100);
                // return float4(diffuse + specular, 1);

                // UnityLightingCommon provies a struct which Unity shaders use to pass light data
                UnityLight light;
                light.color = lightColor;
                light.dir   = lightDir;
                light.ndotl = DotClamped(i.normal, lightDir);

                // It also provides a structure for handling indirect lights, with values for diffuse and specular
                UnityIndirect indirectLight;
                indirectLight.diffuse  = 0;
                indirectLight.specular = 0;

                return UNITY_BRDF_PBS(
                    albedo, specularTint, 
                    oneMinusReflectivity, 
                    _Smoothness, 
                    i.normal, viewDir,
                    light, indirectLight
                );
            }
            ENDCG
        }
    }
}