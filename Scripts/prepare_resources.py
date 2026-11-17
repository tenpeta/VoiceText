#!/usr/bin/env python3
"""Precompile the base dictionary during development, never on a keystroke."""
from pathlib import Path
import fcntl
import shutil
import subprocess
ROOT = Path(__file__).resolve().parent.parent
(ROOT / "build").mkdir(exist_ok=True)
lock = (ROOT / "build/resources.lock").open("w")
fcntl.flock(lock, fcntl.LOCK_EX)
shared = ROOT / "build/RimeShared"
user = ROOT / "build/RimeDeployment"
# Recreate staging so resources from an older dictionary are not bundled.
if shared.exists():
    shutil.rmtree(shared)
shared.mkdir(parents=True, exist_ok=True)
user.mkdir(parents=True, exist_ok=True)
shutil.copytree(ROOT / "Resources/Rime/upstream", shared, dirs_exist_ok=True)
for source in (ROOT / "Resources/Rime").glob("*.yaml"):
    shutil.copy2(source, shared / source.name)
shutil.copytree(ROOT / "Resources/Rime/lua", shared / "lua", dirs_exist_ok=True)
subprocess.run([str(ROOT / "Vendor/bin/rime_deployer"), "--build", str(user), str(shared)], check=True)
output = user / "build"
if not all((output / name).exists() for name in ["voicetext_pinyin.schema.yaml", "voicetext_frost.table.bin", "melt_eng.table.bin"]):
    raise RuntimeError("Rime schema compilation failed")
# Remove only obsolete generated dictionary artifacts, never user learning data.
for source in output.glob("luna_pinyin.*.bin"):
    source.unlink()
shutil.copytree(output, shared / "build", dirs_exist_ok=True)
bundle = ROOT / "build/BundleSupport/Rime"
if bundle.exists():
    shutil.rmtree(bundle)
shutil.copytree(shared, bundle)
