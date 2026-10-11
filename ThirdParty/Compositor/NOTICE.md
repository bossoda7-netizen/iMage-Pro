# Compositor code incorporated into Image Pro

Upstream: https://github.com/robbietilton/Compositor
Revision: 11d8d7a50992b24fd9a760a1c13b1c01b70aaf30
Copyright (c) 2026 Wonder Assembly LLC
License: MIT; full text in LICENSE and the distributed application's ThirdPartyLicenses.txt.

Incorporated and adapted sources:

- Rendering/HealPixels.c and HealPixels.h: spot-healing patch search, membrane blending, texture generation.
- Rendering/MetalWarp.swift: Metal smudge, carried brush colors, liquify displacement field and sampling.
- Document/SmudgeLiquify.swift: continuous dab spacing, CPU smudge and push fallback.
- Document/LayerTransform.swift: shared handle-resize geometry used by the crop tool.
- Document/Crop.swift: crop creation, symmetric crop, resize and snap geometry.
- Document/TypeTool.swift and Rendering/InlineTextEditor.swift: point/paragraph text creation, size measurement, native editing and tracking/leading keyboard behavior adapted to our text model; translucent selection layout.

Integration uses Image Pro's existing project model, rendering, layer effects, masks, history, inline NSTextView and persistence. Crop, healing and smudge replace the corresponding Image Pro tools; liquify push is in Retouch and text editing uses the existing Text entry. The original Image Pro move and clone tools remain. There is no separate test category. It does not adopt Compositor's EditorSession, project file format, complete UI, Sparkle updater or deployment requirements.
