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
shared.mkdir(parents=True, exist_ok=True)
user.mkdir(parents=True, exist_ok=True)
shutil.copytree(ROOT / "Resources/Rime/upstream", shared, dirs_exist_ok=True)
for source in (ROOT / "Resources/Rime").glob("*.yaml"):
    shutil.copy2(source, shared / source.name)
subprocess.run([str(ROOT / "Vendor/bin/rime_deployer"), "--build", str(user), str(shared)], check=True)
output = user / "build"
if not (output / "voicetext_pinyin.schema.yaml").exists():
    raise RuntimeError("Rime schema compilation failed")
shutil.copytree(output, shared / "build", dirs_exist_ok=True)
shutil.copytree(shared, ROOT / "build/BundleSupport/Rime", dirs_exist_ok=True)
