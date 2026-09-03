# rvmendillo/portfolio

Rey Victor Mendillo's full-viewport parallax portfolio. It is dependency-free and designed for GitHub Pages.

## Design

- Windows/terminal-inspired glass interface based on the existing portfolio direction
- Five sections locked to the current viewport (`100svh` with a JavaScript viewport fallback)
- CSS scroll snap and layered, reduced-motion-safe parallax
- Internal section scrolling on small phones when content needs more room
- Responsive navigation and accessible semantic structure

## Publish

This bundle targets `rvmendillo/portfolio`. Push it to `main`, then set **Settings → Pages → Source** to **GitHub Actions**. The included workflow publishes the site at `https://rvmendillo.github.io/portfolio/`.

The separate **Build iPhone IPA** workflow uses a GitHub-hosted macOS runner to compile `ios/` and upload `ReyPortfolioOS-unsigned.ipa`. Download that Actions artifact, import it into Feather, and sign it with your certificate and matching provisioning profile.

GitHub Pages sites are public even when the source repository is private. Hosting Pages directly from a private repository requires GitHub Pro, Team, or Enterprise; otherwise make the repository public before enabling Pages.
