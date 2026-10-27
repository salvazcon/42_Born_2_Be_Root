# Born_2_be_root - 11/10/2022

!# Just the Born_2_be_root :)

Documentacion - https://drive.google.com/drive/folders/1W3xtPNuVMlD9KfL1pCW4qMHRBYVVNFG8?usp=share_link

# Widgets used to compare the size of each ttk class between light and dark mode
_PROBES = {
    "TButton": lambda root: ttk.Button(root, text="Start"),
    "TEntry": lambda root: ttk.Entry(root, width=7),
    "TCombobox": lambda root: ttk.Combobox(root, width=16),
}


def _measure_probes(root: tk.Misc) -> dict:
    sizes = {}
    for style_name, make in _PROBES.items():
        probe = make(root)
        probe.update_idletasks()
        sizes[style_name] = (probe.winfo_reqwidth(), probe.winfo_reqheight())
        probe.destroy()
    return sizes


def _padding(root: tk.Misc, style: ttk.Style, style_name: str) -> list:
    """ Padding of a style as [left, top, right, bottom] in pixels"""
    pad = style.lookup(style_name, "padding") or 0
    pad = [round(root.winfo_fpixels(str(v))) for v in (pad if isinstance(pad, (tuple, list)) else str(pad).split())]
    pad += [0] * (1 - len(pad))
    left, top = pad[0], pad[1] if len(pad) > 1 else pad[0]
    return [left, top, pad[2] if len(pad) > 2 else left, pad[3] if len(pad) > 3 else top]


def _match_light_sizes(root: tk.Misc, style: ttk.Style):
    """ "clam" uses more padding than the native theme, so buttons and comboboxes grow and the windows get
    wider. Measure each class and reduce its padding (and the combobox arrow) by the difference, so every
    widget keeps the size it had in light mode (also the other way round: padding is added if it is smaller)"""
    style.configure("TButton", width=_state["light_button_width"])  # minimum width of buttons (in chars)
    for _ in range(2):  # a second pass corrects what the first one could not remove (padding already at 0)
        for style_name, (dark_w, dark_h) in _measure_probes(root).items():
            light_w, light_h = _state["light_sizes"][style_name]
            dx, dy = dark_w - light_w, dark_h - light_h  # extra pixels in dark mode
            if not dx and not dy:
                continue
            left, top, right, bottom = _padding(root, style, style_name)
            new = (left - dx // 2, top - dy // 2, right - (dx - dx // 2), bottom - (dy - dy // 2))
            if style_name == "TCombobox" and new[0] < 0:  # no padding left: make the arrow narrower
                arrow = round(root.winfo_fpixels(str(style.lookup(style_name, "arrowsize") or 14)))
                style.configure(style_name, arrowsize=max(arrow + min(new[0], 0) + min(new[2], 0), 8))
            style.configure(style_name, padding=tuple(max(v, 0) for v in new))
