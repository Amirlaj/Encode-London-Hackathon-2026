#!/usr/bin/env python3
"""Generate the checked-in Xcode project without package-manager dependencies."""
from pathlib import Path
from hashlib import sha1
import json

root = Path(__file__).resolve().parent.parent
# The Debug build allows a LAN development server. Release keeps ATS enabled.
plist = (root / 'Replay/Resources/Info.plist').read_text()
(root / 'Replay/Resources/Info-Debug.plist').write_text(plist.replace('<key>NSAllowsArbitraryLoads</key><false/>', '<key>NSAllowsArbitraryLoads</key><true/>'))
objects = {}
def ident(name):
    return sha1(name.encode()).hexdigest()[:24].upper()
def quote(value):
    return json.dumps(str(value))
def add(name, value):
    key = ident(name)
    objects[key] = value
    return key
def array(values):
    return '(' + ', '.join(values) + (',' if values else '') + ')'
def settings(values):
    return '{' + ' '.join(f'{key} = {quote(value)};' for key, value in values.items()) + '}'

products = []
groups = []
targets = []
for target, folder, product_type, ext in [
    ('Replay', 'Replay/Sources', 'application', 'app'),
    ('ReplayTests', 'ReplayTests', 'bundle.unit-test', 'xctest'),
    ('ReplayUITests', 'ReplayUITests', 'bundle.ui-testing', 'xctest')
]:
    refs, sources, resources = [], [], []
    for path in sorted((root / folder).glob('*.swift')):
        relative = str(path.relative_to(root))
        ref = add(relative, f'{{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(relative)}; sourceTree = SOURCE_ROOT;}}')
        refs.append(ref)
        sources.append(add(relative + '-build', f'{{isa = PBXBuildFile; fileRef = {ref};}}'))
    if target == 'Replay':
        for relative, kind, build in [
            ('Replay/Resources/Assets.xcassets', 'folder.assetcatalog', True),
            ('Replay/Resources/Info.plist', 'text.plist.xml', False),
            ('Replay/Resources/PrivacyInfo.xcprivacy', 'text.xml', True)
        ]:
            ref = add(relative, f'{{isa = PBXFileReference; lastKnownFileType = {kind}; path = {quote(relative)}; sourceTree = SOURCE_ROOT;}}')
            refs.append(ref)
            if build:
                resources.append(add(relative + '-build', f'{{isa = PBXBuildFile; fileRef = {ref};}}'))
    groups.append(add(target + '-group', f'{{isa = PBXGroup; children = {array(refs)}; name = {target}; sourceTree = "<group>";}}'))
    product = add(target + '-product', f'{{isa = PBXFileReference; explicitFileType = {"wrapper.application" if ext == "app" else "wrapper.cfbundle"}; path = {target}.{ext}; sourceTree = BUILT_PRODUCTS_DIR;}}')
    products.append(product)
    source_phase = add(target + '-sources', f'{{isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array(sources)}; runOnlyForDeploymentPostprocessing = 0;}}')
    resource_phase = add(target + '-resources', f'{{isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = {array(resources)}; runOnlyForDeploymentPostprocessing = 0;}}')
    framework_phase = add(target + '-frameworks', '{isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;}')
    configs = []
    for config in ['Debug', 'Release']:
        values = {
            'PRODUCT_NAME': '$(TARGET_NAME)', 'PRODUCT_BUNDLE_IDENTIFIER': f'com.amirlajevardi.{target.lower()}',
            'SWIFT_VERSION': '5.0', 'IPHONEOS_DEPLOYMENT_TARGET': '17.0', 'TARGETED_DEVICE_FAMILY': '1',
            'CODE_SIGN_STYLE': 'Automatic', 'GENERATE_INFOPLIST_FILE': 'YES',
            'SUPPORTED_PLATFORMS': 'iphoneos iphonesimulator',
            'SWIFT_EMIT_LOC_STRINGS': 'YES', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
            'SWIFT_OPTIMIZATION_LEVEL': '-Onone' if config == 'Debug' else '-O',
        }
        if config == 'Debug':
            values['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'DEBUG $(inherited)'
        if target == 'Replay':
            values.update({'INFOPLIST_FILE': 'Replay/Resources/Info-Debug.plist' if config == 'Debug' else 'Replay/Resources/Info.plist', 'GENERATE_INFOPLIST_FILE': 'NO',
                           'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon'})
        elif target == 'ReplayTests':
            values.update({'TEST_HOST': '$(BUILT_PRODUCTS_DIR)/Replay.app/Replay', 'BUNDLE_LOADER': '$(TEST_HOST)'})
        else:
            values['TEST_TARGET_NAME'] = 'Replay'
        configs.append(add(target + config, f'{{isa = XCBuildConfiguration; buildSettings = {settings(values)}; name = {config};}}'))
    config_list = add(target + '-configs', f'{{isa = XCConfigurationList; buildConfigurations = {array(configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}}')
    deps = []
    if target != 'Replay':
        proxy = add(target + '-proxy', f'{{isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {ident("Replay-target")}; remoteInfo = Replay;}}')
        deps.append(add(target + '-dependency', f'{{isa = PBXTargetDependency; target = {ident("Replay-target")}; targetProxy = {proxy};}}'))
    targets.append(add(target + '-target', f'{{isa = PBXNativeTarget; buildConfigurationList = {config_list}; buildPhases = {array([source_phase, framework_phase, resource_phase])}; buildRules = (); dependencies = {array(deps)}; name = {target}; productName = {target}; productReference = {product}; productType = "com.apple.product-type.{product_type}";}}'))

product_group = add('products', f'{{isa = PBXGroup; children = {array(products)}; name = Products; sourceTree = "<group>";}}')
main = add('main', f'{{isa = PBXGroup; children = {array(groups + [product_group])}; sourceTree = "<group>";}}')
project_configs = []
for config in ['Debug', 'Release']:
    values = {'SDKROOT': 'iphoneos', 'CLANG_ENABLE_MODULES': 'YES', 'CLANG_ENABLE_OBJC_ARC': 'YES',
              'ENABLE_TESTABILITY': 'YES' if config == 'Debug' else 'NO',
              'DEBUG_INFORMATION_FORMAT': 'dwarf' if config == 'Debug' else 'dwarf-with-dsym',
              'GCC_C_LANGUAGE_STANDARD': 'gnu17', 'ONLY_ACTIVE_ARCH': 'YES' if config == 'Debug' else 'NO'}
    project_configs.append(add('project-' + config, f'{{isa = XCBuildConfiguration; buildSettings = {settings(values)}; name = {config};}}'))
config_list = add('project-configs', f'{{isa = XCConfigurationList; buildConfigurations = {array(project_configs)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;}}')
add('project', f'{{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2660;}}; buildConfigurationList = {config_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main}; productRefGroup = {product_group}; projectDirPath = ""; projectRoot = ""; targets = {array(targets)};}}')
output = '// !$*UTF8*$!\n{\n archiveVersion = 1;\n classes = {};\n objectVersion = 56;\n objects = {\n'
output += '\n'.join(f'  {key} = {value};' for key, value in objects.items())
output += f'\n }};\n rootObject = {ident("project")};\n}}\n'
(root / 'Replay.xcodeproj/project.pbxproj').write_text(output)

def reference(target):
    ext = 'app' if target == 'Replay' else 'xctest'
    return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ident(target + "-target")}" BuildableName="{target}.{ext}" BlueprintName="{target}" ReferencedContainer="container:Replay.xcodeproj"/>'
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2660" version="1.3">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries>
    <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference('Replay')}</BuildActionEntry>
  </BuildActionEntries></BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>
    <TestableReference skipped="NO" parallelizable="NO">{reference('ReplayTests')}</TestableReference>
    <TestableReference skipped="NO" parallelizable="NO">{reference('ReplayUITests')}</TestableReference>
  </Testables></TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('Replay')}</BuildableProductRunnable></LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference('Replay')}</BuildableProductRunnable></ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
'''
(root / 'Replay.xcodeproj/xcshareddata/xcschemes/Replay.xcscheme').write_text(scheme)
print('Generated Replay.xcodeproj')
