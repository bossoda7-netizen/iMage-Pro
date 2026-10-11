#!/usr/bin/env python3
"""Verify the notices in the actual app, including the copy displayed in About."""
from pathlib import Path
import sys
import hashlib

root = Path(__file__).resolve().parent.parent
app = Path(sys.argv[1])
resources = app / "Contents/Resources"
canonical = root / "Sources/ImagePro/Legal/ThirdPartyLicenses.txt"


def require(condition, message):
    if not condition:
        raise SystemExit("Distribution verification failed: " + message)


for relative in ["ThirdPartyLicenses.txt", "ImagePro_ImagePro.bundle/Legal/ThirdPartyLicenses.txt"]:
    bundled = resources / relative
    require(bundled.is_file(), "missing " + relative)
    require(bundled.read_bytes() == canonical.read_bytes(), "stale " + relative)

text = canonical.read_text(encoding="utf-8")
for name in ["LICENSE", "NOTICE.md"]:
    source = root / "ThirdParty/Compositor" / name
    bundled = resources / "Licenses/Compositor" / name
    require(bundled.is_file(), "missing Compositor " + name)
    require(bundled.read_bytes() == source.read_bytes(), "modified Compositor " + name)
require((root / "ThirdParty/Compositor/LICENSE").read_text().strip() in text,
        "combined notice omits the full Compositor license")
font_license = root / "Sources/ImagePro/Resources/Fonts/LICENSE.txt"
require(font_license.read_text().strip() in text, "combined notice omits the font license")
require((resources / "Fonts/LICENSE.txt").read_bytes() == font_license.read_bytes(),
        "font license missing or modified")
require(not (resources / "Demo.jpg").exists(), "unlicensed unused demo image is still bundled")
runtime = app / "Contents/Frameworks/libonnxruntime.1.30.0.dylib"
require(runtime.is_file(), "bundled ONNX Runtime is missing")
require((resources / "PrivacyInfo.xcprivacy").is_file(), "PrivacyInfo.xcprivacy is missing")
model = resources / "ImagePro_ImagePro.bundle/InpaintingModels/migan_pipeline_v2.onnx"
require(model.is_file(), "bundled MI-GAN model is missing")
require(hashlib.sha256(model.read_bytes()).hexdigest() ==
        "6f1f3530a1a2324b19752018ce756088b07973cda8d7d890034ace5c8a48c40b",
        "MI-GAN model checksum mismatch")
for relative in [
    "Licenses/MI-GAN/LICENSE", "Licenses/MI-GAN/LICENSE-WEIGHTS",
    "Licenses/ONNXRuntime/LICENSE", "Licenses/ONNXRuntime/ThirdPartyNotices.txt",
]:
    bundled = resources / relative
    source = root / "ThirdParty" / relative.removeprefix("Licenses/")
    require(bundled.is_file(), "missing " + relative)
    require(bundled.read_bytes() == source.read_bytes(), "modified " + relative)
    require(source.read_text().strip() in text, "combined notice omits " + relative)
require(not (resources / "Licenses/OpenCV").exists(), "removed repair dependency is still bundled")
print("Verified distribution notices and resource exclusions: " + str(app))
