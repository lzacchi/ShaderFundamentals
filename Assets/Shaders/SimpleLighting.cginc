#if !defined(SIMPLE_LIGHTING)
#define SIMPLE_LIGHTING

#include "CGIncludes/UnityCG.cginc"
#include "CGIncludes/UnityPBSLighting.cginc"
#include "CGIncludes/AutoLight.cginc"


// Properties need to be declared inside the shaders in order to be accessed
float4 _Tint;
// float4 _SpecularTint;
float _Metallic;
sampler2D _MainTex, _DetailTex;
sampler2D _NormalMap, _DetailNormalMap;
float4 _MainTex_ST, _DetailTex_ST;// Also set automatically. ST stands for Scale Translation
float _Smoothness;
float _BumpScale, _DetailBumpScale;

struct VertexData {
    float4 position : POSITION;
    float3 normal : NORMAL;    // Unity's cube and sphere meshes contain normal data, which can be passed directly to the vertex shader.
    float4 tangent : TANGET;
    float2 uv : TEXCOORD0;
};

struct Interpolators {
    float4 position : SV_POSITION;
    float4 uv : TEXCOORD0;
    float3 normal : TEXCOORD1;

    #if defined(BINORMAL_PER_FRAGMENT)
    float4 tangent : TEXCOORD2;
    #else
    float3 tangent : TEXCOORD2;
    float3 binormal : TEXCOORD3;
    #endif

    float3 worldPos : TEXCOORD4;    // Required for specular highlights

    #if defined(VERTEXLIGHT_ON)
    float3 vertexLightColor : TEXCOORD5;
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

float3 CreateBinormal(float3 normal, float3 tangent, float binormalSign) {
    return cross(normal, tangent.xyz) * (binormalSign * unity_WorldTransformParams.w);
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

    #if defined(BINORMAL_PER_FRAGMENT)
    i.tangent = float4(UnityObjectToWorldDir(v.tangent.xyz), v.tangent.w);
    #else
    i.tangent = UnityObjectToWorldDir(v.tangent.xyz);
    i.binormal = CreateBinormal(i.normal, i.tangent, v.tangent.w);
    #endif
    // Of course, Unity has a function that implements that operation.
    i.uv.xy = TRANSFORM_TEX(v.uv, _MainTex);
    i.uv.zw = TRANSFORM_TEX(v.uv, _DetailTex);
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
    // float2 du = float2(_HeightMap_TexelSize.x * 0.5, 0);
    // float u1 = tex2D(_HeightMap, i.uv - du);
    // float u2 = tex2D(_HeightMap, i.uv + du);
    // float height_u = u2 - u1;
    // float3 tangent_u = float3(1, height_u, 0);

    // float2 dv = float2(0, _HeightMap_TexelSize.y * 0.5);
    // float v1 = tex2D(_HeightMap, i.uv - dv);
    // float v2 = tex2D(_HeightMap, i.uv + dv);
    // float height_v = v2 - v1;

    // float3 tanget_v = float3(0, height_v, 1);
    // i.normal = cross(tanget_v, tangent_u);
    // Unity's normal maps use DXT5nm by default, which means
    // the x component is stored in the a channel, and the y component
    // is stored in the g channel. The z component is not stored, so it needs
    // to be inferred. Since normals are unit vectors, the formula can be applied:
    // ||N|| = ||N|² = N²x + N²y + N²z = 1
    // Nz = sqrt(1 - N²x - N²y)
    // i.normal.xy = tex2D(_NormalMap, i.uv).wy * 2 - 1;
    // i.normal.xy *= _BumpScale;
    // i.normal.z = saturate(sqrt(1 - (dot(i.normal.xy, i.normal.xy))));
    // As usual, there is a UnityStandardUtils function that handles this:
    float3 main_normal = UnpackScaleNormal(tex2D(_NormalMap, i.uv.xy), _BumpScale);
    float3 detail_normal = UnpackScaleNormal(tex2D(_DetailNormalMap, i.uv.zw), _DetailBumpScale);
    // using the whiteout technique
    // i.normal = float3(main_normal.xy + detail_normal.xy, main_normal.z * detail_normal.z);
    // or by using Unity's own implementations:

    float3 tangent_space_normal = BlendNormals(main_normal, detail_normal);

    #if defined(BINORMAL_PER_FRAGMENT)
    float3 binormal = cross(i.normal, i.tangent.xyz) * (i.tangent.w * unity_WorldTransformParams.w);
    #else
    float3 binormal = i.binormal;
    #endif

    i.normal = normalize(tangent_space_normal.x * i.tangent + tangent_space_normal.y * binormal + tangent_space_normal.z * i.normal);

    i.normal = BlendNormals(main_normal, detail_normal);
    // Unity swaps the y and z coordinates on normal maps:
    i.normal = i.normal.xzy;
    // i.normal = normalize(i.normal);  // Unity's BlendNormals already normalizes the results


}

float4 MyFragmentProgram(Interpolators i) : SV_TARGET {
    // The fragment program is supposed to return an RGB value for one pixel
    InitializeFragmentNormal(i);

    // view direction can be found by subtracting the surface position from the camera position
    float3 viewDir = normalize(_WorldSpaceCameraPos - i.worldPos);

    // Albedo is a material's intrinsic color. The texture and tint can be used to represent it.
    // Subtracting specular tint from the albedo values guarantees that the sum of the reflected light is never greater than the receiving light
    float3 albedo = tex2D(_MainTex, i.uv.xy).rgb * _Tint.rgb;
    albedo *= tex2D(_DetailTex, i.uv.zw).rgb * unity_ColorSpaceDouble;
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