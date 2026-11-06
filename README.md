# Born_2_be_root - 11/10/2022

!# Just the Born_2_be_root :)

Documentacion - https://drive.google.com/drive/folders/1W3xtPNuVMlD9KfL1pCW4qMHRBYVVNFG8?usp=share_link


"""
MessageViewer.py

Message viewer of the Function windows ("Rx Messages") and of the sent messages window ("Sent Messages"):
a list with one message per row and, below it, the detail of the selected message with some values translated
(IPs, status, header timestamp).

While it follows the messages (Pause not pressed) the newest message is selected and shown. Clicking a row (or
pressing Pause) stops on that message; pressing Pause again goes back to the newest one.
"""
import time
import tkinter as tk
from tkinter import ttk

from Constants import *
from Messages import *
from Widgets import MultiSelectDropdown
from Theme import THEME

_STATUS_NAMES = {status.value: name for name, status in STATUS_MAP.items()}

# column id: (heading, width px, anchor)
_COLUMNS = {
    "time":     ("Time", 92, "w"),
    "fid":      ("FID", 38, "e"),
    "function": ("Function", 66, "w"),
    "message":  ("Message", 178, "w"),
    "seq":      ("Seq", 50, "e"),
    "its":      ("Its", 32, "e"),
}
_REFRESH_MS = 100  # the detail and the selection are updated at most every _REFRESH_MS


class MessageViewer(tk.Frame):
    """ List + detail of a list of Messages, with filters by message and FID, Pause and Delete all.

    Args:
        master: parent widget
        msgs_list: messages already received/sent (shown when the viewer is created)
        displayer_name: title of the viewer
        fid_names: callable returning {fid: Function name} of the simulator's Functions (to name the FIDs)
        bd: border of the viewer frame
    """

    def __init__(self, master: tk.Misc, msgs_list: list[Message], displayer_name: str,
                 fid_names: callable = None, bd: int = 2):
        super().__init__(master)
        self._displayer_name = displayer_name
        self._fid_names = fid_names or (lambda: {})
        self._history: list[Message] = []
        self._shown: list[Message] = []  # messages that pass the filters, in the same order as the rows
        self._msg_name_filter_selection = list(MSG_NAME_FILTER_VALUES)
        self._fid_filter_selection: list[str] = []  # filled with the FIDs of the messages (_register_fid)
        self._paused = False
        self._detail_msg: Message = None  # message drawn in the detail
        self._refresh_pending = False

        base_grid = tk.LabelFrame(self, bd=bd, text=displayer_name, font="Verdana 8 bold")
        base_grid.grid(row=0, column=0, sticky="nsew", padx=5, pady=5)
        self._build_list(base_grid)
        self._build_detail(base_grid)
        self._build_controls(base_grid)

        self._load_history(msgs_list)

    # ------------------------------------------------------------------------------------------------
    # Widgets
    # ------------------------------------------------------------------------------------------------
    def _build_list(self, master: tk.Misc):
        frame = tk.Frame(master)
        frame.grid(row=0, column=0, sticky="nsew", padx=10, pady=(10, 5))
        self._tree = ttk.Treeview(frame, columns=list(_COLUMNS), show="headings", height=9, selectmode="browse")
        for column, (heading, width, anchor) in _COLUMNS.items():
            self._tree.heading(column, text=heading, anchor=anchor)
            self._tree.column(column, width=width, minwidth=width, anchor=anchor, stretch=False)
        scrollbar = ttk.Scrollbar(frame, orient="vertical", command=self._tree.yview)
        self._tree.configure(yscrollcommand=scrollbar.set)
        self._tree.grid(row=0, column=0, sticky="nsew")
        scrollbar.grid(row=0, column=1, sticky="ns")
        # only the user's clicks and keys stop on a message (the selection made by the code must not)
        self._tree.bind("<ButtonRelease-1>", self._on_user_select)
        for key in ("Up", "Down", "Prior", "Next", "Home", "End"):
            self._tree.bind(f"<KeyRelease-{key}>", self._on_user_select)

    def _build_detail(self, master: tk.Misc):
        frame = tk.Frame(master)
        frame.grid(row=1, column=0, sticky="nsew", padx=10, pady=5)
        self._detail = tk.Text(frame, height=13, width=68, wrap="none", font="Verdana 8", bd=1, relief="solid",
                               bg=THEME.panel, padx=6, pady=4, cursor="arrow")
        self._detail.tag_configure("title", font=("Verdana", 8, "bold"))
        self._detail.tag_configure("section", font=("Verdana", 8, "bold"))
        self._detail.tag_configure("name", font=("Verdana", 8, "bold"))
        self._detail.tag_configure("raw", foreground=COLOR_GRAY)
        scrollbar = ttk.Scrollbar(frame, orient="vertical", command=self._detail.yview)
        self._detail.configure(yscrollcommand=scrollbar.set)
        self._detail.grid(row=0, column=0, sticky="nsew")
        scrollbar.grid(row=0, column=1, sticky="ns")

    def _build_controls(self, master: tk.Misc):
        frame = tk.Frame(master)
        frame.grid(row=2, column=0, sticky="ew", padx=10, pady=(5, 10))

        tk.Label(frame, text="Filter by Msg:").grid(row=0, column=0, sticky="w", padx=(0, 5))
        MultiSelectDropdown(
            frame, MSG_NAME_FILTER_VALUES, must_have_one=True, show_limit=0, width=1, start_checked=True,
            on_select=lambda e: self._apply_filter(e, is_msg_name_filter=True)
        ).grid(row=0, column=1, sticky="nsew", padx=(0, 15))

        tk.Label(frame, text="Filter by FID:").grid(row=0, column=2, sticky="w", padx=(0, 5))
        self._fid_filter = MultiSelectDropdown(
            frame, [], must_have_one=True, show_limit=0, width=1, start_checked=True,
            on_select=lambda e: self._apply_filter(e, is_msg_name_filter=False)
        )
        self._fid_filter.grid(row=0, column=3, sticky="nsew", padx=(0, 15))

        self._button_pause = ttk.Button(frame, text="Pause", width=8, command=self._toggle_pause)
        self._button_pause.grid(row=0, column=4, padx=2)
        ttk.Button(frame, text="Delete all", width=10, command=self._delete_msgs).grid(row=0, column=5, padx=2)

        # fixed width (the widest text): the window must not grow when the counter gains a digit
        self._counter = tk.Label(frame, text="", anchor="e", width=len(f"{MAX_HISTORY} msgs"))
        self._counter.grid(row=0, column=6, sticky="e", padx=(10, 0))
        frame.columnconfigure(6, weight=1)

    # ------------------------------------------------------------------------------------------------
    # Public interface (same as the old MessageDisplayer)
    # ------------------------------------------------------------------------------------------------
    def process_data(self, msg: Message):
        """ Adds a new message (received or sent)"""
        self._register_fid(msg)
        self._history.append(msg)
        if len(self._history) > MAX_HISTORY:  # drop only the oldest message
            self._drop_oldest()
        if self._passes_filter(msg):
            self._shown.append(msg)
            self._insert_row(msg)
        self._request_refresh()

    def history(self) -> list[Message]:
        return self._history

    # ------------------------------------------------------------------------------------------------
    # History and filters
    # ------------------------------------------------------------------------------------------------
    def _load_history(self, history):
        self._history = list(history)
        for msg in self._history:
            self._register_fid(msg)
        self._rebuild_rows()

    def _drop_oldest(self):
        oldest = self._history.pop(0)
        if not self._shown or self._shown[0] is not oldest:
            return
        self._shown.pop(0)
        self._tree.delete(str(id(oldest)))
        if self._paused and self._detail_msg is oldest:  # the message being viewed was dropped: resume
            print(f"[INFO] {self._displayer_name}: paused message dropped (limit of {MAX_HISTORY} messages), "
                  f"resumed msg updating")
            self._set_paused(False)

    def _register_fid(self, msg: Message):
        """ A message from a FID that is not in the FID filter yet: the FID is added to the filter, checked,
        so its messages are shown (e.g. after "Overwrite FID", a scenario or an external Function)"""
        fid = str(msg.header.function_id)
        if fid not in self._fid_filter.options:
            self._fid_filter.add_option(fid, checked=True, sort_key=int)
            self._fid_filter_selection.append(fid)

    def _passes_filter(self, msg: Message) -> bool:
        """ True if the message matches both filters (Msg and FID)"""
        return (type(msg.bodies[0]).__name__ in self._msg_name_filter_selection
                and str(msg.header.function_id) in self._fid_filter_selection)

    def _apply_filter(self, selection: list[str], is_msg_name_filter: bool):
        attr = "_msg_name_filter_selection" if is_msg_name_filter else "_fid_filter_selection"
        setattr(self, attr, selection)
        self._rebuild_rows()

    def _rebuild_rows(self):
        """ Fills the list again with the messages that pass the filters (after loading or filtering)"""
        self._shown = [msg for msg in self._history if self._passes_filter(msg)]
        self._tree.delete(*self._tree.get_children())
        names = self._fid_names()
        for msg in self._shown:
            self._insert_row(msg, names)
        if self._paused and not any(m is self._detail_msg for m in self._shown):
            self._set_paused(False)  # the paused message is hidden now: follow the newest one
        self._refresh()

    def _delete_msgs(self):
        if not self._shown:
            print("[INFO] Nothing to delete")
            return
        to_delete = {id(m) for m in self._shown}  # by identity: one pass, no Message comparisons
        self._history = [m for m in self._history if id(m) not in to_delete]
        self._shown = []
        self._tree.delete(*self._tree.get_children())
        if self._paused:
            self._set_paused(False)
        self._refresh()
        print("[INFO] Deleted messages")

    # ------------------------------------------------------------------------------------------------
    # List
    # ------------------------------------------------------------------------------------------------
    def _insert_row(self, msg: Message, names: dict = None):
        header = msg.header
        fid = header.function_id
        names = self._fid_names() if names is None else names
        self._tree.insert("", "end", iid=str(id(msg)), values=(
            _clock(_msg_time(msg)), fid, names.get(fid, "external"),
            f"{type(msg.bodies[0]).__name__} ({extract_msg_id(header.msg_version_id)})",
            header.msg_seq_number, header.number_of_it,
        ))

    def _on_user_select(self, event=None):
        if event is not None and event.type == tk.EventType.ButtonRelease \
                and self._tree.identify_region(event.x, event.y) != "cell":
            return  # click on a heading or outside the rows
        selected = self._tree.selection()
        if not selected:
            return
        msg = next((m for m in self._shown if str(id(m)) == selected[0]), None)
        if msg is None:
            return
        if not self._paused:  # the user picked a message: stop on it
            self._set_paused(True)
        self._draw_detail(msg)

    def _select(self, msg: Message):
        if msg is None:
            self._tree.selection_set(())
        else:
            iid = str(id(msg))
            self._tree.selection_set(iid)
            self._tree.see(iid)

    # ------------------------------------------------------------------------------------------------
    # Pause and refresh
    # ------------------------------------------------------------------------------------------------
    def _toggle_pause(self):
        self._set_paused(not self._paused)
        print(f"[INFO] {self._displayer_name}: {'paused' if self._paused else 'resumed msg updating'}")

    def _set_paused(self, paused: bool):
        self._paused = paused
        if paused:
            self._button_pause.state(["pressed", "!active"])
        else:
            # hover color only if the mouse is on it (not when released automatically)
            button = self._button_pause
            pointer_over = button.winfo_containing(*button.winfo_pointerxy()) is button
            button.state(["!pressed", "active" if pointer_over else "!active"])
            self._refresh()

    def _request_refresh(self):
        if self._refresh_pending:
            return
        self._refresh_pending = True
        self.after(_REFRESH_MS, self._refresh)

    def _refresh(self):
        self._refresh_pending = False
        if not self.winfo_exists():
            return
        total = len(self._shown)
        self._counter.config(text=f"{total} msgs")
        if self._paused:
            return  # the selected message stays
        newest = self._shown[-1] if self._shown else None
        self._select(newest)
        self._draw_detail(newest)

    # ------------------------------------------------------------------------------------------------
    # Detail
    # ------------------------------------------------------------------------------------------------
    def _draw_detail(self, msg: Message):
        if msg is self._detail_msg and msg is not None:
            return  # same message: nothing to redraw
        self._detail_msg = msg
        text = self._detail
        text.config(state="normal")
        text.delete("1.0", tk.END)
        if msg is None:
            text.insert(tk.END, "No messages", "title")
        else:
            self._write_detail(msg)
        text.config(state="disabled")

    def _write_detail(self, msg: Message):
        text = self._detail
        header = msg.header
        fid = header.function_id
        name = self._fid_names().get(fid, "external")
        msg_id = extract_msg_id(header.msg_version_id)
        text.insert(tk.END, f"{type(msg.bodies[0]).__name__} ({msg_id})  ·  FID {fid} ({name})  ·  "
                            f"seq {header.msg_seq_number}\n", "title")

        text.insert(tk.END, "Header\n", "section")
        ts = header.ts_seconds + header.ts_fractional / 2 ** 32
        self._field("timestamp", _datetime(ts))
        self._field("msg id / version", f"{msg_id} / {(header.msg_version_id >> 13) & 0x3}")
        self._field("iterations", f"{header.number_of_it} x {header.single_it_len} B")

        for i, body in enumerate(msg.bodies, start=1):
            text.insert(tk.END, f"Iteration {i}\n", "section")
            for field_name, field_type in body._fields_:
                value, raw = _translate(field_name, field_type, getattr(body, field_name))
                self._field(field_name, value, raw)

    def _field(self, name: str, value, raw=None):
        text = self._detail
        text.insert(tk.END, f"    {name} = ", "name")
        text.insert(tk.END, f"{value}")
        if raw is not None:
            text.insert(tk.END, f"  ({raw})", "raw")
        text.insert(tk.END, "\n")


# ------------------------------------------------------------------------------------------------
# Values
# ------------------------------------------------------------------------------------------------
def _translate(field_name: str, field_type, value) -> tuple[str, str | None]:
    """ (value to show, raw value or None). IPs and status are shown translated, arrays shortened"""
    if hasattr(field_type, "_length_"):
        values = list(value)
        shown = ", ".join(str(v) for v in values[:8])
        return (f"[{shown}{', ...' if len(values) > 8 else ''}]", f"{len(values)} values" if len(values) > 8 else None)
    value = int(value)
    name = field_name.lower()
    if field_type is c_uint32 and (name in ("addr", "ip") or name.endswith(("_addr", "_ip"))):
        return uint32_to_ip(value), str(value)
    if name == "status" and value in _STATUS_NAMES:
        return _STATUS_NAMES[value], str(value)
    return str(value), None


def _msg_time(msg: Message) -> float:
    """ When the message was received/sent (event_time, set by the Function); if missing, its header timestamp"""
    event_time = getattr(msg, "event_time", None)
    if event_time is not None:
        return event_time
    return msg.header.ts_seconds + msg.header.ts_fractional / 2 ** 32


def _clock(t: float) -> str:
    return time.strftime("%H:%M:%S", time.localtime(t)) + f".{int((t % 1) * 1000):03d}"


def _datetime(t: float) -> str:
    return time.strftime("%Y-%m-%d ", time.localtime(t)) + _clock(t)
