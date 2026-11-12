#!/bin/bash
# scripts/test-run-qemu-viewer.sh — проверка выбора способа показа экрана
# в scripts/run-qemu.sh (--viewer/--dry-run). Ничего не запускает.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RUN="${REPO_DIR}/scripts/run-qemu.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

# Без графической сессии auto не должен зависеть от окружения теста.
dry() {
    env -u DISPLAY -u WAYLAND_DISPLAY bash "$RUN" trixie --installed --dry-run "$@"
}

echo "==> фиксированные режимы"
case "$(dry --viewer gtk)" in *"-display gtk"*) ;; *) fail "--viewer gtk" ;; esac
case "$(dry --viewer spice)" in *"-display spice-app"*) ;; *) fail "--viewer spice" ;; esac
case "$(dry --viewer vnc)" in *"-vnc 127.0.0.1:0"*) ;; *) fail "--viewer vnc" ;; esac
case "$(dry --viewer none)" in *"-display none"*) ;; *) fail "--viewer none" ;; esac
case "$(dry --viewer=spice)" in *"-display spice-app"*) ;; *) fail "--viewer=spice" ;; esac

echo "==> auto"
# Без $DISPLAY/$WAYLAND_DISPLAY auto обязан выбрать VNC.
case "$(dry)" in *"-vnc 127.0.0.1:0"*) ;; *) fail "auto без графической сессии должен давать vnc" ;; esac
# С графической сессией auto предпочитает SPICE, если есть remote-viewer.
if command -v remote-viewer >/dev/null 2>&1 && [ -n "${DISPLAY:-}" ]; then
    case "$(bash "$RUN" trixie --installed --dry-run)" in
        *"-display spice-app"*) ;;
        *) fail "auto с сессией и remote-viewer должен давать spice" ;;
    esac
elif qemu-system-x86_64 -display help 2>/dev/null | grep -qx gtk && [ -n "${DISPLAY:-}" ]; then
    case "$(bash "$RUN" trixie --installed --dry-run)" in
        *"-display gtk"*) ;;
        *) fail "auto с сессией и без remote-viewer должен давать gtk" ;;
    esac
fi

echo "==> неверный режим"
if dry --viewer bogus >/dev/null 2>&1; then
    fail "неверный --viewer принят"
fi

echo "==> справка"
bash "$RUN" --help | grep -q -- '--viewer' || fail "нет --viewer в справке"

echo "PASS: run-qemu viewer"
