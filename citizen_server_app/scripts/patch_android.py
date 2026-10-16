"""Patch the `flutter create`-generated Android project for InfraVision Citizen.

Usage (from repo root, after `flutter create`):  python scripts/patch_android.py citizen_app
Sets applicationId com.infravision.citizen, minSdk 24, and adds only the needed permissions.
Idempotent: safe to run more than once.
"""
import pathlib
import re
import sys

APP_ID = "com.infravision.citizen"
PERMS = [
    "android.permission.INTERNET",
    "android.permission.CAMERA",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
]


def patch_manifest(text: str) -> str:
    for p in PERMS:
        if p not in text:
            text = re.sub(r"(<manifest[^>]*>)", rf'\1\n    <uses-permission android:name="{p}"/>', text, count=1)
    if "android.hardware.camera" not in text:
        text = re.sub(r"(<manifest[^>]*>)",
                      r'\1\n    <uses-feature android:name="android.hardware.camera" android:required="false"/>',
                      text, count=1)
    # Dev only: allows http://<laptop-ip>:8000. Remove for production (use HTTPS).
    if "usesCleartextTraffic" not in text:
        text = text.replace("<application", '<application android:usesCleartextTraffic="true"', 1)
    return text


def patch_gradle(text: str) -> str:
    text = re.sub(r'applicationId\s*=?\s*"[^"]*"', f'applicationId = "{APP_ID}"', text)
    text = re.sub(r"minSdk\s*=?\s*[\w.]+", "minSdk = 24", text)
    text = re.sub(r'namespace\s*=?\s*"[^"]*"', f'namespace = "{APP_ID}"', text)
    return text


def main(root: str):
    a = pathlib.Path(root) / "android" / "app"
    m = a / "src" / "main" / "AndroidManifest.xml"
    m.write_text(patch_manifest(m.read_text()))
    for name in ("build.gradle", "build.gradle.kts"):
        g = a / name
        if g.exists():
            g.write_text(patch_gradle(g.read_text()))
    print("patched", m)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "citizen_app")
