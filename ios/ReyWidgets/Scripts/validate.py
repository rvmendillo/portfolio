#!/usr/bin/env python3
"""Static project checks and actual HTML-runtime fixtures; does not claim an iOS build."""
from pathlib import Path
import base64
import html as html_module
import json
import plistlib
import re
import textwrap
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]

def multiline(source, expression):
    match = re.search(re.escape(expression) + r' = """\n(.*?)\n\s*"""', source, re.S)
    if not match: raise AssertionError('Missing Swift multiline string: ' + expression)
    return textwrap.dedent(match.group(1))

def fixtures():
    template = (ROOT / 'Core/Templates.swift').read_text()
    runtime = (ROOT / 'App/HTMLRuntime.swift').read_text()
    body = re.search(r'return """\n(.*?)\n\s*"""', runtime, re.S).group(1)
    body = textwrap.dedent(body).replace(r'\n', '\n')
    result = []
    examples = ROOT / 'Examples'; examples.mkdir(exist_ok=True)
    build = ROOT / 'build/validation'; build.mkdir(parents=True, exist_ok=True)
    for variable, name, data in [
        ('html', 'made-of-possibility', {'message': 'Make something yours.'}),
        ('apiHTML', 'api-canvas', {'current': {'temperature_2m': 29, 'apparent_temperature': 33, 'wind_speed_10m': 12}}),
    ]:
        html = multiline(template, variable + '.html')
        css = multiline(template, variable + '.css')
        js_literal = re.search(re.escape(variable + '.javascript') + r' = ("(?:\\.|[^"\\])*")', template).group(1)
        js = json.loads(js_literal)
        (examples / (name + '.css')).write_text(css)
        (examples / (name + '.js')).write_text(js)
        (examples / (name + '.body.html')).write_text(html)
        for size, width, height in [('small',170,170),('medium',364,170),('large',364,382)]:
            def render(payload):
                replacements = {
                    r'\(doc.css)': css, r'\(doc.html)': html, r'\(doc.javascript)': js,
                    r'\(payload)': base64.b64encode(json.dumps(payload,ensure_ascii=False).encode()).decode(),
                    r'\(size.rawValue)': size, r'\(Int(size.width))': str(width), r'\(Int(size.height))': str(height),
                }
                value = body
                for key, replacement in replacements.items(): value = value.replace(key, replacement)
                assert '\\(' not in value, 'Unreplaced Swift interpolation'
                return value
            page = render(data)
            path = build / (name + '-' + size + '.html'); path.write_text(page)
            if size == 'medium': (examples / (name + '.html')).write_text(page)
            result.append(dict(name=name, size=size, width=width, height=height, path=str(path), screenshot=str(build / (name + '-' + size + '.png'))))
    (build / 'fixtures.json').write_text(json.dumps(result,indent=2))
    preview = ROOT / 'Docs/HTML-Preview.html'
    if preview.exists():
        preview_text = preview.read_text()
        fixture_iter = iter(result)
        def replace_frame(match):
            source = Path(next(fixture_iter)['path']).read_text()
            return 'srcdoc="' + html_module.escape(source, quote=True) + '"'
        preview_text = re.sub(r'srcdoc="[^"]*"', replace_frame, preview_text)
        preview.write_text(preview_text)
    return result

def main():
    checks = []
    for path in (ROOT / 'Config').glob('*.plist'): plistlib.loads(path.read_bytes())
    app = plistlib.loads((ROOT/'Config/App.entitlements').read_bytes())
    widget = plistlib.loads((ROOT/'Config/Widget.entitlements').read_bytes())
    assert app == widget
    assert app['com.apple.security.application-groups'] == ['$(APP_GROUP)']
    assert app['keychain-access-groups'] == ['$(AppIdentifierPrefix)$(KEYCHAIN_GROUP)']
    checks.append('Matching App Group and Keychain entitlements; plist parsing')
    ET.parse(ROOT/'ReyWidgets.xcodeproj/xcshareddata/xcschemes/ReyWidgets.xcscheme')
    project = (ROOT/'ReyWidgets.xcodeproj/project.pbxproj').read_text()
    assert project.count('"isa" = "PBXNativeTarget"') == 4
    assert 'Embed App Extensions' in project and '"dstSubfolderSpec" = 13' in project
    assert 'XCLocalSwiftPackageReference' in project and 'LlamaRuntime' in project
    checks.append('Four Xcode targets, embedded extension, shared scheme and pinned runtime reference')
    try:
        from tree_sitter import Parser, Language
        import tree_sitter_swift
        parser = Parser(Language(tree_sitter_swift.language()))
        paths = list(ROOT.rglob('*.swift'))
        for path in paths:
            tree = parser.parse(path.read_bytes())
            assert not tree.root_node.has_error, 'Swift syntax error: ' + str(path)
        checks.append(f'Swift syntax parse: {len(paths)} files; no errors (not type checking)')
    except ImportError:
        checks.append('Swift syntax parsing skipped; install tree-sitter and tree-sitter-swift')
    fixtures()
    checks.append('Six HTML fixtures extracted from actual app templates and runtime')
    (ROOT/'build/validation/static-results.json').write_text(json.dumps(checks,indent=2))
    print('\n'.join('PASS: ' + item for item in checks))

if __name__ == '__main__': main()
