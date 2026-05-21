// Upgrade NOTE: replaced 'mul(UNITY_MATRIX_MVP,*)' with 'UnityObjectToClipPos(*)'

Shader "Custom/Simple Lighting Shader" {
    Properties {
        // Properties are defined as property_name(str, type)
        _Tint ("Tint", Color) =  (1, 1, 1, 1)
        _MainTex ("Albedo", 2D) = "white" {}
        [NoScaleOffset]
        _HeightMap ("Height Map", 2D) = "gray" {}
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

            // Target is used to instruct Unity to use the best BRDF PBS function
            #pragma target 3.0

            // Add vertex light support for base pass. Vertex Light is only supported for point light sources.
            #pragma multi_compile _ VERTEXLIGHT_ON

            // Shaders consist of 2 programs each:
            // The Vertex shader is responsible for processing the vertex data of a mesh
            // The Fragment shader is responsible for coloring individual pixels inside the mesh's triangles.


            #pragma vertex MyVertexProgram
            #pragma fragment MyFragmentProgram

            #define FORWARD_BASE_PASS


            #include "SimpleLighting.cginc"

            ENDCG
        }
        Pass {
            Tags { "LightMode" = "ForwardAdd" }            // Unity will use this pass to render the second light source
            Blend One One            // Additive blending, making sure both light sources are rendered.
            ZWrite Off            // There is no need to write to the depth buffer a second time
            CGPROGRAM

            #pragma target 3.0

            // Instructs unity to create different variants of the shader. In this case,
            // One for Directional lights and one for point lights
            // #pragma multi_compile DIRECTIONAL DIRECTIONAL_COOKIE POINT SPOT
            // Of course, we can use Unityt's pre-defined forwad add list:
            #pragma multi_compile_fwdadd

            #pragma vertex MyVertexProgram
            #pragma fragment MyFragmentProgram

            // #define POINT   // Instruct AutoLight to compute attenuation for point lights

            #include "SimpleLighting.cginc"

            ENDCG
        }
    }
}