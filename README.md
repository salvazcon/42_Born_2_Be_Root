# Born_2_be_root - 11/10/2022

!# Just the Born_2_be_root :)

Documentacion - https://drive.google.com/drive/folders/1W3xtPNuVMlD9KfL1pCW4qMHRBYVVNFG8?usp=share_link

    new_colors = {}

    def new_color(color, option, wclass):
        key = (color, option, wclass)
        if key not in new_colors:
            new_colors[key] = _role_color(color, option, wclass)
        return new_colors[key]

    def _role_color(color, option, wclass):
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
            try:
                # tk.Misc.configure: read/write every option in one call each (and skip configure() overrides)
                options = tk.Misc.configure(widget)
                changes = {}
                for option in _COLOR_OPTIONS:
                    if option in options:
                        current = str(options[option][-1])
                        color = new_color(current, option, wclass)
                        if color is not None and color != current:
                            changes[option] = color
                if changes:
                    tk.Misc.configure(widget, **changes)
            except tk.TclError:
                pass
            if wclass == "Text" and "highlight" in widget.tag_names():
                widget.tag_configure("highlight", background=THEME.highlight)
        for child in widget.winfo_children():
            recolor(child)
    select="#3d6a8a",
    highlight="#8a7a00",
    menu_bg="#2d2d30",
    menu_fg="#e6e6e6",
)
# Colors of ttk widgets (buttons, comboboxes, ttk entries) in each mode
_LIGHT_TTK = dict(button="#e1e1e1", button_active="#e5f1fb", button_border="#adadad",
                  field="#ffffff", disabled_fg="#a0a0a0")
_DARK_TTK = dict(button="#3a3a3a", button_active="#4a4a4a", button_border="#5a5a5a",
                 field="#3c3f41", disabled_fg="#7a7a7a")

# Size of ttk buttons: the same in both modes. Increase BUTTON_PADDING for bigger buttons, decrease it for smaller
BUTTON_PADDING = (4, 1)     # inner margin (x, y) around the text, in pixels
_ROUND_SIZE = 24            # size of the button image (it is stretched to each button)
_ROUND_RADIUS = 5           # corner radius in pixels

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
_button_images: dict[str, tk.PhotoImage] = {}  # kept alive here, or Tk discards them


def init_theme(root: tk.Misc):
    """ Takes the system default colors as the light palette and sets up the ttk theme.
    Call it once, before building the GUI"""
    label, entry, menu = tk.Label(root), tk.Entry(root), tk.Menu(root)
    LIGHT.update(bg=str(label.cget("bg")), fg=str(label.cget("fg")), field=str(entry.cget("bg")),
                 field_fg=str(entry.cget("fg")), menu_bg=str(menu.cget("bg")), menu_fg=str(menu.cget("fg")))
    for probe in (label, entry, menu):
        probe.destroy()
    THEME._use(LIGHT, False)
    _apply_option_db(root, LIGHT)
    _apply_ttk(root, False)


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
    """ ttk widgets use "clam" in BOTH modes (the native Windows themes ignore custom colors). Only colors are
    changed here: theme, layouts and paddings are the same in both modes, so sizes never change"""
    c, t = (DARK, _DARK_TTK) if dark else (LIGHT, _LIGHT_TTK)
    style = ttk.Style(root)
    if style.theme_use() != "clam":
        style.theme_use("clam")
    style.configure(".", background=c["bg"], foreground=c["fg"], fieldbackground=t["field"],
                    bordercolor=c["border"], lightcolor=c["bg"], darkcolor=c["bg"], troughcolor=c["panel"],
                    selectbackground=c["select"], selectforeground=c["fg"], insertcolor=c["fg"],
                    arrowcolor=c["fg"])
    style.map(".", background=[("disabled", c["bg"])], foreground=[("disabled", t["disabled_fg"])])
    _rounded_buttons(root, style, c, t)
    style.map("TCombobox", fieldbackground=[("readonly", t["field"]), ("disabled", c["bg"])],
              foreground=[("readonly", c["fg"]), ("disabled", t["disabled_fg"])],
              selectbackground=[("readonly", t["field"])], selectforeground=[("readonly", c["fg"])])
    style.map("TEntry", fieldbackground=[("disabled", c["bg"]), ("readonly", c["bg"])])
    style.configure("Treeview", background=c["panel"], fieldbackground=c["panel"], foreground=c["fg"])
    style.configure("Treeview.Heading", background=t["button"], foreground=c["fg"])
    style.map("Treeview", background=[("selected", c["select"])], foreground=[("selected", c["fg"])])
    style.configure("Center.TButton", anchor="center", justify="center")


def _rounded_buttons(root: tk.Misc, style: ttk.Style, c: dict, t: dict):
    """ TButton with rounded corners. The frame of the button is an image (rounded rectangle) that ttk stretches
    to each button. The element is created once; switching mode repaints the same images with the new colors"""
    fills = {"normal": t["button"], "active": t["button_active"], "pressed": c["select"], "disabled": c["bg"]}
    if not _button_images:
        for state in fills:
            _button_images[state] = tk.PhotoImage(master=root, width=_ROUND_SIZE, height=_ROUND_SIZE)
        img = _button_images
        style.element_create("Rounded.button", "image", img["normal"],
                             ("pressed", img["pressed"]), ("active", img["active"]),
                             ("disabled", img["disabled"]), border=_ROUND_RADIUS, padding=2, sticky="nsew")
        style.layout("TButton", [("Rounded.button", {"sticky": "nsew", "children": [
            ("Button.padding", {"sticky": "nsew", "children": [("Button.label", {"sticky": "nsew"})]})]})])
    for state, fill in fills.items():
        _paint_rounded(root, _button_images[state], fill, t["button_border"], c["bg"])
    style.configure("TButton", padding=BUTTON_PADDING, foreground=c["fg"])


def _paint_rounded(root: tk.Misc, img: tk.PhotoImage, fill: str, outline: str, background: str):
    """ Paints a rounded rectangle with a 1px outline and smoothed corners. Pixels outside the corners are
    transparent; the edge of the curve is blended with the window background"""
    size, r = _ROUND_SIZE, _ROUND_RADIUS
    to_rgb = lambda col: tuple(v // 257 for v in root.winfo_rgb(col))
    f, o, b = to_rgb(fill), to_rgb(outline), to_rgb(background)
    mix = lambda c1, c2, k: tuple(round(a + (bb - a) * k) for a, bb in zip(c1, c2))
    transparent, rows = [], []
    for y in range(size):
        row = []
        for x in range(size):
            px, py = x + 0.5, y + 0.5
            dx = max(r - px, 0.0, px - (size - r))
            dy = max(r - py, 0.0, py - (size - r))
            depth = r - (dx * dx + dy * dy) ** 0.5              # distance to the edge (negative = outside)
            alpha = min(max(depth + 0.5, 0.0), 1.0)             # coverage of the shape
            color = mix(o, f, min(max(depth - 0.5, 0.0), 1.0))  # outline at the edge, fill inside
            if alpha <= 0:
                transparent.append((x, y))
            row.append("#%02x%02x%02x" % mix(b, color, alpha))
        rows.append("{" + " ".join(row) + "}")
    img.put(" ".join(rows))
    for x, y in transparent:
        img.transparency_set(x, y, True)


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

