#!/usr/bin/env python3
"""Deterministic Xcode project generation without a package-manager dependency."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
objects = {}
def uid(key): return hashlib.sha1(key.encode()).hexdigest()[:24].upper()
def quote(value): return json.dumps(str(value))
def obj(key, body):
    identifier = uid(key)
    objects[identifier] = body
    return identifier
def array(items): return "(" + ", ".join(items) + ")"
def settings(values): return "{ " + " ".join(f'{key} = {quote(value)};' for key, value in values.items()) + " }"

def main():
    source_refs, build_sources = [], []
    files = sorted(list((ROOT / "Sources").rglob("*.swift")) + list((ROOT / "RimeBridge").glob("*.c")) + list((ROOT / "NativeSupport").glob("*.c")))
    for file in files:
        path = str(file.relative_to(ROOT))
        kind = "sourcecode.swift" if file.suffix == ".swift" else "sourcecode.c.c"
        ref = obj(path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(path)}; sourceTree = SOURCE_ROOT;')
        source_refs.append(ref)
        build_sources.append(obj("build:" + path, f"isa = PBXBuildFile; fileRef = {ref};"))
    resource_refs = []
    for path, kind in [("Resources/Info.plist", "text.plist.xml"), ("Resources/VoiceText.entitlements", "text.plist.entitlements"), ("README.md", "net.daringfireball.markdown")]:
        resource_refs.append(obj(path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(path)}; sourceTree = SOURCE_ROOT;'))
    packaged_refs = []
    resource_builds = []
    for path, kind in [("build/BundleSupport/Rime", "folder"), ("ThirdPartyNotices", "folder"), ("Resources/AppIcon.icns", "image.icns"), ("Resources/en.lproj", "folder"), ("Resources/InputSourceIcon.pdf", "image.pdf")]:
        ref = obj(path, f'isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(path)}; sourceTree = SOURCE_ROOT;')
        packaged_refs.append(ref)
        resource_builds.append(obj("resource:" + path, f'isa = PBXBuildFile; fileRef = {ref};'))
    lib = obj("librime", 'isa = PBXFileReference; lastKnownFileType = "compiled.mach-o.dylib"; path = Vendor/lib/librime.1.dylib; sourceTree = SOURCE_ROOT;')
    lua_lib = obj("lualib", 'isa = PBXFileReference; lastKnownFileType = "compiled.mach-o.dylib"; path = Vendor/lib/librime-lua.dylib; sourceTree = SOURCE_ROOT;')
    product = obj("product", 'isa = PBXFileReference; explicitFileType = wrapper.application; path = VoiceText.app; sourceTree = BUILT_PRODUCTS_DIR;')
    code = obj("codegroup", f'isa = PBXGroup; name = Sources; children = {array(source_refs)}; sourceTree = "<group>";')
    products = obj("products", f'isa = PBXGroup; name = Products; children = ({product}); sourceTree = "<group>";')
    group = obj("rootgroup", f'isa = PBXGroup; children = {array([code] + resource_refs + packaged_refs + [lib, lua_lib, products])}; sourceTree = "<group>";')
    sources = obj("sourcesphase", f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(build_sources)}; runOnlyForDeploymentPostprocessing = 0;')
    frameworks = obj("frameworksphase", 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    embed_ref = obj("embedlib", f'isa = PBXBuildFile; fileRef = {lib}; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy);}};')
    lua_embed = obj("embedlua", f'isa = PBXBuildFile; fileRef = {lua_lib}; settings = {{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy);}};')
    embed = obj("embedphase", f'isa = PBXCopyFilesBuildPhase; buildActionMask = 2147483647; dstPath = ""; dstSubfolderSpec = 10; files = ({embed_ref}, {lua_embed}); name = "Embed librime"; runOnlyForDeploymentPostprocessing = 0;')
    resources = obj("resourcesphase", f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resource_builds)}; runOnlyForDeploymentPostprocessing = 0;')
    # Ad hoc signatures have no Team ID and cannot satisfy hardened library validation.
    # Developer ID distribution enables the runtime in package.sh and signs both binaries.
    common = dict(ARCHS="arm64", MACOSX_DEPLOYMENT_TARGET="14.0", SDKROOT="macosx", SWIFT_VERSION="5.0", CLANG_ENABLE_MODULES="YES", CLANG_ENABLE_OBJC_ARC="YES", ENABLE_USER_SCRIPT_SANDBOXING="NO", ENABLE_HARDENED_RUNTIME="NO", CODE_SIGN_STYLE="Manual", CODE_SIGN_IDENTITY="-", CODE_SIGN_ENTITLEMENTS="Resources/VoiceText.entitlements", PRODUCT_BUNDLE_IDENTIFIER="im.voicetext.inputmethod.VoiceText", PRODUCT_NAME="VoiceText", INFOPLIST_FILE="Resources/Info.plist", GENERATE_INFOPLIST_FILE="NO", SWIFT_OBJC_BRIDGING_HEADER="RimeBridge/VoiceText-Bridging-Header.h", HEADER_SEARCH_PATHS="$(SRCROOT)/Vendor/include $(SRCROOT)/RimeBridge $(SRCROOT)/NativeSupport/include", LIBRARY_SEARCH_PATHS="$(SRCROOT)/Vendor/lib", OTHER_LDFLAGS="$(inherited) -lrime -lc++ -lz -lsqlite3", SWIFT_INCLUDE_PATHS="$(SRCROOT)/NativeSupport/include", LD_RUNPATH_SEARCH_PATHS="$(inherited) @executable_path/../Frameworks", COMBINE_HIDPI_IMAGES="YES")
    configs = []
    for name in ["Debug", "Release"]:
        values = dict(common, SWIFT_OPTIMIZATION_LEVEL="-Onone" if name == "Debug" else "-O", GCC_OPTIMIZATION_LEVEL="0" if name == "Debug" else "s", DEBUG_INFORMATION_FORMAT="dwarf" if name == "Debug" else "dwarf-with-dsym")
        configs.append(obj("targetconfig" + name, f'isa = XCBuildConfiguration; buildSettings = {settings(values)}; name = {name};'))
    config_list = obj("targetconfigs", f'isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    target = obj("target", f'isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = {array([sources, frameworks, embed, resources])}; buildRules = (); dependencies = (); name = VoiceText; productName = VoiceText; productReference = {product}; productType = "com.apple.product-type.application";')
    pconfigs = [obj("project" + name, f'isa = XCBuildConfiguration; buildSettings = {{}}; name = {name};') for name in ["Debug", "Release"]]
    plist = obj("projectconfigs", f'isa = XCConfigurationList; buildConfigurations = {array(pconfigs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
    project = obj("project", f'isa = PBXProject; attributes = {{LastUpgradeCheck = 1600;}}; buildConfigurationList = {plist}; compatibilityVersion = "Xcode 14.0"; developmentRegion = zh_CN; hasScannedForEncodings = 0; knownRegions = (zh_CN, en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target});')
    directory = ROOT / "VoiceText.xcodeproj"
    directory.mkdir(exist_ok=True)
    text = "// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n"
    text += "\n".join(f"{key} = {{ {body} }};" for key, body in objects.items())
    (directory / "project.pbxproj").write_text(text + f"\n}}; rootObject = {project}; }}\n")
    schemes = directory / "xcshareddata/xcschemes"; schemes.mkdir(parents=True, exist_ok=True)
    (schemes / "VoiceText.xcscheme").write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="VoiceText.app" BlueprintName="VoiceText" ReferencedContainer="container:VoiceText.xcodeproj"/></BuildActionEntry></BuildActionEntries></BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0"><BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{target}" BuildableName="VoiceText.app" BlueprintName="VoiceText" ReferencedContainer="container:VoiceText.xcodeproj"/></BuildableProductRunnable><CommandLineArguments><CommandLineArgument argument="--settings" isEnabled="YES"/></CommandLineArguments></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"/>
  <AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')

if __name__ == "__main__": main()
