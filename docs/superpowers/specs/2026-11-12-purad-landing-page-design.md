# PuraD — landing page: design

## Task

A public landing page for the PuraD project: one static HTML page
that briefly tells what this distribution is, shows the key
features and leads to download/build and documentation.

The audience is those who are learning about the project for the first time (from a link, a post, a screenshot).
Success: the page opens locally without a network, all sections are in place,
stub links are marked, it looks neat on desktop and on a phone.

## Scope

- **Included:**
  - one file `site/index.html` with embedded styles;
  - a related branding change: the monogram **P → PD** in all SVG sources
    and regeneration of the derived PNGs (see the "Branding change" section).
- **Not included:** build/minification, frameworks, external CDNs, analytics,
  forms, screenshots, multilanguage, separate CSS/JS files.
- The repository is not published yet, there are no ready ISOs — links to GitHub/Releases
  are set as stubs and marked for later replacement.

## Location and resources

- File: `site/index.html` (the `site/` folder separates the page from the build and docs).
- CSS — inside `<style>`; JavaScript is not used (there are no copy buttons).
- Logo — the relative path `../assets/branding/purad-logo.svg`; it is also
  included as the favicon (`<link rel="icon" …>`).
- External fonts and CDNs are not used: only system fonts
  (`system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`).
- The page language is Russian (`<html lang="ru">`).

## Page structure

1. **Header** (`<header>`) — logo + name, anchor navigation
   (Features · Download · Documentation). Sticky on scroll.
2. **Hero** (`<section id="top">`) — logo, `<h1>PuraD</h1>`,
   the slogan "Live distribution based on pure Debian with KDE Plasma",
   a short description in 1–2 sentences, buttons:
   - **"Download ISO"** → Releases (stub);
   - **"GitHub"** → repository (stub).
3. **Key features** (`<section id="features">`) — 4–6 cards:
   - Pure Debian without third-party repositories (`main`, `contrib`,
     `non-free-firmware`);
   - KDE Plasma 6;
   - Installation to ext4/btrfs out of the box;
   - Wi-Fi/GPU firmware already in the image;
   - btrfs snapshots (Timeshift + grub-btrfs);
   - Reproducible build in podman.
4. **How to download/build** (`<section id="download">`) — a block with the commands
   `make iso TARGET=trixie` and `make run-install TARGET=trixie` (mono code),
   next to it a link to Releases.
5. **Documentation** (`<section id="docs">`) — links to `README.md` and `docs/`.
6. **Footer** (`<footer>`) — name, version (`2026.11.09`, from `VERSION`), year.

## Design

- Dark theme in the logo's colors: accent gradient `#1f7fb8 → #0b2e46`.
- Mobile-first, responsive card grid (CSS Grid, `auto-fit`/`minmax`).
- Semantics (`header`/`main`/`section`/`footer`), text contrast,
  `alt` on images, visible focus for the keyboard.
- Respect for `prefers-reduced-motion`: animations are disabled.

## Stub links

Links to the repository and Releases are marked up as `href="#"` with
comments `<!-- TODO: repository URL -->` / `<!-- TODO: Releases URL -->`
next to them, so they can be replaced in one place when published.

## Verification

There are no automated tests for a static file — verification is manual:

- open `site/index.html` locally without a network, make sure there are no external
  requests and everything is displayed;
- check in a wide and a narrow window (responsive);
- check that all navigation anchors work;
- make sure the stubs are marked with comments.

## Branding change: monogram P → PD

The chosen variant is **A**: "PD" tight, the underline preserved (closest to
the current style). It changes in all three SVG sources; the derived PNGs for
Calamares and the icons are regenerated and committed.

**`assets/branding/purad-logo.svg`** (256×256): the text `PD`, `font-size=128`,
`letter-spacing=-4`, baseline `y=178`, the accent bar stays
(`x=56 y=200 w=144 h=10`).

**`assets/branding/purad-welcome.svg`**: the monogram in a 96×96 square
(`x=180 y=44`) — the text `PD`, `font-size=52`, baseline `y=111`
(the width of the "PD" inscription ≈ 76 px, so it fits with margins). The caption `PuraD`
below does not change.

**`assets/branding/purad-slide1.svg`**: the same for the square `x=352 y=96` —
`font-size=52`, baseline `y=163`.

**Regeneration of the derived files:** `scripts/gen-branding.sh` (uses
`rsvg-convert` or ImageMagick) updates
`config/includes.chroot/etc/calamares/branding/purad/{purad-logo,welcome,slide1}.png`
and the copy `config/includes.chroot/usr/share/pixmaps/purad-logo.png`. The changed
SVG and PNG are committed together.

**Branding verification:** no single `P` monogram remains in the SVG; the PNGs
are regenerated and visually show "PD"; the landing page shows the new logo
via the relative path.

> The `P` logo can easily be rolled back if desired: an edit only in these three SVGs + rerunning
> `scripts/gen-branding.sh`.

## Update: publication

The repository is published (`https://github.com/viorn/PuraD`), therefore:

- the stub links are replaced with real ones: repository, `…/releases`, `…/blob/main/README.md`,
  `…/tree/main/docs`;
- the landing page is published via GitHub Actions + Pages (`.github/workflows/pages.yml`,
  publish directory `site/`) at `https://viorn.github.io/PuraD/`;
- since Pages serves only the contents of `site/`, a copy of the logo is placed in
  `site/purad-logo.svg`, and the page references it by a relative path
  (`purad-logo.svg`) instead of `../assets/…`; the branding source remains
  `assets/branding/purad-logo.svg`;
- added `<meta name="description">` and Open Graph / Twitter tags for the preview
  when sharing; the og image is `site/og-image.png` (source
  `assets/branding/purad-og.svg`, rendered by `scripts/gen-branding.sh`);
- the ISO image (2.3 GB) does not fit in GitHub Releases (the limit is 2 GiB per file),
  so it is distributed via BitTorrent: `.torrent` and `.sha256` are attached to the release,
  and the page has a "Download torrent" button and a magnet link; the `.torrent` is built by
  `scripts/gen-torrent.py`;
- additionally the image is uploaded to an external HTTP hosting (FolderHost): a permanent
  direct link (`/s/<id>`, with resumption) became the main one ("Download ISO"), and the torrent —
  an alternative; the same link is specified as a web seed (`url-list`) in the `.torrent`,
  so peers pull the image over HTTP; the info hash does not change when `url-list` is added;
- the site and README are translated into two languages: `README.md` — English (main), `README.ru.md` —
  Russian, with a switcher at the beginning; the page `site/index.html` is English (`lang="en"`),
  `site/ru/index.html` is Russian (`lang="ru"`), the header has a switcher, the pages have their own
  `canonical` and `hreflang` alternatives.

