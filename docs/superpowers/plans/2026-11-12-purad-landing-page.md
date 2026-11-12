# PuraD — лендинг-визитка и монограмма «PD»: план реализации

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Опубликовать статичную страницу-визитку PuraD в `site/index.html` и обновить монограмму брендинга с «P» на «PD» во всех исходниках и производных PNG.

**Architecture:** Страница — один HTML-файл со встроенным CSS, без зависимостей и внешних запросов, с относительной ссылкой на существующий SVG-логотип. Брендинг — правка трёх SVG-исходников в `assets/branding/` и перегенерация производных PNG скриптом `scripts/gen-branding.sh`.

**Tech Stack:** HTML5, CSS (inline `<style>`), SVG, шрифт DejaVu Sans, bash + `rsvg-convert`/ImageMagick.

**Spec:** `docs/superpowers/specs/2026-11-12-purad-landing-page-design.md`

## Global Constraints

- Язык страницы — русский, `<html lang="ru">`.
- Никаких внешних ресурсов: ни CDN, ни внешних шрифтов — только системные
  (`system-ui, -apple-system, "Segoe UI", Roboto, sans-serif`). Страница обязана
  полностью работать офлайн.
- Весь CSS — внутри `<style>`; JavaScript не используется.
- Логотип — относительный путь `../assets/branding/purad-logo.svg`; он же
  подключается как favicon.
- Цвета: акцентный градиент `#1f7fb8 → #0b2e46`, акцентная полоска `#8fd0f0`.
- Ссылки-заглушки: `href="#"` и рядом комментарий `<!-- TODO: URL репозитория -->`
  или `<!-- TODO: URL Releases -->`.
- Версия в футере: `2026.11.09` (из файла `VERSION`).
- Монограмма — вариант A: «PD», `font-size=128`, `letter-spacing=-4`, базовая
  линия `y=178` (логотип 256×256); в плитках 96×96 — `font-size=52`,
  базовые линии `y=111` (welcome) и `y=163` (slide1).

## Review Focus

- **Относительный путь к логотипу** — при неверном пути картинка не откроется при
  `file://` из папки `site/`. Ждём: логотип виден.
- **Внешний ресурс** (CDN, `@import`, веб-шрифт) — ломает заявленную офлайн-работу.
  Ждём: ни одного внешнего запроса.
- **Заглушки без пометки** — ссылка `href="#"` без комментария `TODO` теряется при
  публикации. Ждём: у каждой заглушки есть `TODO`.
- **«PD» шире плитки** — в квадратике 96×96 буквы выходят за края. Ждём: надпись
  вписана с полями.
- **Горизонтальная прокрутка на узком экране** — появляется при фиксированных
  ширинах. Ждём: на ширине 360 px прокрутки по горизонтали нет.

---

### Task 1: Брендинг — монограмма P → PD

**Files:**
- Modify: `assets/branding/purad-logo.svg`
- Modify: `assets/branding/purad-welcome.svg`
- Modify: `assets/branding/purad-slide1.svg`
- Regenerate: `config/includes.chroot/etc/calamares/branding/purad/purad-logo.png`
- Regenerate: `config/includes.chroot/etc/calamares/branding/purad/welcome.png`
- Regenerate: `config/includes.chroot/etc/calamares/branding/purad/slide1.png`
- Regenerate: `config/includes.chroot/usr/share/pixmaps/purad-logo.png`

**Interfaces:**
- Consumes: ничего (изолированная правка ассетов).
- Produces: `assets/branding/purad-logo.svg` с монограммой «PD» — используется
  Task 2 как логотип и favicon страницы.

- [ ] **Step 1: Заменить монограмму в `assets/branding/purad-logo.svg`**

Текст `P` (строки 9–11) заменить на `PD` с уменьшенным кеглем и плотным
трекингом; полоску сдвинуть ниже (`y=200`):

```xml
  <text x="128" y="178" text-anchor="middle"
        font-family="DejaVu Sans" font-weight="bold" font-size="128"
        letter-spacing="-4" fill="#ffffff">PD</text>
  <rect x="56" y="200" width="144" height="10" rx="5" fill="#8fd0f0" opacity="0.85"/>
```

- [ ] **Step 2: Заменить монограмму в `assets/branding/purad-welcome.svg`**

В плитке 96×96 (строка 11–12) заменить `P` на `PD`, кегль 52, базовая линия 111:

```xml
  <text x="228" y="111" text-anchor="middle" font-family="DejaVu Sans"
        font-weight="bold" font-size="52" fill="#ffffff">PD</text>
```

- [ ] **Step 3: Заменить монограмму в `assets/branding/purad-slide1.svg`**

В плитке 96×96 (строки 11–12) заменить `P` на `PD`, кегль 52, базовая линия 163:

```xml
  <text x="400" y="163" text-anchor="middle" font-family="DejaVu Sans"
        font-weight="bold" font-size="52" fill="#ffffff">PD</text>
```

- [ ] **Step 4: Проверить, что одиночной монограммы «P» не осталось**

Run: `grep -n '>P<' assets/branding/*.svg`
Expected: пустой вывод (ни одной одиночной `P` как содержимого тега).

- [ ] **Step 5: Перегенерировать производные PNG**

Run: `bash scripts/gen-branding.sh`
Expected: скрипт печатает список пяти PNG (три в `.../branding/purad/` и копию
в `.../pixmaps/`) без ошибок.

- [ ] **Step 6: Проверить, что PNG обновились**

Run: `git status --short config/includes.chroot`
Expected: изменены ровно 4 файла PNG (`branding/purad/purad-logo.png`,
`welcome.png`, `slide1.png`, `pixmaps/purad-logo.png`).

- [ ] **Step 7: Визуально проверить вписывание «PD»**

Run: `rsvg-convert -o /tmp/pd-logo.png assets/branding/purad-logo.svg && rsvg-convert -o /tmp/pd-welcome.png assets/branding/purad-welcome.svg`
Открыть оба PNG и убедиться, что «PD» целиком внутри квадрата, с полями по
бокам, полоска не пересекает буквы. (Ручная проверка — автотестов у ассетов нет.)

- [ ] **Step 8: Commit**

```bash
git add assets/branding/purad-logo.svg assets/branding/purad-welcome.svg \
        assets/branding/purad-slide1.svg config/includes.chroot
git commit -m "branding: монограмма P → PD во всех исходниках и PNG"
```

---

### Task 2: Страница `site/index.html`

**Files:**
- Create: `site/index.html`

**Interfaces:**
- Consumes: логотип `assets/branding/purad-logo.svg` (Task 1) по относительному
  пути `../assets/branding/purad-logo.svg`.
- Produces: готовую страницу `site/index.html` — самодостаточную и офлайновую.

- [ ] **Step 1: Создать `site/index.html` — каркас, стили и секции**

Собрать один файл: `<!DOCTYPE html>`, `<html lang="ru">`, `<head>` с
`<meta charset="utf-8">`, `<meta name="viewport" content="width=device-width, initial-scale=1">`,
`<title>PuraD</title>`, `<link rel="icon" type="image/svg+xml" href="../assets/branding/purad-logo.svg">`
и `<style>` со всеми стилями. `<body>` содержит `header`, `main` (секции), `footer`.

Тексты и значения (пиннинг из спеки):

- **Шапка** — `<header>`: логотип `<img src="../assets/branding/purad-logo.svg" alt="PuraD" width="40" height="40">`,
  название `PuraD`, навигация-якоря: `#features` (Особенности), `#download`
  (Скачать), `#docs` (Документация). Позиция `sticky`.
- **Герой** — `<section id="top">`: `<h1>PuraD</h1>`, слоган
  «Live-дистрибутив на базе чистого Debian с KDE Plasma», абзац-описание 1–2
  предложения о лив-CD с KDE Plasma и установке на ext4/btrfs без сторонних
  репозиториев. Кнопки:
  - «Скачать ISO» → `<a href="#" class="btn btn-primary">` + `<!-- TODO: URL Releases -->`;
  - «GitHub» → `<a href="#" class="btn">` + `<!-- TODO: URL репозитория -->`.
- **Особенности** — `<section id="features">` с заголовком «Ключевые особенности»
  и сеткой карточек (CSS Grid `repeat(auto-fit, minmax(240px, 1fr))`) из шести
  пунктов: «Чистый Debian» (только `main`, `contrib`, `non-free-firmware`),
  «KDE Plasma 6», «ext4 и btrfs из коробки», «Wi-Fi и GPU-прошивки в образе»,
  «Снимки btrfs» (Timeshift + grub-btrfs), «Воспроизводимая сборка» (podman).
- **Как скачать/собрать** — `<section id="download">`: абзац со ссылкой на
  Releases (заглушка `#` + `<!-- TODO: URL Releases -->`) и блок `<pre><code>`
  с командами:

```text
make iso TARGET=trixie
make run-install TARGET=trixie
```

- **Документация** — `<section id="docs">`: ссылки на `README.md` и `docs/`
  (заглушки `#` + `<!-- TODO: URL репозитория -->`).
- **Футер** — `<footer>`: `PuraD`, версия `2026.11.09`, текущий год.

Оформление: тёмная тема, акцентный градиент `#1f7fb8 → #0b2e46` (например, в
фоне героя), акцентная полоска `#8fd0f0`; mobile-first; видимый фокус
(`:focus-visible`); блок `@media (prefers-reduced-motion: reduce)` отключает
анимации. Никаких фиксированных ширин, вызывающих горизонтальный скролл.

- [ ] **Step 2: Проверить, что внешних ресурсов нет**

Run: `grep -nE 'https?://|@import|fonts\.googleapis|cdn\.' site/index.html`
Expected: пустой вывод (все ссылки — якоря, заглушки, локальные пути).

- [ ] **Step 3: Проверить, что у каждой заглушки есть пометка TODO**

Run: `grep -c 'href="#"' site/index.html && grep -c 'TODO: URL' site/index.html`
Expected: оба числа равны — количество `href="#"` совпадает с количеством
пометок `TODO: URL` (5 и 5 ожидаемо: 2 в герое, 1 в блоке скачивания, 2 в
документации).

- [ ] **Step 4: Проверить, что путь к логотипу разрешается**

Run: `cd site && test -f ../assets/branding/purad-logo.svg && echo OK`
Expected: `OK`.

- [ ] **Step 5: Открыть страницу и проверить вручную**

Run: `xdg-open site/index.html`
Проверить: логотип отображается; все якоря навигации прокручивают к секциям;
на ширине ~360 px (или в режиме мобильного) нет горизонтальной прокрутки;
`prefers-reduced-motion` не ломает вид.

- [ ] **Step 6: Commit**

```bash
git add site/index.html
git commit -m "site: страница-визитка PuraD"
```
