# Born_2_be_root - 11/10/2022

!# Just the Born_2_be_root :)

Documentacion - https://drive.google.com/drive/folders/1W3xtPNuVMlD9KfL1pCW4qMHRBYVVNFG8?usp=share_link

    _FLASH_MS = 150  # how long a button looks pressed when a sequence presses it

    def __init__(self, master: tk.Misc):
        super().__init__(master)
        self.title("3ATI Display Buttons")
        self.iconbitmap(PATH_TO_ICON)
        self.resizable(False, False)
        self.protocol("WM_DELETE_WINDOW", self._on_close)
        self._buttons: dict[int, ttk.Button] = {}
        self._sequence = None
        self._player: SequencePlayer = None

        frame = tk.LabelFrame(self, text="Display Buttons", font="Verdana 8 bold", bd=2)
        frame.grid(row=0, column=0, padx=10, pady=10)

        for button, (row, column) in self._LAYOUT.items():
            btn = ttk.Button(frame, text="-", width=4, command=lambda b=button: self._press(b))
            btn.grid(row=row, column=column, padx=10, pady=10)
            self._buttons[button] = btn



            row=1, column=1, rowspan=2, columnspan=5)

        self._build_sequence_controls()
        place_window(self, *ATI_WINDOW_POS)

    def _build_sequence_controls(self):
        frame = tk.LabelFrame(self, text="Sequence", font="Verdana 8 bold", bd=2)
        frame.grid(row=1, column=0, sticky="ew", padx=10, pady=(0, 10))
        frame.columnconfigure(1, weight=1)

        ttk.Button(frame, text="Load sequence", width=15, command=self._load_sequence).grid(
            row=0, column=0, padx=5, pady=5)
        self._seq_name = tk.Label(frame, text="No sequence loaded", anchor="w")
        self._seq_name.grid(row=0, column=1, sticky="ew", padx=5)
        self._run_button = ttk.Button(frame, text="Run", width=10, command=self._toggle_sequence, state="disabled")
        self._run_button.grid(row=1, column=0, padx=5, pady=5)
        self._seq_progress = tk.Label(frame, text="", anchor="w", fg=COLOR_GRAY)
        self._seq_progress.grid(row=1, column=1, sticky="ew", padx=5)

    def _press(self, button: int, flash: bool = False):
        if flash:  # pressed by a sequence: show which one
            btn = self._buttons[button]
            btn.state(["pressed"])
            self.after(self._FLASH_MS, lambda: btn.winfo_exists() and btn.state(["!pressed"]))
        try:
            datagram = send_display_button(button)
            print(f"[INFO] 3ATI: display button {button} pressed ({datagram.hex(' ')})")
        except OSError as e:
            print(f"[ERROR] 3ATI: could not send display button {button}: {e}")

    # --- Sequences ---
    def _load_sequence(self):
        if self._player and self._player.running:
            self._player.stop()
        path = filedialog.askopenfilename(
            parent=self, title="Load 3ATI sequence", initialdir=SCENARIOS_DIR,
            filetypes=[("3ATI sequence", "*.json *.yaml *.yml"), ("All files", "*.*")],
        )
        if not path:
            return
        try:
            self._sequence = load_sequence(path)
        except SequenceError as e:
            print(f"[ERROR] 3ATI sequence: {e}")
            messagebox.showerror("3ATI sequence error", str(e), parent=self)
            return
        seq = self._sequence
        self._player = SequencePlayer(self, seq, press=lambda b: self._press(b, flash=True),
                                      on_step=self._on_sequence_step, on_finish=self._on_sequence_finish)
        self._seq_name.config(text=seq.name)
        self._seq_progress.config(text=f"{seq.presses} presses, {seq.duration_ms / 1000:.1f} s")
        self._run_button.config(text="Run", state="normal")
        print(f"[INFO] 3ATI sequence '{seq.name}' loaded: {seq.presses} presses, {seq.duration_ms / 1000:.1f} s")

    def _toggle_sequence(self):
        if self._player.running:
            self._player.stop()
        else:
            self._run_button.config(text="Stop")
            print(f"[INFO] 3ATI sequence '{self._sequence.name}' started")
            self._player.start()

    def _on_sequence_step(self, index: int, total: int, step):
        action = f"button {step.button}" if step.button is not None else "pause"
        self._seq_progress.config(text=f"Step {index}/{total}: {action}")

    def _on_sequence_finish(self, completed: bool):
        if not self.winfo_exists():
            return
        self._run_button.config(text="Run")
        self._seq_progress.config(text="Finished" if completed else "Stopped")
        print(f"[INFO] 3ATI sequence '{self._sequence.name}' {'finished' if completed else 'stopped'}")

    def _on_close(self):
        if self._player and self._player.running:
            self._player.stop()
        self._destroy_and_clear() if False else self.destroy()



"""
ATISequence.py

3ATI sequences: a template file (.json, or .yaml/.yml if PyYAML is installed) lists presses of the 3ATI display
buttons and the time to wait between one press and the next. load_sequence() reads and validates it and
SequencePlayer presses the buttons one after another without blocking the GUI (it uses Tk's after()).

See scenarios/template_ati_sequence.json. This module has no widgets (the controls are in Popup.DisplayButtonsPopup).
"""
import time
from dataclasses import dataclass, field
from pathlib import Path

from Constants import *
from Scenario import ScenarioError, _read_file

_SEQUENCE_KEYS = {"name", "description", "default_delay_ms", "repeat", "steps"}
_STEP_KEYS = {"button", "delay_ms", "times", "wait_ms"}
DEFAULT_DELAY_MS = 1000


class SequenceError(Exception):
    """ The sequence file can't be read or has invalid content"""
    pass


@dataclass
class Step:
    """ One press of a display button (button=None: only a pause) and the time to wait before the next step"""
    button: int | None
    delay_ms: int


@dataclass
class Sequence:
    name: str
    description: str
    path: Path
    steps: list[Step] = field(default_factory=list)  # already expanded: "times" and "repeat" applied

    @property
    def presses(self) -> int:
        return sum(1 for s in self.steps if s.button is not None)

    @property
    def duration_ms(self) -> int:
        """ From the first press to the last one (the delay after the last step is not waited)"""
        return sum(s.delay_ms for s in self.steps[:-1])


# ------------------------------------------------------------------------------------------------
# Loading and validation
# ------------------------------------------------------------------------------------------------
def load_sequence(path) -> Sequence:
    """ Reads and validates a 3ATI sequence template. Raises SequenceError listing every problem found"""
    path = Path(path)
    try:
        data = _read_file(path)
    except ScenarioError as e:
        raise SequenceError(str(e))
    if not isinstance(data, dict):
        raise SequenceError(f"{path.name}: the file must contain an object with 'steps'")

    errors = [f"unknown key '{k}' (valid: {', '.join(sorted(_SEQUENCE_KEYS))})"
              for k in data if not k.startswith("_") and k not in _SEQUENCE_KEYS]
    default_delay = _int(data, "default_delay_ms", DEFAULT_DELAY_MS, 0, errors, "default_delay_ms")
    repeat = _int(data, "repeat", 1, 1, errors, "repeat")

    raw_steps = data.get("steps")
    if not isinstance(raw_steps, list) or not raw_steps:
        errors.append("'steps' must be a non-empty list")
        raw_steps = []

    steps = []
    for i, raw in enumerate(raw_steps, start=1):
        steps += _parse_step(raw, f"steps[{i}]", default_delay, errors)

    if errors:
        raise SequenceError(f"{path.name} has {len(errors)} error(s):\n- " + "\n- ".join(errors))
    return Sequence(name=str(data.get("name") or path.stem), description=str(data.get("description", "")),
                    path=path, steps=steps * repeat)


def _parse_step(raw, where: str, default_delay: int, errors: list[str]) -> list[Step]:
    if not isinstance(raw, dict):
        errors.append(f"{where}: must be an object, e.g. {{\"button\": 3, \"delay_ms\": 500}}")
        return []
    unknown = [k for k in raw if not k.startswith("_") and k not in _STEP_KEYS]
    if unknown:
        errors.append(f"{where}: unknown key(s) {', '.join(unknown)} (valid: {', '.join(sorted(_STEP_KEYS))})")

    if "wait_ms" in raw:  # pause only
        if "button" in raw:
            errors.append(f"{where}: use 'button' (+ 'delay_ms') or 'wait_ms', not both")
            return []
        wait = _int(raw, "wait_ms", 0, 0, errors, f"{where}.wait_ms")
        return [Step(button=None, delay_ms=wait)]

    if "button" not in raw:
        errors.append(f"{where}: missing 'button' (0-{ATI_N_BUTTONS - 1}) or 'wait_ms'")
        return []
    button = _int(raw, "button", 0, 0, errors, f"{where}.button")
    if button >= ATI_N_BUTTONS:
        errors.append(f"{where}.button: must be between 0 and {ATI_N_BUTTONS - 1} (got {button})")
    delay = _int(raw, "delay_ms", default_delay, 0, errors, f"{where}.delay_ms")
    times = _int(raw, "times", 1, 1, errors, f"{where}.times")
    return [Step(button=button, delay_ms=delay) for _ in range(times)]


def _int(data: dict, key: str, default: int, minimum: int, errors: list[str], where: str) -> int:
    """ Integer value of data[key] (default if missing). Adds an error and returns the default if it is not valid"""
    value = data.get(key, default)
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        errors.append(f"{where}: must be an integer >= {minimum} (got {value!r})")
        return default
    return value


# ------------------------------------------------------------------------------------------------
# Playing a sequence
# ------------------------------------------------------------------------------------------------
class SequencePlayer:
    """ Presses the buttons of a Sequence one after another without blocking the GUI.

    Each step is scheduled from the start time of the sequence (not from the end of the previous step),
    so the small delays of every press do not add up along the sequence.

    Args:
        widget: any Tk widget, used for after()
        sequence: the Sequence to play
        press: callable(button) that presses one display button
        on_step: callable(index, total, step) called after each step (index starts at 1)
        on_finish: callable(completed) called at the end; completed is False if it was stopped
    """

    def __init__(self, widget, sequence: Sequence, press: callable, on_step: callable = None,
                 on_finish: callable = None):
        self._widget = widget
        self._sequence = sequence
        self._press = press
        self._on_step = on_step
        self._on_finish = on_finish
        self._index = 0
        self._next_time = 0.0
        self._after_id = None

    @property
    def running(self) -> bool:
        return self._after_id is not None

    def start(self):
        if self.running:
            return
        self._index = 0
        self._next_time = time.perf_counter()
        self._after_id = self._widget.after(0, self._run_step)

    def stop(self):
        if not self.running:
            return
        self._widget.after_cancel(self._after_id)
        self._after_id = None
        if self._on_finish:
            self._on_finish(False)

    def _run_step(self):
        steps = self._sequence.steps
        step = steps[self._index]
        if step.button is not None:
            self._press(step.button)
        self._index += 1
        if self._on_step:
            self._on_step(self._index, len(steps), step)
        if self._index >= len(steps):  # last step: its delay is not waited
            self._after_id = None
            if self._on_finish:
                self._on_finish(True)
            return
        self._next_time += step.delay_ms / 1000
        wait_ms = max(0, round((self._next_time - time.perf_counter()) * 1000))
        self._after_id = self._widget.after(wait_ms, self._run_step)




{
    "_help": [
        "3ATI sequence template for the NDAS Simulator: 'Load sequence' in the 3ATI Display Buttons window loads it and 'Run' plays it.",
        "Keys starting with '_' are comments and are ignored.",
        "Buttons (0-9) as placed around the display: 0-3 right side (top to bottom), 4 and 5 bottom (right to left), 6-9 left side (bottom to top).",
        "default_delay_ms: time between one press and the next when a step has no delay_ms (default 1000).",
        "repeat: how many times the whole list of steps is played (default 1).",
        "steps, in order:",
        "  {\"button\": n}: press button n, then wait default_delay_ms.",
        "  {\"button\": n, \"delay_ms\": t}: press button n, then wait t milliseconds before the next step.",
        "  {\"button\": n, \"times\": k}: press button n k times in a row, waiting delay_ms between presses.",
        "  {\"wait_ms\": t}: extra pause of t milliseconds, without pressing anything.",
        "The delay after the very last step is not waited: the sequence ends with its last press."
    ],
    "name": "Example 3ATI sequence",
    "description": "Goes through some display pages and comes back",
    "default_delay_ms": 1000,
    "repeat": 1,
    "steps": [
        {"button": 9},
        {"button": 0, "delay_ms": 500},
        {"button": 3, "times": 3, "delay_ms": 300},
        {"wait_ms": 2000},
        {"button": 6, "_note": "back to the first page"}
    ]
}
