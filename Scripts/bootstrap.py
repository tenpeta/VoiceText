#!/usr/bin/env python3
"""Download fixed upstream build inputs. Python is used only at build time."""
import hashlib
import fcntl
import json
from pathlib import Path
import shutil
import subprocess
import tarfile
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
VENDOR = ROOT / "Vendor"

def download(url, target, digest=None):
    target.parent.mkdir(parents=True, exist_ok=True)
    if not target.exists():
        print("Downloading", target.name, flush=True)
        request = urllib.request.Request(url, headers={"User-Agent": "VoiceText-build"})
        temporary = target.with_suffix(target.suffix + ".download")
        try:
            with urllib.request.urlopen(request, timeout=90) as source, temporary.open("wb") as output:
                shutil.copyfileobj(source, output)
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
    actual = hashlib.sha256(target.read_bytes()).hexdigest()
    if digest and actual != digest:
        raise RuntimeError(f"Checksum mismatch: {target}. Remove it and retry.")
    return actual

def main():
    complete = VENDOR / ".bootstrap-complete"
    complete.unlink(missing_ok=True)
    for name, digest, destination in [
        ("rime", "11d8dc663c6ec06d5ccb6111ba664a9e7b631b703ac6acd07cffbac664021850", VENDOR),
        ("rime-deps", "dfe6047e87be271963d7466bd1a6e3d9e660c30e5e73e4bb94e8782c0a6ac8df", VENDOR / "deps"),
    ]:
        archive = VENDOR / "archives" / f"{name}.tar.bz2"
        download(f"https://github.com/rime/librime/releases/download/1.17.0/{name}-33e7814-macOS-universal.tar.bz2", archive, digest)
        destination.mkdir(parents=True, exist_ok=True)
        # Archives are pinned by SHA-256 before extraction.
        with tarfile.open(archive) as package:
            package.extractall(destination, filter="data")
    for name in ["include", "lib", "bin"]:
        (VENDOR / name).mkdir(exist_ok=True)
    for source in (VENDOR / "dist/include").glob("*.h"):
        shutil.copy2(source, VENDOR / "include" / source.name)
    library = VENDOR / "lib/librime.1.dylib"
    # Ship arm64 core and only the Lua plugin used by candidate ranking.
    subprocess.run(["lipo", str(VENDOR / "dist/lib/librime.1.17.0.dylib"), "-thin", "arm64", "-output", str(library)], check=True)
    lua = VENDOR / "lib/librime-lua.dylib"
    subprocess.run(["lipo", str(VENDOR / "dist/lib/rime-plugins/librime-lua.dylib"), "-thin", "arm64", "-output", str(lua)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(lua)], check=True)
    alias = VENDOR / "lib/librime.dylib"
    alias.unlink(missing_ok=True)
    alias.symlink_to("librime.1.dylib")
    shutil.copy2(VENDOR / "dist/bin/rime_deployer", VENDOR / "bin/rime_deployer")
    # The deployer only needs the same bundled library; no Homebrew runtime paths.
    subprocess.run(["install_name_tool", "-add_rpath", "@loader_path/../lib", str(VENDOR / "bin/rime_deployer")], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(library)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(VENDOR / "bin/rime_deployer")], check=True)

    resources = ROOT / "Resources/Rime/upstream"
    (resources / "luna_pinyin.dict.yaml").unlink(missing_ok=True)
    notices = ROOT / "ThirdPartyNotices/upstream"
    manifest = []
    inputs = [
        ("lua/lua", "v5.4.8", "lua.h", notices / "Lua-5.4.8.LICENSE.h"),
        ("hchunhui/librime-lua", "ec52e48", "LICENSE", notices / "librime-lua.LICENSE"),

        ("rime/rime-essay", "054920de4f54c9e5994276a96a4fc2a35cb51aa3", "essay.txt", resources / "essay.txt"),
        ("rime/rime-essay", "054920de4f54c9e5994276a96a4fc2a35cb51aa3", "LICENSE", notices / "essay.LICENSE"),
        ("rime/librime", "33e78140250125871856cdc5b42ddc6a5fcd3cd4", "LICENSE", notices / "librime.LICENSE"),
        ("google/glog", "7b134a5c82c0c0b5698bb6bf7a835b230c5638e4", "COPYING", notices / "glog.LICENSE"),
        ("google/leveldb", "99b3c03b3284f5886f9ef9a4ef703d57373e61be", "LICENSE", notices / "leveldb.LICENSE"),
        ("s-yata/marisa-trie", "3e87d53b78e15f2f43783d5e376561a8c9722051", "COPYING.md", notices / "marisa.LICENSE"),
        ("BYVoid/OpenCC", "556ed22496d650bd0b13b6c163be9814637970ae", "LICENSE", notices / "OpenCC.LICENSE"),
        ("jbeder/yaml-cpp", "2f86d13775d119edbb69af52e5f566fd65c6953b", "LICENSE", notices / "yaml-cpp.LICENSE"),
    ]
    frost_revision = "af22941caec0fb7c052893e1bf439b79a94e5fb2"
    ice_revision = "99662ba01e3affa6a0f009174ca530b887bac3b6"
    for name in ["8105", "base", "ext", "others"]:
        path = f"cn_dicts/{name}.dict.yaml"
        inputs.append(("gaboolic/rime-frost", frost_revision, path, resources / path))
    for path in ["melt_eng.dict.yaml", "en_dicts/en.dict.yaml", "en_dicts/en_ext.dict.yaml"]:
        inputs.append(("iDvel/rime-ice", ice_revision, path, resources / path))
    inputs.extend([
        ("gaboolic/rime-frost", frost_revision, "LICENSE", notices / "rime-frost.LICENSE"),
        ("iDvel/rime-ice", ice_revision, "LICENSE", notices / "rime-ice.LICENSE"),
    ])
    for repo, revision, path, destination in inputs:
        url = f"https://raw.githubusercontent.com/{repo}/{revision}/{path}"
        digest = download(url, destination)
        manifest.append(dict(source=url, sha256=digest))
    gpl_url = "https://raw.githubusercontent.com/gcc-mirror/gcc/releases/gcc-14.2.0/COPYING3"
    manifest.append(dict(source=gpl_url, sha256=download(gpl_url, notices / "GPL-3.0.txt")))
    opencc = resources / "opencc"
    opencc.mkdir(parents=True, exist_ok=True)
    for name in ["t2s.json", "TSCharacters.ocd2", "TSPhrases.ocd2", "s2t.json", "STCharacters.ocd2", "STPhrases.ocd2"]:
        shutil.copy2(VENDOR / "deps/share/opencc" / name, opencc / name)
    notices.mkdir(parents=True, exist_ok=True)
    shutil.copy2(VENDOR / "deps/include/COPYING.darts-clone", notices / "darts-clone.LICENSE")
    (notices / "resources.json").write_text(json.dumps(manifest, indent=2) + "\n")
    complete.write_text("librime-1.17.0-frost-lua-1\n")
    print("librime 1.17.0 and base dictionaries are ready.")

if __name__ == "__main__":
    VENDOR.mkdir(parents=True, exist_ok=True)
    with (VENDOR / ".bootstrap.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        main()
