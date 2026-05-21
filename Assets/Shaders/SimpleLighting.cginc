#if !defined(SIMPLE_LIGHTING)
#define SIMPLE_LIGHTING

#include "CGIncludes/UnityCG.cginc"
#include "CGIncludes/UnityPBSLighting.cginc"
#include "CGIncludes/AutoLight.cginc"


// Properties need to be declared inside the shaders in order to be accessed
float4 _Tint;
// float4 _SpecularTint;
float _Metallic;
sampler2D _MainTex;
sampler2D _HeightMap;
float4 _HeightMap_TexelSize;// Automatically set by Unity
float4 _MainTex_ST;// Also set automatically. ST stands for Scale Translation
float _Smoothness;

struct VertexData {
    float4 position : POSITION;
    float3 normal : NORMAL;    // Unity's cube and sphere meshes contain normal data, which can be passed directly to the vertex shader.
    float2 uv : TEXCOORD0;
};

struct Interpolators {
    float4 position : SV_POSITION;
    float2 uv : TEXCOORD0;
    float3 normal : TEXCOORD1;
    float3 worldPos : TEXCOORD2;    // Required for specular highlights

    #if defined(VERTEXLIGHT_ON)
    float3 vertexLightColor : TEXCOORD3;
    #endif
};

void ComputeVertexLightColor(inout Interpolators i) {
    // inout Interpolators i: It both reads from and writes to i
    #if defined(VERTEXLIGHT_ON)
    // float3 lightPos = float3(unity_4LightPosX0.x, unity_4LightPosX0.y, unity_4LightPosX0.z);
    // UNITY_LIGHT_ATTENUATION macro cannot be used, so the 1/1+r^2 formula is reintroduced.
    // Unity provides a unity_4LightAtten0, which factors that help approximate the attenuation of
    // pixel lights. So the formula becomes 1/1+r^2*a
    // float3 lightVector = lightPos - i.worldPos;
    // float3 lightDir = normalize(lightVector);
    // float ndotl = DotClamped(i.normal, lightDir);
    // float attenuation = 1 / (1 + dot(lightVector, lightVector) * unity_4LightAtten0);
    // i.vertexLightColor = unity_LightColor[0].rgb * ndotl * attenuation;

    // The cpde above computes the vertex light for an individual source.
    // Unity supports up to 4 vertex lights, so we can use Unity's Shade4PointLights, which
    // computes and adds all of the sources
    i.vertexLightColor = Shade4PointLights(unity_4LightPosX0, unity_4LightPosY0, unity_4LightPosZ0, unity_LightColor[0].rgb, unity_LightColor[1].rgb, unity_LightColor[2].rgb, unity_LightColor[3].rgb, unity_4LightAtten0, i.worldPos, i.normal);
    #endif

}

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
    ComputeVertexLightColor(i);
    return i;
}

UnityLight CreateLight(Interpolators i) {
    // UnityLightingCommon provies a struct which Unity shaders use to pass light data
    UnityLight light;

    // Treat direction differently based on light type (defined in the shader variants)
    #if defined(POINT) || defined(POINT_COOKIE) || defined(SPOT)
    light.dir = normalize(_WorldSpaceLightPos0.xyz - i.worldPos);
    #else    // DIRECTIONAL
    light.dir = _WorldSpaceLightPos0.xyz;
    #endif
    // Compute attenuation
    // The light source acts as a sphere surface, and as such the attenuation (or photon density)
    // can be interpreted as 1/(surface area). Surface area of a sphere is 4*pi*r^2
    // The 4*pi can be ignored if it's assumed to be factored into the light's intensity.
    // So attenuation can be calculated as 1/r^2, where r is the light's distance
    // If the distance approaches zero, intensity tends to infinity so it's countered by
    // computing 1/(1+r^2)
    // float3 lightVector = _WorldSpaceLightPos0.xyz - i.worldPos;
    // float attenuation = 1 / (1 + dot(lightVector, lightVector));

    // Unsurprisingly, Unity has a macro that deals with all of the above:
    UNITY_LIGHT_ATTENUATION(attenuation, 0, i.worldPos);

    light.color = _LightColor0.rgb * attenuation;
    light.ndotl = DotClamped(i.normal, light.dir);

    return light;
}

UnityIndirect CreateIndirectLight(Interpolators i) {
    // It also provides a structure for handling indirect lights, with values for diffuse and specular
    UnityIndirect indirectLight;
    indirectLight.diffuse = 0;
    indirectLight.specular = 0;

    // In the fragment program, the vertex light color needs to be added to all other computed lights.
    // As such the vertex light can be treated as indirect lighting.
    #if defined(VERTEXLIGHT_ON)
    indirectLight.diffuse = i.vertexLightColor;
    #endif

    #if defined(FORWARD_BASE_PASS)
    // On the base pass, include Unity's spherical hamornics approximation into indirect light calculation
    indirectLight.diffuse += max(0, ShadeSH9(float4(i.normal, 1)));
    #endif
    return indirectLight;
}

void InitializeFragmentNormal(inout Interpolators i) {
    // Approximate the slope of the height map using texel size;
    float2 delta = float2(_HeightMap_TexelSize.x, 0);
    float height_sample1 = tex2D(_HeightMap, i.uv);
    float height_sample2 = tex2D(_HeightMap, i.uv + delta);
    float height = height_sample1 - height_sample2;
    i.normal = float3(height, 1, 0);
    i.normal = normalize(i.normal);
}

float4 MyFragmentProgram(Interpolators i) : SV_TARGET {
    // The fragment program is supposed to return an RGB value for one pixel
    InitializeFragmentNormal(i);

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

    return UNITY_BRDF_PBS(albedo, specularTint, oneMinusReflectivity, _Smoothness, i.normal, viewDir, CreateLight(i), CreateIndirectLight(i));
}
#endif