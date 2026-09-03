# rvmendillo/portfolio

Rey Victor Mendillo's interactive Portfolio OS. It is dependency-free, installable as a PWA, responsive on touch devices, and designed for GitHub Pages.

## Portfolio OS

- Windows 11-inspired aurora desktop with draggable, resizable, minimizable, and maximizable windows
- Windows, iOS, and resume themes saved per local profile
- Animated boot, wallpaper parallax, window/menu transitions, toast feedback, and reduced-motion support
- About, real resume PDF viewer, Projects, File Explorer, Browser, Settings, Calculator, safe Terminal, and IntelliJ-style IDE
- GUI Designer with touch-friendly drag/drop, visual connections, live bindings, formulas, text actions, YAML/Python editing, and app packaging
- GUI exports for Tkinter, PyQt, Kivy, Java Swing, and C++ Win32
- Native Python and English/Filipino HumanCode transpilation to Python, Java, and C++
- Local-only portfolio assistant, per-profile app installer, offline service worker, CSP, URL allowlists, package validation, and no `eval`

## Publish

This bundle targets `rvmendillo/portfolio`. Push it to `main`, then set **Settings → Pages → Source** to **GitHub Actions**. The included workflow publishes the site at `https://rvmendillo.github.io/portfolio/`.

The separate **Build iPhone IPA** workflow uses a GitHub-hosted macOS runner to compile `ios/` and upload `ReyPortfolioOS-unsigned.ipa`. The wrapper opens the live Portfolio OS, so web updates appear without rebuilding the shell. Import the unsigned IPA into Feather and sign it with your certificate and matching provisioning profile.

GitHub Pages sites are public even when the source repository is private. Hosting Pages directly from a private repository requires GitHub Pro, Team, or Enterprise; otherwise make the repository public before enabling Pages.
