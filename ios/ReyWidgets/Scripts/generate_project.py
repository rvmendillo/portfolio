#!/usr/bin/env python3
"""Generate the checked-in Xcode project without third-party build generators."""
from pathlib import Path
import hashlib
import json
import plistlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
objects = {}

def ident(label):
    return hashlib.sha256(label.encode()).hexdigest()[:24].upper()

def add(label, isa, **values):
    key = ident(label)
    objects[key] = dict(isa=isa, **values)
    return key

def file(path, kind):
    return add('file:' + path, 'PBXFileReference', lastKnownFileType=kind, path=path, sourceTree='<group>')

def plist(path, value):
    with (ROOT / path).open('wb') as handle:
        plistlib.dump(value, handle, sort_keys=False)

shared_info = {
    'CFBundleDevelopmentRegion': 'en', 'CFBundleExecutable': '$(EXECUTABLE_NAME)',
    'CFBundleIdentifier': '$(PRODUCT_BUNDLE_IDENTIFIER)', 'CFBundleInfoDictionaryVersion': '6.0',
    'CFBundleName': '$(PRODUCT_NAME)', 'CFBundleShortVersionString': '$(MARKETING_VERSION)',
    'CFBundleVersion': '$(CURRENT_PROJECT_VERSION)', 'RWAppGroup': '$(APP_GROUP)',
    'RWKeychainGroup': '$(AppIdentifierPrefix)$(KEYCHAIN_GROUP)',
}
plist('Config/App-Info.plist', dict(shared_info, **{
    'CFBundleDisplayName': 'ReyWidgets', 'CFBundlePackageType': 'APPL',
    'LSRequiresIPhoneOS': True, 'UILaunchScreen': {},
    'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False},
    'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'],
    'UISupportedInterfaceOrientations~ipad': ['UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown', 'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'],
    'UIRequiredDeviceCapabilities': ['arm64'], 'LSSupportsOpeningDocumentsInPlace': True,
    'NSLocalNetworkUsageDescription': 'Connect to API endpoints you configure on your local network.',
    'CFBundleURLTypes': [{'CFBundleURLName': '$(BUNDLE_ID_PREFIX)', 'CFBundleURLSchemes': ['reywidgets']}],
    'UTImportedTypeDeclarations': [{'UTTypeIdentifier': 'org.ggml.gguf', 'UTTypeDescription': 'GGUF language model',
        'UTTypeConformsTo': ['public.data'], 'UTTypeTagSpecification': {'public.filename-extension': ['gguf']}}],
}))
plist('Config/Widget-Info.plist', dict(shared_info, **{
    'CFBundleDisplayName': 'ReyWidgets', 'CFBundlePackageType': 'XPC!',
    'NSExtension': {'NSExtensionPointIdentifier': 'com.apple.widgetkit-extension'},
}))
for name in ['App', 'Widget']:
    plist(f'Config/{name}.entitlements', {
        'com.apple.security.application-groups': ['$(APP_GROUP)'],
        'keychain-access-groups': ['$(AppIdentifierPrefix)$(KEYCHAIN_GROUP)'],
    })
plist('App/PrivacyInfo.xcprivacy', {
    'NSPrivacyTracking': False, 'NSPrivacyCollectedDataTypes': [],
    'NSPrivacyAccessedAPITypes': [{'NSPrivacyAccessedAPIType': 'NSPrivacyAccessedAPICategoryUserDefaults',
                               'NSPrivacyAccessedAPITypeReasons': ['CA92.1']}],
})

base_config = file('Config/Base.xcconfig', 'text.xcconfig')
refs = {}
for directory in ['Core', 'App', 'Widget', 'Tests', 'UITests']:
    for path in sorted((ROOT / directory).glob('*.swift')):
        relative = str(path.relative_to(ROOT))
        refs[relative] = file(relative, 'sourcecode.swift')
for path, kind in [('App/Assets.xcassets', 'folder.assetcatalog'), ('App/PrivacyInfo.xcprivacy', 'text.xml')]:
    refs[path] = file(path, kind)

config_refs = [base_config]
for path in sorted((ROOT / 'Config').iterdir()):
    if path.name == 'Base.xcconfig': continue
    config_refs.append(file(str(path.relative_to(ROOT)), 'text.plist.xml'))

product_ids = {}
target_ids = {name: ident('target:' + name) for name in ['ReyWidgets', 'ReyWidgetsExtension', 'ReyWidgetsTests', 'ReyWidgetsUITests']}
product_specs = {
    'ReyWidgets': ('app', 'wrapper.application', 'com.apple.product-type.application'),
    'ReyWidgetsExtension': ('appex', 'wrapper.app-extension', 'com.apple.product-type.app-extension'),
    'ReyWidgetsTests': ('xctest', 'wrapper.cfbundle', 'com.apple.product-type.bundle.unit-test'),
    'ReyWidgetsUITests': ('xctest', 'wrapper.cfbundle', 'com.apple.product-type.bundle.ui-testing'),
}
for name, (suffix, kind, _) in product_specs.items():
    product_ids[name] = add('product:' + name, 'PBXFileReference', explicitFileType=kind, includeInIndex=0,
                            path=name + '.' + suffix, sourceTree='BUILT_PRODUCTS_DIR')

package = add('package:llama', 'XCLocalSwiftPackageReference', relativePath='Packages/LlamaRuntime')
package_product = add('package-product:llama', 'XCSwiftPackageProductDependency', package=package, productName='LlamaRuntime')

def configuration_list(label, settings):
    configs = []
    for config in ['Debug', 'Release']:
        build = dict(settings)
        if config == 'Debug':
            build.update(SWIFT_OPTIMIZATION_LEVEL='-Onone', DEBUG_INFORMATION_FORMAT='dwarf',
                         ENABLE_TESTABILITY='YES', SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) DEBUG', ONLY_ACTIVE_ARCH='YES')
        else:
            build.update(SWIFT_OPTIMIZATION_LEVEL='-O', DEBUG_INFORMATION_FORMAT='dwarf-with-dsym',
                         SWIFT_COMPILATION_MODE='wholemodule', VALIDATE_PRODUCT='YES')
        configs.append(add(label + ':' + config, 'XCBuildConfiguration', baseConfigurationReference=base_config,
                           buildSettings=build, name=config))
    return add(label + ':list', 'XCConfigurationList', buildConfigurations=configs,
               defaultConfigurationIsVisible=0, defaultConfigurationName='Release')

def dependency(source, target):
    proxy = add('proxy:' + source + ':' + target, 'PBXContainerItemProxy',
                containerPortal=ident('project'), proxyType=1, remoteGlobalIDString=target_ids[target], remoteInfo=target)
    return add('dependency:' + source + ':' + target, 'PBXTargetDependency', target=target_ids[target], targetProxy=proxy)

for name in target_ids:
    source_dirs = ['Core', 'App'] if name == 'ReyWidgets' else ['Core', 'Widget'] if name == 'ReyWidgetsExtension' else ['Tests'] if name == 'ReyWidgetsTests' else ['UITests']
    sources = []
    for path, reference in refs.items():
        if path.endswith('.swift') and path.split('/')[0] in source_dirs:
            sources.append(add('build:' + name + ':' + path, 'PBXBuildFile', fileRef=reference))
    source_phase = add('sources:' + name, 'PBXSourcesBuildPhase', buildActionMask=2147483647, files=sources, runOnlyForDeploymentPostprocessing=0)
    frameworks = []
    if name == 'ReyWidgets':
        frameworks.append(add('build:llama', 'PBXBuildFile', productRef=package_product))
    framework_phase = add('frameworks:' + name, 'PBXFrameworksBuildPhase', buildActionMask=2147483647, files=frameworks, runOnlyForDeploymentPostprocessing=0)
    resources = []
    if name == 'ReyWidgets':
        for path in ['App/Assets.xcassets', 'App/PrivacyInfo.xcprivacy']:
            resources.append(add('resource:' + path, 'PBXBuildFile', fileRef=refs[path]))
    resource_phase = add('resources:' + name, 'PBXResourcesBuildPhase', buildActionMask=2147483647, files=resources, runOnlyForDeploymentPostprocessing=0)
    phases = [source_phase, framework_phase, resource_phase]
    settings = {'PRODUCT_NAME': '$(TARGET_NAME)', 'PRODUCT_MODULE_NAME': name}
    dependencies = []
    if name == 'ReyWidgets':
        embed = add('build:extension', 'PBXBuildFile', fileRef=product_ids['ReyWidgetsExtension'], settings={'ATTRIBUTES': ['RemoveHeadersOnCopy', 'CodeSignOnCopy']})
        phases.append(add('embed:extension', 'PBXCopyFilesBuildPhase', buildActionMask=2147483647,
                          dstPath='', dstSubfolderSpec=13, files=[embed], name='Embed App Extensions', runOnlyForDeploymentPostprocessing=0))
        dependencies.append(dependency(name, 'ReyWidgetsExtension'))
        settings.update(PRODUCT_BUNDLE_IDENTIFIER='$(BUNDLE_ID_PREFIX)', INFOPLIST_FILE='Config/App-Info.plist',
                        CODE_SIGN_ENTITLEMENTS='Config/App.entitlements', ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon',
                        OTHER_LDFLAGS=['$(inherited)', '-weak_framework', 'FoundationModels'])
    elif name == 'ReyWidgetsExtension':
        settings.update(PRODUCT_BUNDLE_IDENTIFIER='$(BUNDLE_ID_PREFIX).widgets', INFOPLIST_FILE='Config/Widget-Info.plist',
                        CODE_SIGN_ENTITLEMENTS='Config/Widget.entitlements', APPLICATION_EXTENSION_API_ONLY='YES', SKIP_INSTALL='YES',
                        LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/../../Frameworks')
    else:
        dependencies.append(dependency(name, 'ReyWidgets'))
        settings.update(PRODUCT_BUNDLE_IDENTIFIER='$(BUNDLE_ID_PREFIX).' + ('tests' if name == 'ReyWidgetsTests' else 'uitests'),
                        GENERATE_INFOPLIST_FILE='YES')
        if name == 'ReyWidgetsTests':
            settings.update(TEST_HOST='$(BUILT_PRODUCTS_DIR)/ReyWidgets.app/ReyWidgets', BUNDLE_LOADER='$(TEST_HOST)')
        else:
            settings.update(TEST_TARGET_NAME='ReyWidgets')
    add('target:' + name, 'PBXNativeTarget', buildConfigurationList=configuration_list('config:' + name, settings),
        buildPhases=phases, buildRules=[], dependencies=dependencies, name=name, productName=name,
        productReference=product_ids[name], productType=product_specs[name][2],
        packageProductDependencies=[package_product] if name == 'ReyWidgets' else [])

groups = []
for directory in ['App', 'Core', 'Widget', 'Tests', 'UITests']:
    groups.append(add('group:' + directory, 'PBXGroup', children=[ref for path, ref in refs.items() if path.startswith(directory + '/')], name=directory, sourceTree='<group>'))
groups.append(add('group:Config', 'PBXGroup', children=config_refs, name='Config', sourceTree='<group>'))
products = add('group:Products', 'PBXGroup', children=list(product_ids.values()), name='Products', sourceTree='<group>')
groups.append(products)
main = add('group:main', 'PBXGroup', children=groups, sourceTree='<group>')
project = add('project', 'PBXProject', attributes={'BuildIndependentTargetsInParallel': 'YES', 'LastUpgradeCheck': '2600',
    'TargetAttributes': {target_ids[n]: dict(CreatedOnToolsVersion='26.0', **({'TestTargetID': target_ids['ReyWidgets']} if n.endswith('Tests') else {})) for n in target_ids}},
    buildConfigurationList=configuration_list('project-config', {}), compatibilityVersion='Xcode 14.0', developmentRegion='en',
    hasScannedForEncodings=0, knownRegions=['en', 'Base'], mainGroup=main, productRefGroup=products,
    projectDirPath='', projectRoot='', targets=list(target_ids.values()), packageReferences=[package])

def emit(value, indent=0):
    pad = '\t' * indent
    if isinstance(value, dict):
        return '{\n' + ''.join('\t' * (indent + 1) + json.dumps(k) + ' = ' + emit(v, indent + 1) + ';\n' for k, v in value.items()) + pad + '}'
    if isinstance(value, list):
        return '(\n' + ''.join('\t' * (indent + 1) + emit(v, indent + 1) + ',\n' for v in value) + pad + ')'
    return str(value) if isinstance(value, int) else json.dumps(value, ensure_ascii=False)

project_dir = ROOT / 'ReyWidgets.xcodeproj'
project_dir.mkdir(exist_ok=True)
payload = dict(archiveVersion=1, classes={}, objectVersion=56, objects=objects, rootObject=project)
(project_dir / 'project.pbxproj').write_text('// !$*UTF8*$!\n' + emit(payload) + '\n')

scheme = ET.Element('Scheme', LastUpgradeVersion='2600', version='1.7')
build = ET.SubElement(scheme, 'BuildAction', parallelizeBuildables='YES', buildImplicitDependencies='YES')
entries = ET.SubElement(build, 'BuildActionEntries')
def build_reference(parent, name):
    ET.SubElement(parent, 'BuildableReference', BuildableIdentifier='primary', BlueprintIdentifier=target_ids[name],
                  BuildableName=objects[product_ids[name]]['path'], BlueprintName=name, ReferencedContainer='container:ReyWidgets.xcodeproj')
for name in ['ReyWidgets', 'ReyWidgetsTests', 'ReyWidgetsUITests']:
    item = ET.SubElement(entries, 'BuildActionEntry', buildForTesting='YES', buildForRunning='YES' if name == 'ReyWidgets' else 'NO',
                         buildForProfiling='YES' if name == 'ReyWidgets' else 'NO', buildForArchiving='YES' if name == 'ReyWidgets' else 'NO', buildForAnalyzing='YES')
    build_reference(item, name)
test = ET.SubElement(scheme, 'TestAction', buildConfiguration='Debug', selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',
                     selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB', shouldUseLaunchSchemeArgsEnv='YES')
testables = ET.SubElement(test, 'Testables')
for name in ['ReyWidgetsTests', 'ReyWidgetsUITests']:
    build_reference(ET.SubElement(testables, 'TestableReference', skipped='NO', parallelizable='NO'), name)
launch = ET.SubElement(scheme, 'LaunchAction', buildConfiguration='Debug', selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',
                       selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB', launchStyle='0', useCustomWorkingDirectory='NO', ignoresPersistentStateOnLaunch='NO', debugDocumentVersioning='YES', debugServiceExtension='internal', allowLocationSimulation='YES')
build_reference(ET.SubElement(launch, 'BuildableProductRunnable', runnableDebuggingMode='0'), 'ReyWidgets')
profile = ET.SubElement(scheme, 'ProfileAction', buildConfiguration='Release', shouldUseLaunchSchemeArgsEnv='YES', savedToolIdentifier='', useCustomWorkingDirectory='NO', debugDocumentVersioning='YES')
build_reference(ET.SubElement(profile, 'BuildableProductRunnable', runnableDebuggingMode='0'), 'ReyWidgets')
ET.SubElement(scheme, 'AnalyzeAction', buildConfiguration='Debug')
ET.SubElement(scheme, 'ArchiveAction', buildConfiguration='Release', revealArchiveInOrganizer='YES')
ET.indent(scheme)
scheme_dir = project_dir / 'xcshareddata/xcschemes'; scheme_dir.mkdir(parents=True, exist_ok=True)
ET.ElementTree(scheme).write(scheme_dir / 'ReyWidgets.xcscheme', encoding='UTF-8', xml_declaration=True)
print('Generated ReyWidgets.xcodeproj: app, widget extension, unit tests, UI tests.')
