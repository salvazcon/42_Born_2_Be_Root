# Born_2_be_root - 11/10/2022

!# Just the Born_2_be_root :)

Documentacion - https://drive.google.com/drive/folders/1W3xtPNuVMlD9KfL1pCW4qMHRBYVVNFG8?usp=share_link


"""
Theme.py

Light/dark mode for the whole GUI.

- THEME holds the colors of the active mode. Widgets created with explicit colors must take them from here
  (THEME.panel, THEME.field...) instead of fixed values like "white", so new widgets follow the active mode.
- set_dark_mode(root, dark) switches mode: recolors every existing tk widget (mapping each color of the old
  palette to the same role in the new one), restyles ttk widgets and updates the defaults for new widgets.

Call init_theme(root) once, right after creating the Tk root and before building the GUI.
"""
import tkinter as tk
from tkinter import ttk

# Colors of each mode, by role. Light values for bg/fg/field/menu are replaced by the system defaults in init_theme()
LIGHT = dict(
    bg="#f0f0f0",           # windows, frames, labels
    fg="#000000",           # text
    panel="#ffffff",        # white areas: message viewer, iteration cards, dropdown button
    field="#ffffff",        # editable fields (tk Entry/Text)
    field_fg="#000000",
    disabled="#C9C9C9",     # disabled text area (data file editor)
    error="#FFCCCC",        # invalid value
    modified="#ffeab0",     # value edited but not applied yet
    ghost="#E8E8E8",        # iteration being dragged
    hover="#CCE8FF",        # dropdown button under the mouse
    border="#A0A0A0",       # message cards border
    select="#A3CBE3",       # selected text
    highlight="yellow",     # search results in the data file editor
    menu_bg="#f0f0f0",
    menu_fg="#000000",
)
DARK = dict(
    bg="#2d2d30",
    fg="#e6e6e6",
    panel="#252526",
    field="#252526",
    field_fg="#e6e6e6",
    disabled="#3a3a3a",
    error="#6e2a2a",
    modified="#6b5a1e",
    ghost="#444444",
    hover="#2f4f6f",
    border="#5a5a5a",
    select="#3d6a8a",
    highlight="#8a7a00",
    menu_bg="#2d2d30",
    menu_fg="#e6e6e6",
)
_DARK_TTK = dict(button="#3a3a3a", button_active="#4a4a4a", field="#3c3f41", disabled_fg="#7a7a7a")

# tk color options and the palette roles they can take
_FG_OPTIONS = ("foreground", "activeforeground", "insertbackground", "selectforeground",
               "disabledforeground", "highlightcolor")
_BG_OPTIONS = ("background", "activebackground", "highlightbackground", "selectbackground",
               "readonlybackground", "troughcolor", "selectcolor")
_FG_ROLES = ("fg", "field_fg", "menu_fg")
_FIELD_CLASSES = ("Entry", "Text", "Spinbox", "Listbox")


class _Theme:
    """ Colors of the active mode, as attributes (THEME.bg, THEME.panel...). It is always the same object,
    so modules that did `from Theme import THEME` see the change of mode"""

    def __init__(self):
        self.dark = False
        self._use(LIGHT, False)

    def _use(self, palette: dict, dark: bool):
        self.__dict__.update(palette)
        self.dark = dark


THEME = _Theme()
_state = {"light_ttk_theme": None}


def init_theme(root: tk.Misc):
    """ Takes the system default colors as the light palette. Call it once, before building the GUI"""
    style = ttk.Style(root)
    _state["light_ttk_theme"] = style.theme_use()
    label, entry, menu = tk.Label(root), tk.Entry(root), tk.Menu(root)
    LIGHT.update(bg=str(label.cget("bg")), fg=str(label.cget("fg")), field=str(entry.cget("bg")),
                 field_fg=str(entry.cget("fg")), menu_bg=str(menu.cget("bg")), menu_fg=str(menu.cget("fg")))
    for probe in (label, entry, menu):
        probe.destroy()
    THEME._use(LIGHT, False)
    _apply_option_db(root, LIGHT)


def set_dark_mode(root: tk.Misc, dark: bool):
    """ Switches the whole GUI (every open window) to dark or light mode"""
    if dark == THEME.dark:
        return
    old, new = (LIGHT, DARK) if dark else (DARK, LIGHT)
    THEME._use(new, dark)
    _apply_ttk(root, dark)
    _apply_option_db(root, new)
    _recolor_tree(root, old, new)


# ------------------------------------------------------------------------------------------------
def _apply_option_db(root: tk.Misc, c: dict):
    """ Default colors for tk widgets created from now on"""
    for pattern, value in (
        ("*Background", c["bg"]), ("*Foreground", c["fg"]),
        ("*activeBackground", c["bg"]), ("*activeForeground", c["fg"]),
        ("*highlightBackground", c["bg"]), ("*highlightColor", c["fg"]),
        ("*selectBackground", c["select"]), ("*selectForeground", c["fg"]),
        ("*insertBackground", c["fg"]),
        ("*Entry.Background", c["field"]), ("*Entry.Foreground", c["field_fg"]),
        ("*Text.Background", c["field"]), ("*Text.Foreground", c["field_fg"]),
        ("*Listbox.Background", c["field"]), ("*Listbox.Foreground", c["field_fg"]),
        ("*Menu.Background", c["menu_bg"]), ("*Menu.Foreground", c["menu_fg"]),
        ("*Menu.activeBackground", c["select"]), ("*Menu.activeForeground", c["fg"]),
        ("*TCombobox*Listbox.background", c["field"]), ("*TCombobox*Listbox.foreground", c["field_fg"]),
        ("*TCombobox*Listbox.selectBackground", c["select"]),
    ):
        root.option_add(pattern, value)


def _apply_ttk(root: tk.Misc, dark: bool):
    style = ttk.Style(root)
    if not dark:
        style.theme_use(_state["light_ttk_theme"])
    else:
        c, t = DARK, _DARK_TTK
        style.theme_use("clam")  # the Windows native themes ignore custom colors
        style.configure(".", background=c["bg"], foreground=c["fg"], fieldbackground=t["field"],
                        bordercolor=c["border"], lightcolor=c["bg"], darkcolor=c["bg"], troughcolor=c["panel"],
                        selectbackground=c["select"], selectforeground=c["fg"], insertcolor=c["fg"],
                        arrowcolor=c["fg"])
        style.map(".", background=[("disabled", c["bg"])], foreground=[("disabled", t["disabled_fg"])])
        style.configure("TButton", background=t["button"])
        style.map("TButton", background=[("pressed", c["select"]), ("active", t["button_active"]),
                                         ("disabled", c["bg"])])
        style.map("TCombobox", fieldbackground=[("readonly", t["field"]), ("disabled", c["bg"])],
                  foreground=[("readonly", c["fg"]), ("disabled", t["disabled_fg"])],
                  selectbackground=[("readonly", t["field"])], selectforeground=[("readonly", c["fg"])])
        style.map("TEntry", fieldbackground=[("disabled", c["bg"]), ("readonly", c["bg"])])
        style.configure("Treeview", background=c["panel"], fieldbackground=c["panel"], foreground=c["fg"])
        style.configure("Treeview.Heading", background=t["button"], foreground=c["fg"])
        style.map("Treeview", background=[("selected", c["select"])], foreground=[("selected", c["fg"])])
    # Custom styles are stored per ttk theme: define them again after switching
    style.configure("Center.TButton", anchor="center", justify="center")


def _recolor_tree(root: tk.Misc, old: dict, new: dict):
    rgb_cache = {}

    def rgb(color):
        color = str(color)
        if color not in rgb_cache:
            try:
                rgb_cache[color] = root.winfo_rgb(color) if color else None
            except tk.TclError:
                rgb_cache[color] = None
        return rgb_cache[color]

    roles_by_rgb = {}
    for role, color in old.items():
        roles_by_rgb.setdefault(rgb(color), []).append(role)

    def new_color(color, option, wclass):
        roles = roles_by_rgb.get(rgb(color))
        if not roles:
            return None  # a color outside the palette (e.g. Running/Stopped labels): keep it
        if option in _FG_OPTIONS:
            roles = [r for r in roles if r in _FG_ROLES]
            prefer = ("field_fg",) if wclass in _FIELD_CLASSES else ("menu_fg",) if wclass == "Menu" else ("fg",)
        else:
            roles = [r for r in roles if r not in _FG_ROLES]
            if option == "selectbackground":
                prefer = ("select",)
            elif wclass in _FIELD_CLASSES:
                prefer = ("field", "panel")
            elif wclass == "Menu":
                prefer = ("menu_bg",)
            else:
                prefer = ("bg", "panel")
        if not roles:
            return None
        role = next((r for r in prefer if r in roles), roles[0])
        return new[role]

    def recolor(widget):
        if not isinstance(widget, ttk.Widget):  # ttk widgets follow the ttk style
            wclass = widget.winfo_class()
            keys = widget.keys()
            for option in _FG_OPTIONS + _BG_OPTIONS:
                if option in keys:
                    try:
                        color = new_color(str(widget.cget(option)), option, wclass)
                        if color is not None:
                            widget.configure(**{option: color})
                    except tk.TclError:
                        pass
            if wclass == "Text" and "highlight" in widget.tag_names():
                widget.tag_configure("highlight", background=THEME.highlight)
        for child in widget.winfo_children():
            recolor(child)

    recolor(root)

