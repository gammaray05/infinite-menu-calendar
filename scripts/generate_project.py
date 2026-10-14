#!/usr/bin/env python3
"""Generate a dependency-free Xcode project with deterministic object IDs."""
from pathlib import Path
import hashlib

root = Path(__file__).resolve().parent.parent
def uid(value):
    return hashlib.sha1(value.encode()).hexdigest()[:24].upper()
objects = []
def obj(key, value):
    objects.append(f'{uid(key)} = {{ {value} }};')
sources = sorted(str(p.relative_to(root)) for p in (root / 'Sources').rglob('*.swift'))
for source in sources:
    obj(source, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{source}"; sourceTree = "<group>";')
    obj('build:' + source, f'isa = PBXBuildFile; fileRef = {uid(source)};')
obj('info', 'isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>";')
obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = InfiniteCalendar.app; sourceTree = BUILT_PRODUCTS_DIR;')
obj('products', f'isa = PBXGroup; children = ({uid("product")},); name = Products; sourceTree = "<group>";')
children = ','.join(uid(s) for s in sources) + ',' + uid('info') + ',' + uid('products')
obj('main', f'isa = PBXGroup; children = ({children},); sourceTree = "<group>";')
obj('sources', 'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = (' + ','.join(uid('build:' + s) for s in sources) + ',); runOnlyForDeploymentPostprocessing = 0;')
obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
obj('resources', 'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
for mode in ['Debug', 'Release']:
    opt = '-Onone' if mode == 'Debug' else '-O'
    obj('project:' + mode, f'isa = XCBuildConfiguration; buildSettings = {{ SDKROOT = macosx; MACOSX_DEPLOYMENT_TARGET = 14.0; CLANG_ENABLE_MODULES = YES; }}; name = {mode};')
    obj('target:' + mode, f'isa = XCBuildConfiguration; buildSettings = {{ PRODUCT_NAME = InfiniteCalendar; PRODUCT_BUNDLE_IDENTIFIER = com.gammaray05.InfiniteCalendar; INFOPLIST_FILE = Info.plist; GENERATE_INFOPLIST_FILE = NO; SWIFT_VERSION = 5.0; SWIFT_OPTIMIZATION_LEVEL = "{opt}"; SWIFT_COMPILATION_MODE = wholemodule; CODE_SIGN_IDENTITY = "-"; CODE_SIGN_STYLE = Manual; COMBINE_HIDPI_IMAGES = YES; ENABLE_HARDENED_RUNTIME = YES; LD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks"; }}; name = {mode};')
for kind in ['project', 'target']:
    obj(kind + ':config', f'isa = XCConfigurationList; buildConfigurations = ({uid(kind + ":Debug")},{uid(kind + ":Release")},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {uid("target:config")}; buildPhases = ({uid("sources")},{uid("frameworks")},{uid("resources")},); buildRules = (); dependencies = (); name = InfiniteCalendar; productName = InfiniteCalendar; productReference = {uid("product")}; productType = "com.apple.product-type.application";')
obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; }}; buildConfigurationList = {uid("project:config")}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, it, Base,); mainGroup = {uid("main")}; productRefGroup = {uid("products")}; projectDirPath = ""; projectRoot = ""; targets = ({uid("target")},);')
project = root / 'InfiniteCalendar.xcodeproj'
project.mkdir(exist_ok=True)
(project / 'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n' + '\n'.join(objects) + f'\n}}; rootObject = {uid("project")}; }}\n')
scheme_dir = project / 'xcshareddata' / 'xcschemes'
scheme_dir.mkdir(parents=True, exist_ok=True)
ref = f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid("target")}" BuildableName="InfiniteCalendar.app" BlueprintName="InfiniteCalendar" ReferencedContainer="container:InfiniteCalendar.xcodeproj"/>'
(scheme_dir / 'InfiniteCalendar.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"/>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated InfiniteCalendar.xcodeproj')
