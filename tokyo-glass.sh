#!/usr/bin/env bash
#
# tokyo-glass — one-install Tokyo Night + Slot Dark Icons + Aura Glass blend.
#
# Compiles Tokyonight from SCSS, installs Slot-Dark-Icons + Slot-Dark-Plasma
# system icons, the Annotation Mono Bold Nerd Font, pastel border CSS, and
# a Tokyo Night-tuned dconf preset. Complements aura-glass if present.
#
# Repo root: $(dirname "$0")
# Assets shipped inside this repo under assets/:
#   assets/Slot-Dark-Icons.tar.xz
#   assets/Slot-Dark-Plasma.tar.gz
#   assets/AnnotationMono.zip
#
# Native Tokyonight SCSS lives under themes/src/ (upstream checkout).
#
set -euo pipefail

# ── paths (all relative to repo root) ─────────────────────────────────────
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Assets shipped inside this repo under assets/ — no network needed.
ICONS_TARBALL="$REPO_ROOT/assets/Slot-Dark-Icons.tar.xz"
PLASMA_TARBALL="$REPO_ROOT/assets/Slot-Dark-Plasma.tar.gz"
FONT_ZIP="$REPO_ROOT/assets/AnnotationMono.zip"

# Native Tokyonight SCSS.
TOKYO_SOURCE="$REPO_ROOT/themes/src"
TOKYO_MAIN="$TOKYO_SOURCE/main"
TOKYO_SASS="$TOKYO_SOURCE/sass"

# Destinations
ICON_DEST="$HOME/.local/share/icons/Slot-Dark-Icons"
PLASMA_DEST="$HOME/.local/share/icons/Slot-Dark-Plasma-system"
THEME_DEST="$HOME/.local/share/themes/Tokyo-Night"
FONT_DEST="$HOME/.local/share/fonts"
CONFIG_DIR="$HOME/.config/aura-glass"   # install into aura-glass's config dir
CONF_DIR="${CONFIG_DIR:-$HOME/.config/tokyo-glass}"
CSS_DEST="$HOME/.config/gtk-4.0"
SHELL_CSS_DEST="$HOME/.themes/Tokyo-Night/gnome-shell"

# ── flags ────────────────────────────────────────────────────────────────
DRY_RUN="${DRY_RUN:-0}"
FORCE="${FORCE:-0}"
BG_STYLE="${BG_STYLE:-default}"        # default | moon | storm
PASTEL_BORDERS="${PASTEL_BORDERS:-1}"  # 1 = on (default)
INSTALL_ICONS="${INSTALL_ICONS:-1}"    # 1 = on
INSTALL_PLASMA="${INSTALL_PLASMA:-1}"  # 1 = on
INSTALL_FONT="${INSTALL_FONT:-1}"      # 1 = on
INSTALL_THEME="${INSTALL_THEME:-1}"    # 1 = on
INSTALL_CSS="${INSTALL_CSS:-1}"        # 1 = on
INSTALL_DCONF="${INSTALL_DCONF:-1}"    # 1 = on
UPDATE_AURA_GLASS="${UPDATE_AURA_GLASS:-1}"  # copy CSS into aura-glass config if present

usage() {
    cat <<EOF
tokyo-glass — Tokyo Night theme + Slot Dark Icons + pastel borders.
Repo: $REPO_ROOT

  ${C_BLD}usage${C_OFF}
    ./tokyo-glass.sh [options]

  ${C_BLD}options${C_OFF}
    --dry-run              print what would happen, change nothing
    --force                reinstall even if already present
    --bg-style STYLE       default | moon | storm (default: default)
    --no-pastel-borders    skip the pastel border CSS
    --no-icons             skip Slot-Dark-Icons installation
    --no-plasma-icons      skip Slot-Dark-Plasma system icons
    --no-font              skip Annotation Mono Bold font
    --no-theme             skip Tokyonight theme compilation
    --no-css               skip pastel border CSS
    --no-dconf             skip dconf preset
    --help                 this message

  ${C_BLD}defaults${C_OFF}
    bg-style:     default
    pastel-borders: on
    icons:        on
    plasma-icons: on
    font:         on
    theme:        on
    css:          on
    dconf:        on

  ${C_BLD}after installing${C_OFF}
    Log out and back in for GNOME Shell changes to take effect.
    Run tokyo-glass.sh --dry-run first to preview.
EOF
}

# ── helpers ──────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_DIM=$'\033[2m'; C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'
    C_YEL=$'\033[0;33m'; C_BLU=$'\033[0;34m'; C_BLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_DIM=''; C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_BLD=''; C_OFF=''
fi

step()  { printf '\n%s==>%s %s%s%s\n' "$C_BLU" "$C_OFF" "$C_BLD" "$*" "$C_OFF"; }
info()  { printf '    %s\n' "$*"; }
ok()    { printf '    %s✓%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
warn()  { printf '    %s!%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
skip()  { printf '    %s·%s %s%s%s\n' "$C_DIM" "$C_OFF" "$C_DIM" "$*" "$C_OFF"; }
die()   { printf '\n%serror:%s %s\n\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

run() {
    if [ "${DRY_RUN:-0}" = 1 ]; then
        printf '    %sdry-run:%s %s\n' "$C_DIM" "$C_OFF" "$*"
        return 0
    fi
    "$@"
}

# ── parse flags ──────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)   DRY_RUN=1; shift ;;
        --force)     FORCE=1; shift ;;
        --bg-style)  BG_STYLE="$2"; shift 2 ;;
        --bg-style=*) BG_STYLE="${1#*=}"; shift ;;
        --no-pastel-borders) PASTEL_BORDERS=0; shift ;;
        --no-icons)  INSTALL_ICONS=0; shift ;;
        --no-plasma-icons) INSTALL_PLASMA=0; shift ;;
        --no-font)   INSTALL_FONT=0; shift ;;
        --no-theme)  INSTALL_THEME=0; shift ;;
        --no-css)    INSTALL_CSS=0; shift ;;
        --no-dconf)  INSTALL_DCONF=0; shift ;;
        --help)      usage; exit 0 ;;
        *)           usage; die "unknown option: $1" ;;
    esac
done

# Validate bg-style
case "$BG_STYLE" in
    default|moon|storm) ;;
    *) die "unknown --bg-style '$BG_STYLE' — pick default, moon, or storm" ;;
esac

# ── preflight ────────────────────────────────────────────────────────────
step "Checking environment"

have() { command -v "$1" >/dev/null 2>&1; }

if ! have sassc; then
    die "sassc is required to compile Tokyonight from SCSS. Install it (pacman -S sassc / apt install sassc)."
fi

if ! have bsdtar && ! have tar; then
    die "bsdtar or tar is required to extract the icon archives."
fi

if ! have unzip; then
    die "unzip is required to extract the font archive."
fi

if ! have gsettings; then
    warn "gsettings not found — dconf preset will be skipped"
    INSTALL_DCONF=0
fi

if [ "${INSTALL_THEME:-1}" = 1 ]; then
    if [ ! -f "$TOKYO_MAIN/gnome-shell/gnome-shell-Dark.scss" ]; then
        die "Tokyonight source not found at $TOKYO_MAIN (expected gnome-shell-Dark.scss)"
    fi
    if [ ! -f "$TOKYO_SASS/_tweaks.scss" ]; then
        die "Tokyonight SCSS not found at $TOKYO_SASS/_tweaks.scss"
    fi
fi

if [ "${INSTALL_ICONS:-1}" = 1 ]; then
    if [ ! -f "$ICONS_TARBALL" ]; then
        die "Slot-Dark-Icons tarball not found at $ICONS_TARBALL"
    fi
fi

if [ "${INSTALL_PLASMA:-1}" = 1 ]; then
    if [ ! -f "$PLASMA_TARBALL" ]; then
        die "Slot-Dark-Plasma tarball not found at $PLASMA_TARBALL"
    fi
fi

if [ "${INSTALL_FONT:-1}" = 1 ]; then
    if [ ! -f "$FONT_ZIP" ]; then
        die "AnnotationMono font zip not found at $FONT_ZIP"
    fi
fi

ok "environment check passed"

# ── 1. Compile Tokyonight theme ──────────────────────────────────────────
if [ "${INSTALL_THEME:-1}" = 1 ]; then
    step "Compiling Tokyonight theme (SCSS → CSS)"

    theme_dir="$HOME/.local/share/themes/Tokyo-Night"
    shell_dir="$theme_dir/gnome-shell"
    gtk4_dir="$HOME/.config/gtk-4.0"
    gtk3_dir="$HOME/.config/gtk-3.0"

    # Create directories (needed even in dry-run for heredoc writes)
    if [ "${DRY_RUN:-0}" = 0 ]; then
        run mkdir -p "$theme_dir" "$shell_dir" "$gtk4_dir" "$gtk3_dir"
    else
        info "dry-run: would mkdir -p $theme_dir $shell_dir $gtk4_dir $gtk3_dir"
    fi

    # Pick the color palette SCSS based on bg-style
    palette_import="_color-palette-$BG_STYLE.scss"
    if [ ! -f "$TOKYO_SASS/$palette_import" ]; then
        warn "palette $palette_import not found, falling back to default"
        palette_import="_color-palette-default.scss"
    fi

    # Build a temporary tweaks override — placed IN the sass dir so
    # sassc's import resolution finds it. Back up + restore the original
    # so repeated runs are safe.
    # The override is named 'tweaks-temp.scss' (no underscore, no prefix)
    # because _colors.scss imports 'tweaks-temp' — matching that name
    # lets the import chain resolve without extra -I flags.
    tweaks_dir="$TOKYO_SASS"
    tweaks_bak="$tweaks_dir/_tweaks.scss.bak"
    tweaks_override="$tweaks_dir/tweaks-temp.scss"

    # Ensure common-temp.scss exists (some Tokyonight checkouts are missing it)
    if [ ! -f "$tweaks_dir/gnome-shell/common-temp.scss" ] && \
       [ -f "$tweaks_dir/gnome-shell/_common.scss" ]; then
        run cp "$tweaks_dir/gnome-shell/_common.scss" \
               "$tweaks_dir/gnome-shell/common-temp.scss"
        ok "created missing common-temp.scss"
    fi

    # Remove stale common-temp (no extension) if present — sassc can't
    # disambiguate between common-temp and common-temp.scss otherwise.
    if [ -f "$tweaks_dir/gnome-shell/common-temp" ]; then
        run rm -f "$tweaks_dir/gnome-shell/common-temp"
        info "removed stale common-temp (no extension)"
    fi

    if [ "${DRY_RUN:-0}" = 0 ]; then
        run cp "$tweaks_dir/_tweaks.scss" "$tweaks_bak"
        run cp "$tweaks_dir/_tweaks.scss" "$tweaks_override"
        # Replace the palette import line
        run sed -i "s|@import 'color-palette-default'|@import '$palette_import'|" "$tweaks_override"
    else
        info "dry-run: would create tweaks override with palette $palette_import"
    fi

    # Also set $colorscheme if needed (moon/storm)
    if [ "$BG_STYLE" = "moon" ]; then
        if [ "${DRY_RUN:-0}" = 0 ]; then
            run sed -i "s|\\\\\\$colorscheme: 'default'|\\\\\\$colorscheme: 'moon'|" "$tweaks_override"
        fi
    elif [ "$BG_STYLE" = "storm" ]; then
        if [ "${DRY_RUN:-0}" = 0 ]; then
            run sed -i "s|\\\\\\$colorscheme: 'default'|\\\\\\$colorscheme: 'storm'|" "$tweaks_override"
        fi
    fi

    # Compile gnome-shell
    shell_scss="$TOKYO_MAIN/gnome-shell/gnome-shell-Dark.scss"
    shell_css="$shell_dir/gnome-shell.css"

    # sassc needs the import path to find both the sass/ directory
    # AND the tweaks override. Two -I flags: first for source structure,
    # second for the sass/ directory where common-temp lives.
    run sassc -M -t expanded \
        -I "$TOKYO_SOURCE" \
        -I "$TOKYO_SASS" \
        "$shell_scss" "$shell_css"

    ok "gnome-shell.css compiled → $shell_css"

    # Compile GTK4
    gtk4_scss="$TOKYO_MAIN/gtk-4.0/gtk-Dark.scss"
    gtk4_css="$gtk4_dir/gtk-dark.css"

    run sassc -M -t expanded \
        -I "$TOKYO_SOURCE" \
        -I "$TOKYO_SASS" \
        "$gtk4_scss" "$gtk4_css"

    ok "gtk-dark.css compiled → $gtk4_css"

    # Compile GTK3
    gtk3_scss="$TOKYO_MAIN/gtk-3.0/gtk-Dark.scss"
    gtk3_css="$gtk3_dir/gtk-dark.css"

    if [ "${DRY_RUN:-0}" = 0 ]; then
        run mkdir -p "$gtk3_dir"
        run sassc -M -t expanded \
            -I "$TOKYO_SOURCE" \
            -I "$TOKYO_SASS" \
            "$gtk3_scss" "$gtk3_css"
    else
        info "dry-run: would compile GTK3 → $gtk3_css"
    fi

    ok "gtk-dark.css compiled → $gtk3_css"

    # Copy GTK4 light variant for completion
    run sassc -M -t expanded \
        -I "$TOKYO_SOURCE" \
        -I "$TOKYO_SASS" \
        "$TOKYO_MAIN/gtk-4.0/gtk.scss" \
        "$gtk4_dir/gtk.css"

    # Copy index.theme
    if [ "${DRY_RUN:-0}" = 0 ]; then
        cat > "$theme_dir/index.theme" <<THEMEEOF
[Desktop Entry]
Type=X-GNOME-Metatheme
Name=Tokyo-Night
Comment=Tokyo Night theme — compiled from SCSS

[X-GNOME-Metatheme]
GtkTheme=Tokyo-Night
MetacityTheme=Tokyo-Night
IconTheme=Slot-Dark-Icons
CursorTheme=Adwaita
THEMEEOF
        ok "index.theme written"
    else
        info "dry-run: would write index.theme → $theme_dir/index.theme"
    fi

    # Copy pad-osd.css for GNOME Shell
    if [ -f "$TOKYO_MAIN/gnome-shell/pad-osd.css" ]; then
        run cp "$TOKYO_MAIN/gnome-shell/pad-osd.css" "$shell_dir/"
        ok "pad-osd.css copied"
    fi

    # Restore the original _tweaks.scss
    if [ -f "$tweaks_bak" ]; then
        run mv "$tweaks_bak" "$tweaks_dir/_tweaks.scss"
        run rm -f "$tweaks_override"
    fi
fi

# ── 2. Install Slot-Dark-Icons ───────────────────────────────────────────
if [ "${INSTALL_ICONS:-1}" = 1 ]; then
    step "Installing Slot-Dark-Icons ($ICONS_TARBALL)"

    # Extract into ~/.local/share/icons/Slot-Dark-Icons
    run mkdir -p "$HOME/.local/share/icons"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: extract $ICONS_TARBALL → $ICON_DEST"
    else
        # Remove existing if --force
        if [ "${FORCE:-0}" = 1 ] && [ -d "$ICON_DEST" ]; then
            run rm -rf "$ICON_DEST"
        fi

        if [ -d "$ICON_DEST" ] && [ "${FORCE:-0}" = 0 ]; then
            skip "$ICON_DEST already exists (use --force to reinstall)"
        else
            run bsdtar -xf "$ICONS_TARBALL" -C "$HOME/.local/share/icons/" 2>/dev/null \
                || run tar -xf "$ICONS_TARBALL" -C "$HOME/.local/share/icons/" 2>/dev/null
            ok "extracted to $ICON_DEST"
        fi

        # Build icon-theme.cache
        if have gtk-update-icon-cache; then
            run gtk-update-icon-cache -qft "$ICON_DEST" 2>/dev/null || true
            ok "icon-theme.cache updated"
        fi
    fi
fi

# ── 3. Install Slot-Dark-Plasma system icons ─────────────────────────────
if [ "${INSTALL_PLASMA:-1}" = 1 ]; then
    step "Installing Slot-Dark-Plasma system icons ($PLASMA_TARBALL)"

    run mkdir -p "$PLASMA_DEST/icons" "$PLASMA_DEST/widgets"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: extract plasma icons → $PLASMA_DEST"
    else
        if [ "${FORCE:-0}" = 1 ] && [ -d "$PLASMA_DEST" ]; then
            run rm -rf "$PLASMA_DEST"
        fi

        if [ -d "$PLASMA_DEST" ] && [ "${FORCE:-0}" = 0 ]; then
            skip "$PLASMA_DEST already exists (use --force to reinstall)"
        else
            # Extract only what we need: icons/ and widgets/ and dialogs/
            run bsdtar -xf "$PLASMA_TARBALL" \
                -C "$PLASMA_DEST/" \
                "Slot-Dark-Plasma/icons/" \
                "Slot-Dark-Plasma/widgets/" \
                "Slot-Dark-Plasma/dialogs/" \
                "Slot-Dark-Plasma/translucent/widgets/" \
                "Slot-Dark-Plasma/solid/widgets/" \
                "Slot-Dark-Plasma/opaque/widgets/" \
                2>/dev/null

            # Rename to flat structure for GTK to find
            run cp -r "$PLASMA_DEST/icons/"* "$PLASMA_DEST/" 2>/dev/null || true
            run cp -r "$PLASMA_DEST/widgets/"* "$PLASMA_DEST/" 2>/dev/null || true

            ok "extracted plasma icons → $PLASMA_DEST"
        fi

        # Build icon-theme.cache
        if have gtk-update-icon-cache; then
            run gtk-update-icon-cache -qft "$PLASMA_DEST" 2>/dev/null || true
            ok "plasma icon-theme.cache updated"
        fi
    fi
fi

# ── 4. Install Annotation Mono Bold Nerd Font ────────────────────────────
if [ "${INSTALL_FONT:-1}" = 1 ]; then
    step "Installing Annotation Mono Bold Nerd Font ($FONT_ZIP)"

    run mkdir -p "$FONT_DEST"

    if [ "${DRY_RUN:-0}" = 1 ]; then
        info "dry-run: extract AnnotationMNerdFontMono-Bold.ttf → $FONT_DEST"
    else
        # Extract just the Mono Bold variant
        run unzip -o -j "$FONT_ZIP" \
            "AnnotationMNerdFontMono-Bold.ttf" \
            "AnnotationMNerdFontMono-BoldItalic.ttf" \
            -d "$FONT_DEST/" 2>/dev/null

        # Rename to canonical name
        run mv "$FONT_DEST/AnnotationMNerdFontMono-Bold.ttf" \
            "$FONT_DEST/AnnotationMono-Bold.ttf" 2>/dev/null || true
        run mv "$FONT_DEST/AnnotationMNerdFontMono-BoldItalic.ttf" \
            "$FONT_DEST/AnnotationMono-BoldItalic.ttf" 2>/dev/null || true

        ok "font installed → $FONT_DEST"
    fi

    # Reconfigure font cache
    if have fc-cache; then
        run fc-cache -f "$FONT_DEST/" 2>/dev/null || true
        ok "font cache updated"
    fi

    # Set as interface font via gsettings
    if have gsettings; then
        run gsettings set org.gnome.desktop.interface font "Annotation Mono Bold" 2>/dev/null || \
            run gsettings set org.gnome.desktop.interface font "AnnotationMono Bold" 2>/dev/null || \
            warn "could not set font via gsettings (font name may need adjustment)"
        ok "interface font set to Annotation Mono Bold"
    fi
fi

# ── 5. Pastel border CSS ─────────────────────────────────────────────────
if [ "${INSTALL_CSS:-1}" = 1 ] && [ "${PASTEL_BORDERS:-1}" = 1 ]; then
    step "Installing pastel border CSS"

    run mkdir -p "$CONFIG_DIR"

    # Guard shell_pastel write (needed even in dry-run for heredoc)
    if [ "${DRY_RUN:-0}" = 0 ]; then
        run mkdir -p "$CONFIG_DIR"
    else
        info "dry-run: would create $CONFIG_DIR"
    fi

    # Shell pastel borders (appended after Tokyonight's shell.css)
    shell_pastel="$CONFIG_DIR/shell-pastel-borders.css"

    if [ "${DRY_RUN:-0}" = 0 ]; then
        cat > "$shell_pastel" <<'SHELLEOF'
/* Tokyo Night + Slot Dark — pastel border treatment
 * Soft tinted edges on every surface, carried from Slot Dark's
 * accent palette (#67a4ff blue, #008aad teal, #cd87de lavender).
 * These sit *after* the Tokyonight shell.css in the cascade.
 */

/* Window chrome — soft blue edge */
window {
  border: 1px solid rgba(103, 164, 255, 0.14);
}

/* Panel — bottom edge tint */
#panel {
  border-bottom: 1px solid rgba(103, 164, 255, 0.10);
}

/* Popup menus, dialogs, notifications — soft inset edge */
.popup-menu-content,
.datemenu-popover,
.quick-toggle-menu,
.notification-banner,
.modal-dialog,
.end-session-dialog {
  border: 1px solid rgba(183, 198, 205, 0.08);
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.25),
              inset 0 0 0 1px rgba(255, 255, 255, 0.02);
}

/* OSD pill — soft edge */
.osd-window {
  border: 1px solid rgba(103, 164, 255, 0.12);
}

/* Quick Settings rows — subtle track tint */
.quick-settings-row .margin-box {
  border-color: rgba(103, 164, 255, 0.20);
}

/* Volume/brightness apparatus in panel */
#panel .apparatus {
  border-color: rgba(103, 164, 255, 0.15);
}

/* App grid in overview — soft card edge */
.app-grid-window .app-grid {
  border: 1px solid rgba(183, 198, 205, 0.06);
}

/* Search bar */
.search-bar {
  border: 1px solid rgba(103, 164, 255, 0.10);
}

/* Dialogs in overview */
.overview .dialog {
  border: 1px solid rgba(183, 198, 205, 0.08);
}
SHELLEOF
        ok "shell pastel borders → $shell_pastel"
    else
        info "dry-run: would write shell pastel borders → $shell_pastel"
    fi

    # GTK4 pastel borders (appended after Tokyonight's gtk-dark.css)
    gtk4_pastel="$CONFIG_DIR/gtk4-pastel-borders.css"

    if [ "${DRY_RUN:-0}" = 0 ]; then
        cat > "$gtk4_pastel" <<'GTKEOF'
/* Tokyo Night + Slot Dark — pastel border treatment (GTK4)
 * Soft tinted edges on GTK4/libadwaita surfaces.
 * Sit after the Tokyonight gtk-dark.css in the cascade.
 */

/* Entry fields — soft border */
entry,
.text-entry {
  border: 1px solid rgba(103, 164, 255, 0.10);
  border-radius: 6px;
}

/* Buttons — soft accent edge on hover */
button:hover {
  border-color: rgba(103, 164, 255, 0.20);
}

/* Sidebar — pastel edge */
.sidebar {
  border-right: 1px solid rgba(103, 164, 255, 0.12);
}

/* Notebook tabs — soft separator */
notebook > header {
  border-bottom: 1px solid rgba(183, 198, 205, 0.08);
}

/* Combo boxes — soft border */
combobox {
  border: 1px solid rgba(103, 164, 255, 0.10);
}

/* Switch — soft track */
switch {
  border: 1px solid rgba(183, 198, 205, 0.06);
}

/* Menu — soft border */
menu {
  border: 1px solid rgba(183, 198, 205, 0.08);
  border-radius: 8px;
}

/* Popover — soft border */
popover {
  border: 1px solid rgba(183, 198, 205, 0.08);
  border-radius: 12px;
}

/* Toolbar — soft border */
toolbar {
  border-bottom: 1px solid rgba(183, 198, 205, 0.06);
}

/* Statusbar — soft border */
statusbar {
  border-top: 1px solid rgba(183, 198, 205, 0.06);
}

/* Treeview — soft grid lines */
treeview {
  border: 1px solid rgba(183, 198, 205, 0.06);
}

/* Progress bar — soft track */
progressbar {
  border: 1px solid rgba(103, 164, 255, 0.10);
}

/* Scale / slider — soft trough */
scale {
  border: 1px solid rgba(103, 164, 255, 0.08);
}

/* Scrollbar — soft trough */
scrollbar {
  border: 1px solid rgba(183, 198, 205, 0.06);
}

/* Frame — soft border */
frame {
  border: 1px solid rgba(183, 198, 205, 0.08);
  border-radius: 8px;
}

/* Paned — soft sash */
paned {
  border-color: rgba(183, 198, 205, 0.12);
}

/* Color chooser — soft border */
color-chooser {
  border: 1px solid rgba(103, 164, 255, 0.10);
  border-radius: 8px;
}

/* File chooser — soft border */
file-chooser {
  border: 1px solid rgba(183, 198, 205, 0.08);
  border-radius: 8px;
}

/* Dialog — soft border */
dialog {
  border: 1px solid rgba(183, 198, 205, 0.08);
  border-radius: 12px;
}

/* Infobar — soft border */
infobar {
  border: 1px solid rgba(103, 164, 255, 0.12);
  border-radius: 6px;
}

/* Tooltip — soft border */
tooltip {
  border: 1px solid rgba(183, 198, 205, 0.10);
  border-radius: 6px;
}

/* Menubar — soft border */
menubar {
  border-bottom: 1px solid rgba(183, 198, 205, 0.06);
}

/* Action bar — soft border */
action-bar {
  border-top: 1px solid rgba(183, 198, 205, 0.06);
}

/* Floating bar (Libadwaita) — soft border */
floating-bar {
  border: 1px solid rgba(183, 198, 205, 0.08);
  border-radius: 8px;
}

/* Header bar — soft border */
.header-bar {
  border-bottom: 1px solid rgba(183, 198, 205, 0.06);
}

/* Note: libadwaita's @define-color for borders is overridden below.
 * This makes all libadwaita-drawn borders pastel-tinted. */
@define-color border_color rgba(103, 164, 255, 0.12);
@define-color dark_border_color rgba(103, 164, 255, 0.12);
@define-color secondary_border_color rgba(183, 198, 205, 0.08);
GTKEOF
        ok "GTK4 pastel borders → $gtk4_pastel"
    else
        info "dry-run: would write GTK4 pastel borders → $gtk4_pastel"
    fi

    # Link CSS into gtk-4.0 for libadwaita apps
    if [ "${DRY_RUN:-0}" = 0 ]; then
        run mkdir -p "$HOME/.config/gtk-4.0"
        run ln -sf "$gtk4_pastel" "$HOME/.config/gtk-4.0/gtk4-pastel-borders.css" 2>/dev/null || true
    fi

    # Also install into aura-glass config dir if it exists (for aura-glass-apply)
    if [ -d "/home/ftr/Apps/Gnome/aura-glass" ] && [ -d "$HOME/.config/aura-glass" ]; then
        if [ "${DRY_RUN:-0}" = 0 ]; then
            run cp "$shell_pastel" "/home/ftr/Apps/Gnome/aura-glass/css/shell-pastel-borders.css" 2>/dev/null || true
            run cp "$gtk4_pastel" "/home/ftr/Apps/Gnome/aura-glass/css/gtk4-pastel-borders.css" 2>/dev/null || true
            ok "copies placed in aura-glass css/ for merge into aura-glass-apply"
        else
            info "dry-run: would copy CSS into aura-glass css/"
        fi
    fi
fi

# ── 6. dconf preset ──────────────────────────────────────────────────────
if [ "${INSTALL_DCONF:-1}" = 1 ] && have dconf; then
    step "Installing Tokyo Night dconf preset"

    # Guard dconf write (needed even in dry-run for heredoc)
    if [ "${DRY_RUN:-0}" = 0 ]; then
        run mkdir -p "$CONF_DIR"
    else
        info "dry-run: would create $CONF_DIR"
    fi

    dconf_file="$CONF_DIR/tokyo-night.ini"

    if [ "${DRY_RUN:-0}" = 0 ]; then
        cat > "$dconf_file" <<'DCONFEOF'
[org/gnome/shell/extensions/openbar]
accent-color=['0.17', '0.64', '0.91']
bgcolor=['0.10', '0.11', '0.15']
fgcolor=['0.66', '0.69', '0.84']
dark-accent-color=['0.17', '0.64', '0.91']
dark-bgcolor=['0.10', '0.11', '0.15']
dark-fgcolor=['0.66', '0.69', '0.84']
apply-all-shell=true
apply-menu-notif=true
apply-menu-shell=true
color-scheme='prefer-dark'
bartype='Floating'
balpha=0.01
bgalpha=0.01
bcolor=['0.40', '0.40', '0.40']
bgcolor=['0.10', '0.11', '0.15']
font='Annotation Mono Bold 10'
height=38.0
margin=5.0
position='Top'
winbcolor=['0.133', '0.216', '0.380']
window-hint=0

[org/gnome/shell/extensions/blur-my-shell]
hacks-level=2
settings-version=2

[org/gnome/shell/extensions/blur-my-shell/panel]
blur=true
brightness=0.6
sigma=30
static-blur=true
corner-radius=0
override-background=true

[org/gnome/shell/extensions/blur-my-shell/popup]
blur=true
sigma=30
brightness=0.6
corner-radius=20
menu-corner-radius=26
quick-settings-corner-radius=33
notification-corner-radius=20
osd-corner-radius=12
dialog-corner-radius=20
override-background=false
style-popup=2

[org/gnome/shell/extensions/blur-my-shell/applications]
blur=true
brightness=1.0
corner-radius=30
opacity=240
sigma=12
enable-all=false
blur-on-overview=false

[org/gnome/shell/extensions/custom-osd]
bg-effect='none'
bgcolor=['0.10', '0.11', '0.15', '1.0']
alpha=60.0
levcolor=['1.0', '1.0', '1.0', '1.0']
levalpha=95.0
levthickness=7.0
hpadding=10.0
vpadding=10.0
size=40.0
bradius=100.0
border=false
shadow=false
rotate=false
DCONFEOF
        fi

    ok "dconf preset → $dconf_file"

    if [ "${DRY_RUN:-0}" = 0 ]; then
        run dconf load /org/gnome/shell/extensions/ < "$dconf_file" 2>/dev/null || \
            warn "dconf load failed (maybe not in a GNOME session)"
    fi
fi

# ── 7. Summary ───────────────────────────────────────────────────────────
step "Done"

cat <<EOF

  ${C_BLD}Tokyo Night Theme:${C_OFF}
    GNOME Shell:  $SHELL_CSS_DEST/gnome-shell.css
    GTK4:         $HOME/.config/gtk-4.0/gtk-dark.css
    GTK3:         $HOME/.config/gtk-3.0/gtk-dark.css
    Variant:      $BG_STYLE

  ${C_BLD}Slot Dark Icons:${C_OFF}
    Location:     $ICON_DEST

  ${C_BLD}Slot Dark Plasma System Icons:${C_OFF}
    Location:     $PLASMA_DEST

  ${C_BLD}Annotation Mono Bold Nerd Font:${C_OFF}
    Location:     $FONT_DEST

  ${C_BLD}Pastel Border CSS:${C_OFF}
    Shell:        $CONFIG_DIR/shell-pastel-borders.css
    GTK4:         $CONFIG_DIR/gtk4-pastel-borders.css
    Status:       $([ "${PASTEL_BORDERS:-1}" = 1 ] && echo "enabled" || echo "disabled")

  ${C_BLD}dconf Preset:${C_OFF}
    Location:     $CONF_DIR/tokyo-night.ini

  ${C_BLD}Next step:${C_OFF}
    Log out and back in for GNOME Shell changes to take effect.
    Run: gsettings set org.gnome.desktop.interface icon-theme 'Slot-Dark-Icons'
    Run: gsettings set org.gnome.shell.extensions.openbar theme 'Tokyo-Night'

EOF

if [ "${DRY_RUN:-0}" = 1 ]; then
    info "dry-run complete — no files were modified"
fi
