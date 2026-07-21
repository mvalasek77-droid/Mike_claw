#!/usr/bin/env python3
"""Generate ScreenshotStudio.xcodeproj from the source tree.

This is a small, dependency-free stand-in for XcodeGen so the project file can
be regenerated in any environment (CI, Linux, a fresh clone) without extra
tooling. It walks the source folders, builds the PBX object graph with
deterministic identifiers, and writes a `project.pbxproj` (objectVersion 56,
readable by Xcode 14–16+)
plus the shared scheme and workspace.

`project.yml` remains the canonical spec; running `xcodegen generate` produces
an equivalent project. This script exists so a checkout is buildable even when
xcodegen isn't installed.

Usage:  python3 Scripts/generate_xcodeproj.py
"""
from __future__ import annotations
import hashlib
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
APP = "ScreenshotStudio"
TESTS = "ScreenshotStudioTests"
PROJ_DIR = os.path.join(ROOT, f"{APP}.xcodeproj")


def uid(key: str) -> str:
    return hashlib.md5(key.encode()).hexdigest()[:24].upper()


def walk_sources(folder: str):
    """Return (swift_files, resource_files) as repo-root-relative paths."""
    swift, resources = [], []
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, folder)):
        # Treat asset catalogs as opaque folder references.
        if dirpath.endswith(".xcassets"):
            dirnames[:] = []
            continue
        dirnames.sort()
        for name in sorted(filenames):
            full = os.path.join(dirpath, name)
            rel = os.path.relpath(full, ROOT)
            if name.endswith(".swift"):
                swift.append(rel)
            elif name == "PrivacyInfo.xcprivacy":
                resources.append(rel)
        for d in list(dirnames):
            if d.endswith(".xcassets"):
                rel = os.path.relpath(os.path.join(dirpath, d), ROOT)
                resources.append(rel)
    swift.sort()
    resources.sort()
    return swift, resources


def file_type(path: str) -> str:
    if path.endswith(".swift"):
        return "sourcecode.swift"
    if path.endswith(".xcassets"):
        return "folder.assetcatalog"
    if path.endswith(".plist"):
        return "text.plist.xml"
    if path.endswith(".xcprivacy"):
        return "text.plist.xml"
    return "text"


class Project:
    def __init__(self):
        self.objects: list[tuple[str, str]] = []  # (uid, body)

    def add(self, key: str, body: str) -> str:
        u = uid(key)
        self.objects.append((u, body))
        return u


def build():
    app_swift, app_res = walk_sources(APP)
    test_swift, _ = walk_sources(TESTS)
    info_plist = f"{APP}/Resources/Info.plist"

    p = Project()

    # ---- File references -------------------------------------------------
    fileref = {}  # rel path -> uid

    def add_fileref(rel: str) -> str:
        # Path is the *basename*; the enclosing group hierarchy supplies the
        # directory, so Xcode resolves the on-disk location correctly.
        name = os.path.basename(rel)
        u = p.add(f"fileref:{rel}",
                  f'{{isa = PBXFileReference; lastKnownFileType = {file_type(rel)}; '
                  f'path = "{name}"; sourceTree = "<group>"; }}')
        fileref[rel] = u
        return u

    for rel in app_swift + app_res + test_swift + [info_plist]:
        add_fileref(rel)

    app_product = p.add("product:app",
                        f'{{isa = PBXFileReference; explicitFileType = wrapper.application; '
                        f'includeInIndex = 0; path = "{APP}.app"; sourceTree = BUILT_PRODUCTS_DIR; }}')
    test_product = p.add("product:tests",
                         f'{{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; '
                         f'includeInIndex = 0; path = "{TESTS}.xctest"; sourceTree = BUILT_PRODUCTS_DIR; }}')

    # ---- Build files -----------------------------------------------------
    def build_file(rel: str, phase: str) -> str:
        name = os.path.basename(rel)
        return p.add(f"bf:{phase}:{rel}",
                     f'{{isa = PBXBuildFile; fileRef = {fileref[rel]} /* {name} */; }}')

    app_source_bf = [build_file(r, "appsrc") for r in app_swift]
    app_res_bf = [build_file(r, "appres") for r in app_res]
    test_source_bf = [build_file(r, "testsrc") for r in test_swift]

    # ---- Groups (mirror the directory tree) ------------------------------
    def make_group(abs_dir: str, name: str | None) -> str:
        entries = []
        try:
            names = sorted(os.listdir(abs_dir))
        except FileNotFoundError:
            names = []
        # Subdirectories first (asset catalogs are leaf file refs, not groups).
        for n in names:
            full = os.path.join(abs_dir, n)
            if os.path.isdir(full) and not n.endswith(".xcassets"):
                child = make_group(full, n)
                entries.append((n, child))
        # Then files (and asset-catalog folder refs) we know about.
        for n in names:
            full = os.path.join(abs_dir, n)
            rel = os.path.relpath(full, ROOT)
            if rel in fileref:
                entries.append((n, fileref[rel]))
        entries.sort(key=lambda e: e[0].lower())
        children = "\n".join(f"\t\t\t\t{u} /* {nm} */," for nm, u in entries)
        path_line = f'path = "{name}"; ' if name else ""
        body = (f'{{isa = PBXGroup; children = (\n{children}\n\t\t\t); '
                f'{path_line}sourceTree = "<group>"; }}')
        return p.add(f"group:{abs_dir}", body)

    app_group = make_group(os.path.join(ROOT, APP), APP)
    test_group = make_group(os.path.join(ROOT, TESTS), TESTS)

    products_group = p.add("group:products",
                           f'{{isa = PBXGroup; children = (\n'
                           f'\t\t\t\t{app_product} /* {APP}.app */,\n'
                           f'\t\t\t\t{test_product} /* {TESTS}.xctest */,\n'
                           f'\t\t\t); name = Products; sourceTree = "<group>"; }}')

    main_group = p.add("group:main",
                       f'{{isa = PBXGroup; children = (\n'
                       f'\t\t\t\t{app_group} /* {APP} */,\n'
                       f'\t\t\t\t{test_group} /* {TESTS} */,\n'
                       f'\t\t\t\t{products_group} /* Products */,\n'
                       f'\t\t\t); sourceTree = "<group>"; }}')

    # ---- Build phases ----------------------------------------------------
    def phase(key: str, isa: str, files: list[str], extra: str = "") -> str:
        listing = "\n".join(f"\t\t\t\t{u}," for u in files)
        return p.add(key,
                     f'{{isa = {isa}; buildActionMask = 2147483647; files = (\n'
                     f'{listing}\n\t\t\t); {extra}runOnlyForDeploymentPostprocessing = 0; }}')

    app_sources_phase = phase("phase:appsrc", "PBXSourcesBuildPhase", app_source_bf)
    app_res_phase = phase("phase:appres", "PBXResourcesBuildPhase", app_res_bf)
    test_sources_phase = phase("phase:testsrc", "PBXSourcesBuildPhase", test_source_bf)

    # ---- Build configurations -------------------------------------------
    def config(key: str, name: str, settings: dict) -> str:
        lines = "\n".join(f"\t\t\t\t{k} = {v};" for k, v in settings.items())
        return p.add(key, f'{{isa = XCBuildConfiguration; buildSettings = {{\n{lines}\n\t\t\t}}; name = {name}; }}')

    project_common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ANALYZER_NONNULL": "YES",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "CLANG_WARN_BOOL_CONVERSION": "YES",
        "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES",
        "CLANG_WARN_EMPTY_BODY": "YES",
        "CLANG_WARN_INFINITE_RECURSION": "YES",
        "CLANG_WARN_UNREACHABLE_CODE": "YES",
        "ENABLE_STRICT_OBJC_MSGSEND": "YES",
        "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        "GCC_NO_COMMON_BLOCKS": "YES",
        "GCC_WARN_ABOUT_RETURN_TYPE": "YES_ERROR",
        "GCC_WARN_UNUSED_FUNCTION": "YES",
        "GCC_WARN_UNUSED_VARIABLE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.0",
        "DEVELOPMENT_TEAM": "UDM4W27W9V",
    }
    proj_debug = config("cfg:proj:debug", "Debug", {
        **project_common,
        "DEBUG_INFORMATION_FORMAT": "dwarf",
        "ENABLE_TESTABILITY": "YES",
        "GCC_OPTIMIZATION_LEVEL": "0",
        "GCC_PREPROCESSOR_DEFINITIONS": '("$(inherited)", "DEBUG=1", )',
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
        "ONLY_ACTIVE_ARCH": "YES",
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "SWIFT_OPTIMIZATION_LEVEL": '"-Onone"',
    })
    proj_release = config("cfg:proj:release", "Release", {
        **project_common,
        "DEBUG_INFORMATION_FORMAT": '"dwarf-with-dsym"',
        "ENABLE_NS_ASSERTIONS": "NO",
        "MTL_ENABLE_DEBUG_INFO": "NO",
        "SWIFT_COMPILATION_MODE": "wholemodule",
        "SWIFT_OPTIMIZATION_LEVEL": '"-O"',
    })

    app_common = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "12",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": f"{APP}/Resources/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": '("$(inherited)", "@executable_path/Frameworks", )',
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.valasek.screenshotstudio",
        "PRODUCT_NAME": APP,
        "SWIFT_EMIT_LOC_STRINGS": "YES",
        "TARGETED_DEVICE_FAMILY": '"1,2"',
    }
    app_debug = config("cfg:app:debug", "Debug", app_common)
    app_release = config("cfg:app:release", "Release", app_common)

    test_common = {
        "BUNDLE_LOADER": '"$(TEST_HOST)"',
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "YES",
        "MARKETING_VERSION": "1.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.valasek.screenshotstudio.tests",
        "PRODUCT_NAME": '"$(TARGET_NAME)"',
        "TARGETED_DEVICE_FAMILY": '"1,2"',
        "TEST_HOST": f'"$(BUILT_PRODUCTS_DIR)/{APP}.app/{APP}"',
    }
    test_debug = config("cfg:test:debug", "Debug", test_common)
    test_release = config("cfg:test:release", "Release", test_common)

    def cfg_list(key: str, debug: str, release: str) -> str:
        return p.add(key,
                     f'{{isa = XCConfigurationList; buildConfigurations = (\n'
                     f'\t\t\t\t{debug} /* Debug */,\n\t\t\t\t{release} /* Release */,\n'
                     f'\t\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; }}')

    proj_cfg_list = cfg_list("cfglist:proj", proj_debug, proj_release)
    app_cfg_list = cfg_list("cfglist:app", app_debug, app_release)
    test_cfg_list = cfg_list("cfglist:test", test_debug, test_release)

    # ---- Targets ---------------------------------------------------------
    app_target = uid("target:app")
    test_target = uid("target:tests")

    # tests depend on the app
    container_proxy = p.add("proxy:app",
                            f'{{isa = PBXContainerItemProxy; containerPortal = {uid("project")} /* Project object */; '
                            f'proxyType = 1; remoteGlobalIDString = {app_target}; remoteInfo = {APP}; }}')
    target_dep = p.add("dep:tests->app",
                       f'{{isa = PBXTargetDependency; target = {app_target} /* {APP} */; '
                       f'targetProxy = {container_proxy} /* PBXContainerItemProxy */; }}')

    p.add("target:app",
          f'{{isa = PBXNativeTarget; buildConfigurationList = {app_cfg_list} /* Build configuration list for PBXNativeTarget "{APP}" */; '
          f'buildPhases = (\n\t\t\t\t{app_sources_phase} /* Sources */,\n\t\t\t\t{app_res_phase} /* Resources */,\n\t\t\t); '
          f'buildRules = (\n\t\t\t); dependencies = (\n\t\t\t); name = {APP}; '
          f'productName = {APP}; productReference = {app_product} /* {APP}.app */; '
          f'productType = "com.apple.product-type.application"; }}')

    p.add("target:tests",
          f'{{isa = PBXNativeTarget; buildConfigurationList = {test_cfg_list} /* Build configuration list for PBXNativeTarget "{TESTS}" */; '
          f'buildPhases = (\n\t\t\t\t{test_sources_phase} /* Sources */,\n\t\t\t); '
          f'buildRules = (\n\t\t\t); dependencies = (\n\t\t\t\t{target_dep} /* PBXTargetDependency */,\n\t\t\t); name = {TESTS}; '
          f'productName = {TESTS}; productReference = {test_product} /* {TESTS}.xctest */; '
          f'productType = "com.apple.product-type.bundle.unit-test"; }}')

    # ---- Project object --------------------------------------------------
    p.add("project",
          f'{{isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 1600; '
          f'TargetAttributes = {{ {app_target} = {{ ProvisioningStyle = Automatic; }}; '
          f'{test_target} = {{ ProvisioningStyle = Automatic; TestTargetID = {app_target}; }}; }}; }}; '
          f'buildConfigurationList = {proj_cfg_list} /* Build configuration list for PBXProject "{APP}" */; '
          f'compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; '
          f'knownRegions = (Base, en, ); mainGroup = {main_group}; productRefGroup = {products_group} /* Products */; '
          f'projectDirPath = ""; projectRoot = ""; targets = (\n\t\t\t\t{app_target} /* {APP} */,\n'
          f'\t\t\t\t{test_target} /* {TESTS} */,\n\t\t\t); }}')

    # ---- Serialize -------------------------------------------------------
    body = "\n".join(f"\t\t{u} = {obj};" for u, obj in sorted(p.objects))
    pbxproj = ("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n"
               "\tobjectVersion = 56;\n\tobjects = {\n"
               f"{body}\n"
               "\t};\n"
               f"\trootObject = {uid('project')} /* Project object */;\n}}\n")

    os.makedirs(os.path.join(PROJ_DIR, "project.xcworkspace", "xcshareddata"), exist_ok=True)
    os.makedirs(os.path.join(PROJ_DIR, "xcshareddata", "xcschemes"), exist_ok=True)

    with open(os.path.join(PROJ_DIR, "project.pbxproj"), "w") as f:
        f.write(pbxproj)

    with open(os.path.join(PROJ_DIR, "project.xcworkspace", "contents.xcworkspacedata"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace\n   version = "1.0">\n'
                '   <FileRef\n      location = "self:">\n   </FileRef>\n</Workspace>\n')

    write_scheme(app_target)
    print(f"Generated {PROJ_DIR}")
    print(f"  app sources: {len(app_swift)}, resources: {len(app_res)}, test sources: {len(test_swift)}")


def write_scheme(app_target: str):
    test_target = uid("target:tests")
    scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app_target}" BuildableName = "{APP}.app" BlueprintName = "{APP}" ReferencedContainer = "container:{APP}.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{test_target}" BuildableName = "{TESTS}.xctest" BlueprintName = "{TESTS}" ReferencedContainer = "container:{APP}.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app_target}" BuildableName = "{APP}.app" BlueprintName = "{APP}" ReferencedContainer = "container:{APP}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{app_target}" BuildableName = "{APP}.app" BlueprintName = "{APP}" ReferencedContainer = "container:{APP}.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
'''
    with open(os.path.join(PROJ_DIR, "xcshareddata", "xcschemes", f"{APP}.xcscheme"), "w") as f:
        f.write(scheme)


if __name__ == "__main__":
    build()
