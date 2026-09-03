# Rey Portfolio Native

This is the separate, native SwiftUI edition of Rey Portfolio OS. It does not use `WKWebView`, load the GitHub Pages site, or call a remote AI endpoint.

## Native features

- Animated SwiftUI desktop and app transitions
- Windows, iOS, and resume themes persisted in `UserDefaults`
- About, projects, native PDFKit resume, files, browser links, calculator, and settings
- Safe local terminal and polyglot code-output simulator without `eval`
- Native IDE, Python/HumanCode transpiler, and offline portfolio assistant
- Touch GUI Designer with draggable controls, visual connections, formulas, YAML generation, preview, and locally installed packages
- App Studio for persistent GUI Designer packages

## Build

The `Build Native iOS IPA` GitHub Actions workflow generates the Xcode project with XcodeGen, compiles an unsigned device build, and uploads `ReyPortfolioNative-unsigned.ipa`. The earlier `ReyPortfolioOS-unsigned.ipa` web wrapper remains separate and unchanged.
