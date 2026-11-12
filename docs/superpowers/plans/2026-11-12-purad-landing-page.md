# PuraD — landing page and "PD" monogram: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish a static PuraD landing page in `site/index.html` and update the branding monogram from "P" to "PD" in all sources and derived PNGs.

**Architecture:** The page is one HTML file with embedded CSS, no dependencies or external requests, with a relative link to the existing SVG logo. Branding is an edit of three SVG sources in `assets/branding/` and regeneration of the derived PNGs by the script `scripts/gen-branding.sh`.

**Tech Stack:** HTML5, CSS (inline `<style>`), SVG, the DejaVu Sans font, bash + `rsvg-convert`/ImageMagick.

**Spec:** `docs/superpowers/specs/2026-11-12-purad-landing-page-design.md`

## Global Constraints

- The page language is Russian, `<html lang="ru">`.
- No external resources: no CDNs, no external fonts — only system
  (`system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`). The page must
  work fully offline.
- All CSS — inside `<style>`; JavaScript is not used.
- Logo — the relative path `../assets/branding/purad-logo.svg`; it is also
  included as the favicon.
- Colors: accent gradient `#1f7fb8 → #0b2e46`, accent bar `#8fd0f0`.
- Stub links: `href="#"` and next to it the comment `<!-- TODO: repository URL -->`
  or `<!-- TODO: Releases URL -->`.
- Version in the footer: `2026.11.09` (from the `VERSION` file).
- Monogram — variant A: "PD", `font-size=128`, `letter-spacing=-4`, baseline
  `y=178` (logo 256×256); in the 96×96 tiles — `font-size=52`,
  baselines `y=111` (welcome) and `y=163` (slide1).

## Review Focus

- **Relative path to the logo** — with a wrong path the image will not open when
  using `file://` from the `site/` folder. Expect: the logo is visible.
- **External resource** (CDN, `@import`, web font) — breaks the declared offline operation.
  Expect: not a single external request.
- **Stubs without a marker** — a link `href="#"` without a `TODO` comment is lost when
  publishing. Expect: every stub has a `TODO`.
- **"PD" wider than the tile** — in a 96×96 square the letters go beyond the edges. Expect: the inscription
  is fitted with margins.
- **Horizontal scrolling on a narrow screen** — appears with fixed
  widths. Expect: at a width of 360 px there is no horizontal scrolling.

---

### Task 1: Branding — monogram P → PD

**Files:**
- Modify: `assets/branding/purad-logo.svg`
- Modify: `assets/branding/purad-welcome.svg`
- Modify: `assets/branding/purad-slide1.svg`
- Regenerate: `config/includes.chroot/etc/calamares/branding/purad/purad-logo.png`
- Regenerate: `config/includes.chroot/etc/calamares/branding/purad/welcome.png`
- Regenerate: `config/includes.chroot/etc/calamares/branding/purad/slide1.png`
- Regenerate: `config/includes.chroot/usr/share/pixmaps/purad-logo.png`

**Interfaces:**
- Consumes: nothing (an isolated edit of assets).
- Produces: `assets/branding/purad-logo.svg` with the "PD" monogram — used
  by Task 2 as the page's logo and favicon.

- [ ] **Step 1: Replace the monogram in `assets/branding/purad-logo.svg`**

Replace the text `P` (lines 9–11) with `PD` with a reduced size and tight
tracking; move the bar lower (`y=200`):

```xml
  <text x="128" y="178" text-anchor="middle"
        font-family="DejaVu Sans" font-weight="bold" font-size="128"
        letter-spacing="-4" fill="#ffffff">PD</text>
  <rect x="56" y="200" width="144" height="10" rx="5" fill="#8fd0f0" opacity="0.85"/>
```

- [ ] **Step 2: Replace the monogram in `assets/branding/purad-welcome.svg`**

In the 96×96 tile (lines 11–12) replace `P` with `PD`, size 52, baseline 111:

```xml
  <text x="228" y="111" text-anchor="middle" font-family="DejaVu Sans"
        font-weight="bold" font-size="52" fill="#ffffff">PD</text>
```

- [ ] **Step 3: Replace the monogram in `assets/branding/purad-slide1.svg`**

In the 96×96 tile (lines 11–12) replace `P` with `PD`, size 52, baseline 163:

```xml
  <text x="400" y="163" text-anchor="middle" font-family="DejaVu Sans"
        font-weight="bold" font-size="52" fill="#ffffff">PD</text>
```

- [ ] **Step 4: Check that no single "P" monogram remains**

Run: `grep -n '>P<' assets/branding/*.svg`
Expected: empty output (not a single `P` as tag content).

- [ ] **Step 5: Regenerate the derived PNGs**

Run: `bash scripts/gen-branding.sh`
Expected: the script prints a list of five PNGs (three in `.../branding/purad/` and a copy
in `.../pixmaps/`) without errors.

- [ ] **Step 6: Check that the PNGs were updated**

Run: `git status --short config/includes.chroot`
Expected: exactly 4 PNG files changed (`branding/purad/purad-logo.png`,
`welcome.png`, `slide1.png`, `pixmaps/purad-logo.png`).

- [ ] **Step 7: Visually check the fit of "PD"**

Run: `rsvg-convert -o /tmp/pd-logo.png assets/branding/purad-logo.svg && rsvg-convert -o /tmp/pd-welcome.png assets/branding/purad-welcome.svg`
Open both PNGs and make sure that "PD" is entirely inside the square, with margins on
the sides, and the bar does not cross the letters. (Manual check — there are no automated tests for the assets.)

- [ ] **Step 8: Commit**

```bash
git add assets/branding/purad-logo.svg assets/branding/purad-welcome.svg \
        assets/branding/purad-slide1.svg config/includes.chroot
git commit -m "branding: monogram P → PD in all sources and PNG"
```

---

### Task 2: The `site/index.html` page

**Files:**
- Create: `site/index.html`

**Interfaces:**
- Consumes: the logo `assets/branding/purad-logo.svg` (Task 1) via the relative
  path `../assets/branding/purad-logo.svg`.
- Produces: the ready page `site/index.html` — self-contained and offline.

- [ ] **Step 1: Create `site/index.html` — skeleton, styles and sections**

Assemble one file: `<!DOCTYPE html>`, `<html lang="ru">`, `<head>` with
`<meta charset="utf-8">`, `<meta name="viewport" content="width=device-width, initial-scale=1">`,
`<title>PuraD</title>`, `<link rel="icon" type="image/svg+xml" href="../assets/branding/purad-logo.svg">`
and `<style>` with all the styles. `<body>` contains `header`, `main` (sections), `footer`.

Texts and values (pinning from the spec):

- **Header** — `<header>`: the logo `<img src="../assets/branding/purad-logo.svg" alt="PuraD" width="40" height="40">`,
  the name `PuraD`, anchor navigation: `#features` (Features), `#download`
  (Download), `#docs` (Documentation). Position `sticky`.
- **Hero** — `<section id="top">`: `<h1>PuraD</h1>`, the slogan
  "Live distribution based on pure Debian with KDE Plasma", a description paragraph of 1–2
  sentences about a live CD with KDE Plasma and installation to ext4/btrfs without third-party
  repositories. Buttons:
  - "Download ISO" → `<a href="#" class="btn btn-primary">` + `<!-- TODO: Releases URL -->`;
  - "GitHub" → `<a href="#" class="btn">` + `<!-- TODO: repository URL -->`.
- **Features** — `<section id="features">` with the heading "Key features"
  and a grid of cards (CSS Grid `repeat(auto-fit, minmax(240px, 1fr))`) of six
  items: "Pure Debian" (only `main`, `contrib`, `non-free-firmware`),
  "KDE Plasma 6", "ext4 and btrfs out of the box", "Wi-Fi and GPU firmware in the image",
  "btrfs snapshots" (Timeshift + grub-btrfs), "Reproducible build" (podman).
- **How to download/build** — `<section id="download">`: a paragraph with a link to
  Releases (stub `#` + `<!-- TODO: Releases URL -->`) and a `<pre><code>`
  block with the commands:

```text
make iso TARGET=trixie
make run-install TARGET=trixie
```

- **Documentation** — `<section id="docs">`: links to `README.md` and `docs/`
  (stubs `#` + `<!-- TODO: repository URL -->`).
- **Footer** — `<footer>`: `PuraD`, version `2026.11.09`, the current year.

Design: dark theme, accent gradient `#1f7fb8 → #0b2e46` (for example, in
the hero background), accent bar `#8fd0f0`; mobile-first; visible focus
(`:focus-visible`); the block `@media (prefers-reduced-motion: reduce)` disables
animations. No fixed widths that cause horizontal scrolling.

- [ ] **Step 2: Check that there are no external resources**

Run: `grep -nE 'https?://|@import|fonts\.googleapis|cdn\.' site/index.html`
Expected: empty output (all links are anchors, stubs, local paths).

- [ ] **Step 3: Check that every stub has a TODO marker**

Run: `grep -c 'href="#"' site/index.html && grep -c 'TODO: URL' site/index.html`
Expected: both numbers are equal — the number of `href="#"` matches the number of
`TODO: URL` markers (5 and 5 expected: 2 in the hero, 1 in the download block, 2 in
the documentation).

- [ ] **Step 4: Check that the path to the logo resolves**

Run: `cd site && test -f ../assets/branding/purad-logo.svg && echo OK`
Expected: `OK`.

- [ ] **Step 5: Open the page and check manually**

Run: `xdg-open site/index.html`
Check: the logo is displayed; all navigation anchors scroll to the sections;
at a width of ~360 px (or in mobile mode) there is no horizontal scrolling;
`prefers-reduced-motion` does not break the appearance.

- [ ] **Step 6: Commit**

```bash
git add site/index.html
git commit -m "site: PuraD landing page"
```
