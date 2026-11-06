# Born_2_be_root - 11/10/2022

!# Just the Born_2_be_root :)

Documentacion - https://drive.google.com/drive/folders/1W3xtPNuVMlD9KfL1pCW4qMHRBYVVNFG8?usp=share_link

"""
MessageDisplayer.py

The previous message viewer (one message at a time, with First/Previous/Next/Last), kept so it can be chosen
instead of the new one (MessageViewer.py) with USE_NEW_MSG_VIEWER in Constants.py.
It has the same interface as MessageViewer: MessageDisplayer(master, msgs_list, displayer_name, bd),
process_data(msg) and history().
"""
import tkinter as tk
from tkinter import ttk

from Constants import *
from Messages import *
from Widgets import ScrollableFrame, MultiSelectDropdown
from Theme import THEME


class CollapsibleText(tk.Frame):
    """Creates a tk.Label preceded by a title that, when clicked, shows/collapses said tk.Label contents

    Attributes:
        _is_open (bool): indicates whether the contents are showing
        _toggle_button (tk.Label): title that when pressed shows/collapses the contents
        _content_frame (tk.Frame): frame on which to place the contents

    """

    def __init__(self, master: tk.LabelFrame, title: str, content_text: str, bg: str, *args, **kwargs):
        super().__init__(master, background=bg, *args, **kwargs)

        base_grid = tk.Frame(self, bd=0, background=bg)
        base_grid.grid(row=0, column=0, sticky="nw")

        self._is_open: bool = False
        self._toggle_button = tk.Label(
            base_grid, text=f"> {title}", cursor="hand2",
            font="Verdana 8 bold", background=bg
        )
        self._content_frame = tk.Frame(base_grid, background=bg)

        self._toggle_button.grid(row=0, column=0, sticky="nw")
        self._toggle_button.bind("<Button-1>", lambda e: self._toggle())
        tk.Label(
            self._content_frame, text=content_text, justify="left",
            font="Verdana 8", background=bg
        ).grid(row=0, column=0, sticky="nw", padx=5)

    def _toggle(self):
        if self._is_open:
            self._content_frame.grid_forget()
            self._toggle_button.config(
                text=self._toggle_button.cget("text").replace("v", ">")
            )
        else:
            self._content_frame.grid(row=1, column=0, sticky="ew")
            self._toggle_button.config(
                text=self._toggle_button.cget("text").replace(">", "v")
            )
        self._is_open = not self._is_open

    def is_open(self) -> bool:
        return self._is_open

    def set_header(self, was_header_open: bool):
        self._is_open = not was_header_open
        self._toggle()


class RenderedMessage(tk.Frame):

    def __init__(self, master: tk.Frame, msg: Message, bg, *args, **kwargs):
        super().__init__(master, background=bg, *args, **kwargs)

        header = msg.header
        bodies = msg.bodies
        self.fid = header.function_id
        self.msg_id = extract_msg_id(header.msg_version_id)
        self.msg_name = type(bodies[0]).__name__

        fid = tk.Text(self, height=1, borderwidth=0, highlightthickness=0, bg=bg, font="Verdana 8", width=50)
        fid.tag_configure("bold", font=("Verdana", "8", "bold"))
        fid.insert(tk.END, "Function ID: ", "bold")
        fid.insert(tk.END, f"{self.fid} (Function name placeholder)")
        fid['state'] = 'disable'
        fid.grid(row=0, column=0, sticky="nw", padx=5, pady=2)

        msg_id = tk.Text(self, height=1, borderwidth=0, highlightthickness=0, bg=bg, font="Verdana 8", width=50)
        msg_id.tag_configure("bold", font=("Verdana", "8", "bold"))
        msg_id.insert(tk.END, "Msg ID: ", "bold")
        msg_id.insert(tk.END, f"{self.msg_id} ({type(bodies[0]).__name__})")
        msg_id['state'] = 'disable'
        msg_id.grid(row=1, column=0, sticky="nw", padx=5, pady=2)

        msg_seq_n = tk.Text(self, height=1, borderwidth=0, highlightthickness=0, bg=bg, font="Verdana 8", width=50)
        msg_seq_n.tag_configure("bold", font=("Verdana", "8", "bold"))
        msg_seq_n.insert(tk.END, "Msg sequence number: ", "bold")
        msg_seq_n.insert(tk.END, f"{header.msg_seq_number}")
        msg_seq_n['state'] = 'disable'
        msg_seq_n.grid(row=2, column=0, sticky="nw", padx=5, pady=2)

        header_content = self._generate_content(header)
        self._collapsible_header = CollapsibleText(self, "Header", header_content, bg=bg)
        self._collapsible_header.grid(row=3, column=0, sticky="nw", padx=5, pady=2)

        for i, body in enumerate(bodies):
            body_content = self._generate_content(body)
            CollapsibleText(self, f"Iteration {i+1}", body_content, bg=bg).grid(
                row=4 + i, column=0, sticky="nw", padx=5, pady=2
            )

    def _generate_content(self, struct) -> str:
        content = ""
        fields_len = len(struct._fields_)
        for i, (field_name, _field_type) in enumerate(struct._fields_):
            value = getattr(struct, field_name)
            if hasattr(_field_type, "_length_"):
                value = f"{value[:8]}{'...' if len(value) > 8 else ''}"
            content += f"{field_name}={value}"
            if i + 1 != fields_len:
                content += "\n"
        return content

    def is_header_open(self) -> bool:
        if self._collapsible_header:
            return self._collapsible_header.is_open()
        return False

    def set_header(self, was_header_open: bool):
        if self._collapsible_header:
            self._collapsible_header.set_header(was_header_open)


class MessageDisplayer(tk.Frame):

    def __init__(self, master: tk.LabelFrame, msgs_list: list[Message], displayer_name: str, bd: int = 2):
        super().__init__(master)
        self._master = master
        self._displayer_name = displayer_name
        self._history: list[Message] = []
        self._filtered_history: list[Message] = []
        self._msg_name_filter_selection = list(MSG_NAME_FILTER_VALUES)
        self._fid_filter_selection: list[str] = []  # filled with the FIDs of the messages (_register_fid)
        self._idx = 0
        self._stop = False
        self._stop_idx = 0
        self._empty_msg_text = "[INFO]\nNo messages"
        self._ready_to_refresh = False
        self._refresh_pending = False
        self._shown_msg: Message = None  # message currently drawn (None = "No messages")

        base_grid = tk.LabelFrame(self, bd=bd, text=displayer_name, font="Verdana 8 bold")
        base_grid.grid(row=0, column=0, sticky="nsew", padx=5, pady=5)

        self._text_grid = ScrollableFrame(base_grid, bd=2, bg=THEME.panel, height=250, width=20)
        self._text_grid.grid(row=0, column=0, columnspan=3, sticky="nsew", padx=15, pady=15)

        self._rendered_msg = tk.Label(
            self._text_grid.scrollable_content, text=self._empty_msg_text,
            font="Verdana 8 bold", width=50, height=20, background=THEME.panel, justify="left", anchor="nw"
        )
        self._rendered_msg.grid(row=0, column=0, sticky="nw", padx=5, pady=5)

        move_buttons_grid = tk.LabelFrame(base_grid, bd=0)
        move_buttons_grid.grid(row=1, column=0, sticky="e", padx=5, pady=5)

        self._button_first = ttk.Button(move_buttons_grid, text="◀◀ First", command=self._first_state)
        self._button_first.grid(row=0, column=0, sticky="e", padx=(12, 2))
        self._button_prev = ttk.Button(move_buttons_grid, text="◀ Previous", command=self._prev_state)
        self._button_prev.grid(row=0, column=1, sticky="nsew", padx=2)

        # fixed width (the widest text, "1000 / 1000"): the window must not grow when the counter gains a digit
        self._received_counter = tk.Label(move_buttons_grid, text="1 / 1", font="Verdana 8 bold",
                                          width=len(f"{MAX_HISTORY} / {MAX_HISTORY}"))
        self._received_counter.grid(row=0, column=2, columnspan=2, sticky="ns", padx=15)

        self._button_next = ttk.Button(move_buttons_grid, text="Next ▶", command=self._next_state)
        self._button_next.grid(row=0, column=4, sticky="nsew", padx=2)
        self._button_last = ttk.Button(move_buttons_grid, text="Last ▶▶", command=self._last_state)
        self._button_last.grid(row=0, column=5, sticky="w", padx=(2, 12))

        button_separator = ttk.Separator(move_buttons_grid, orient=tk.HORIZONTAL)
        button_separator.grid(row=1, column=0, sticky="ew", columnspan=8, padx=5, pady=(15, 0))

        interact_buttons_grid = tk.LabelFrame(base_grid, bd=0)
        interact_buttons_grid.grid(row=2, column=0, sticky="w", padx=5, pady=5)

        tk.Label(interact_buttons_grid, text="Filter by Msg:", justify="left", anchor="center").grid(row=0, column=0, sticky="nsew", padx=(15, 5))
        msg_type_filter = MultiSelectDropdown(
            interact_buttons_grid, MSG_NAME_FILTER_VALUES, must_have_one=True, first_must_be=False,
            show_limit=0, width=1, start_checked=True,
            on_select=lambda e: self._apply_filter(e, is_msg_name_filter=True)
        )
        msg_type_filter.grid(row=0, column=1, sticky="nsew", padx=(0, 30), pady=5)

        self._button_del = ttk.Button(interact_buttons_grid, text="Delete all", width=20, command=self._delete_msgs)
        self._button_del.grid(row=0, column=2, sticky="nsew", padx=5, pady=5)

        tk.Label(interact_buttons_grid, text="Filter by FID:", justify="left", anchor="center").grid(row=1, column=0, sticky="nsew", padx=(15, 5))
        self._fid_filter = MultiSelectDropdown(
            interact_buttons_grid, [], must_have_one=True, first_must_be=False,
            show_limit=0, width=1, start_checked=True,
            on_select=lambda e: self._apply_filter(e, is_msg_name_filter=False)
        )
        self._fid_filter.grid(row=1, column=1, sticky="nsew", padx=(0, 30), pady=5)

        self._button_stop = ttk.Button(interact_buttons_grid, text="Stop on current", width=20, command=self._stop_msgs)
        self._button_stop.grid(row=1, column=2, sticky="nsew", padx=5, pady=5)

        self._load_history(msgs_list)
        self._ready_to_refresh = True
        self._refresh_ui()

    def process_data(self, msg: Message):
        self._register_fid(msg)
        self._history.append(msg)
        if len(self._history) > MAX_HISTORY:  # drop only the oldest message
            oldest = self._history.pop(0)
            if self._filtered_history and self._filtered_history[0] is oldest:
                self._filtered_history.pop(0)
                if self._stop and self._stop_idx == 0:  # the message being viewed was dropped: resume
                    print(f"[INFO] {self._displayer_name}: stopped message dropped "
                          f"(limit of {MAX_HISTORY} messages), resumed msg updating")
                    self._stop_msgs(print_msg=False)
                    self._button_stop.state(['!active'])  # normal color, even with the mouse resting on it
                elif self._stop:
                    self._stop_idx -= 1  # "Stop on current" keeps showing the same message
        if self._passes_filter(msg):
            self._filtered_history.append(msg)
        self._idx = len(self._filtered_history) - 1
        self._request_refresh()

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

    def _request_refresh(self):
        if self._refresh_pending:
            return
        self._refresh_pending = True
        self.after(100, self._do_refresh)

    def _do_refresh(self):
        self._refresh_pending = False
        self._refresh_ui()

    def _load_history(self, history):
        self._history = list(history)
        for msg in self._history:
            self._register_fid(msg)
        self._filtered_history = [msg for msg in self._history if self._passes_filter(msg)]
        self._idx = len(self._filtered_history) - 1 if self._filtered_history else 0

    def _refresh_ui(self):
        idx = self._idx if not self._stop else self._stop_idx
        msg_to_show = self._filtered_history[idx] if self._filtered_history else None
        if msg_to_show is not self._shown_msg:  # redraw only when the message to show changes
            self._draw_msg(msg_to_show)

        self._received_counter.config(
            text=f"{idx + 1} / {len(self._filtered_history) if self._filtered_history else 1}"
        )

        state_prev_first = 'disabled' if idx == 0 else 'normal'
        state_next_last = (
            'disabled' if (not self._filtered_history or idx == len(self._filtered_history) - 1) else 'normal'
        )
        self._button_prev.config(state=state_prev_first)
        self._button_first.config(state=state_prev_first)
        self._button_next.config(state=state_next_last)
        self._button_last.config(state=state_next_last)

    def _draw_msg(self, msg: Message):
        last_msg = self._rendered_msg
        was_header_open = isinstance(last_msg, RenderedMessage) and last_msg.is_header_open()

        if msg is not None:
            self._rendered_msg = RenderedMessage(self._text_grid.scrollable_content, msg, bg=THEME.panel)
            self._rendered_msg.set_header(was_header_open=was_header_open)
        else:
            self._rendered_msg = tk.Label(
                self._text_grid.scrollable_content, text=self._empty_msg_text, font="Verdana 8 bold",
                width=50, height=20, background=THEME.panel, justify="left", anchor="nw"
            )
        self._rendered_msg.grid(row=0, column=0, sticky="nw", padx=5, pady=5)
        self._rendered_msg.update_idletasks()
        last_msg.destroy()
        self._shown_msg = msg

    def _prev_state(self):
        if self._stop and self._stop_idx > 0:
            self._stop_idx -= 1
        elif not self._stop and self._idx > 0:
            self._idx -= 1
        self._refresh_ui()

    def _next_state(self):
        filtered_history_len = len(self._filtered_history)
        if self._stop and self._stop_idx < filtered_history_len - 1:
            self._stop_idx += 1
        elif not self._stop and self._idx < filtered_history_len - 1:
            self._idx += 1
        self._refresh_ui()

    def _first_state(self):
        if self._stop:
            self._stop_idx = 0
        else:
            self._idx = 0
        self._refresh_ui()

    def _last_state(self):
        filtered_history_len = len(self._filtered_history)
        if self._stop:
            self._stop_idx = filtered_history_len - 1 if filtered_history_len else 0
        else:
            self._idx = filtered_history_len - 1 if filtered_history_len else 0
        self._refresh_ui()

    def _apply_filter(self, selection: list[str], is_msg_name_filter: bool):
        attr = "_msg_name_filter_selection" if is_msg_name_filter else "_fid_filter_selection"
        setattr(self, attr, selection)
        self._filtered_history = [msg for msg in self._history if self._passes_filter(msg)]
        if self._ready_to_refresh:
            if self._stop:
                self._stop_idx = len(self._filtered_history) - 1 if self._filtered_history else 0
            else:
                self._idx = len(self._filtered_history) - 1 if self._filtered_history else 0
            self._refresh_ui()

    def _delete_msgs(self):
        if not self._filtered_history:
            print("[INFO] Nothing to delete")
            return
        to_delete = {id(m) for m in self._filtered_history}  # by identity: one pass, no Message comparisons
        self._history = [m for m in self._history if id(m) not in to_delete]
        self._filtered_history = []
        self._idx = self._stop_idx = 0
        if self._stop:
            self._stop_msgs(print_msg=False)
        self._refresh_ui()
        print("[INFO] Deleted messages")

    def _stop_msgs(self, print_msg=True):
        self._stop = not self._stop
        if not self._stop:
            # hover color only if the mouse is on it (not when released automatically)
            pointer_over = self._button_stop.winfo_containing(*self._button_stop.winfo_pointerxy()) is self._button_stop
            self._button_stop.state(['!pressed', 'active' if pointer_over else '!active'])
        else:
            self._button_stop.state(['pressed', '!active'])
        if self._stop:
            self._stop_idx = len(self._filtered_history) - 1 if self._filtered_history else 0
            if self._stop_idx and print_msg:
                print(f"[INFO] Stopped at msg {self._stop_idx+1}")
        else:
            self._idx = len(self._filtered_history) - 1 if self._filtered_history else 0
            if self._idx and print_msg:
                print("[INFO] Resumed msg updating")
        self._refresh_ui()

    def history(self):
        return self._history
