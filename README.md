
# RealityShaders

## About

*RealityShaders* is an HLSL shader overhaul for [Project Reality: Battlefield 2](https://www.realitymod.com/). *RealityShaders* introduces many graphical updates that did not make it into the Refactor 2 Engine.

*RealityShaders* also includes `.fxh` files that contain algorithms used in the collection.

## Features

### Shader Model 3.0

Shader Model 3.0 allows modders to add more grapical updates into the game, such as:

- 3D water and terrain
- High precision shading
- Linear lighting
- Procedural effects
- Soft shadows
- Sharper texture filtering
- Steep parallax mapping

### Distance-Based Fog

This fogging method eliminates "corner-peeking".

### Half-Lambert Lighting

[Valve Software's](https://advances.realtimerendering.com/s2006/Mitchell-ShadingInValvesSourceEngine.pdf) smoother version of the Lambertian Term used in lighting.

### Logarithmic Depth Buffer

Logarithmic depth buffering eliminates flickering within distant objects.

### Per-Pixel Lighting

Per-pixel lighting allows sharper lighting and smoother fogging.

### Modernized Post-Processing

This shader package includes updated thermal and suppression effects.

### Procedural Sampling

No more visible texture repetition in clouds and far-away terrain.

### Sharpened Filtering

Support for 16x anisotropic filtering.

## Coding Convention

Practice | Elements
-------- | --------
**ALLCAPS** | state parameters • system semantics
**ALL_CAPS** | preprocessor (macros and its arguments)
**_SnakeCase** | variables (uniform)
**SnakeCase** | method arguments • variables (global, local, textures, samplers)
**Snake_Case** | data subcatagory
**PREFIX_Data** | `struct` • `PixelShader` • `VertexShader`

## Acknowledgment

- [The Forgotten Hope Team](http://forgottenhope.warumdarum.de/)

    Major knowledge-base and inspiration.
