# Born_2_be_root - 11/10/2022

!# Just the Born_2_be_root :)

Documentacion - https://drive.google.com/drive/folders/1W3xtPNuVMlD9KfL1pCW4qMHRBYVVNFG8?usp=share_link


"""
Scenario.py

Scenarios: a template file (.json, or .yaml/.yml if PyYAML is installed) describes how the simulator must be set
up, and apply_scenario() does it through the same paths the GUI buttons use, as if the user clicked them:
open each Function, set its FID, status and tx/rx blocks, select its multicast messages and fill its
"Open msg config" values. Only the fields that differ from the defaults in Messages.py need to be written.

Message values can be given as:
    iterations:      list of {field: value}, one per iteration (missing fields keep their default)
    from_reference:  name(s) of MSG_* payloads of a reference script (e.g. test_FEL_mcast_tx.py), one per iteration
    raw_hex:         complete UDP payload(s) in hex, one per iteration

See scenarios/template_scenario.json. This module has no GUI code.
"""
import ast
import json
from dataclasses import dataclass, field
from pathlib import Path

from Constants import *
from Messages import (
    Message, MessageBody, MSG_CLS_REGISTRY, MSG_NAME_CLS_ALL_DICT, MSG_NAME_CLS_MCAST_DICT,
    extract_msg_id, ip_to_uint32,
)

_FUNCTION_KEYS = {"fid", "status", "block_tx", "block_rx", "mcast_messages", "messages", "start"}
_MESSAGE_KEYS = {"iterations", "from_reference", "raw_hex"}


class ScenarioError(Exception):
    """ The scenario file can't be read or has invalid content"""
    pass


@dataclass
class MessageConfig:
    """ Values of one message, as they would be written in its "Open msg config" window"""
    msg_name: str
    iterations: list[dict] = None          # partial values, applied over the defaults
    bodies: list[MessageBody] = None       # complete iterations, decoded from bytes

    @property
    def is_mcast(self) -> bool:
        return MSG_NAME_CLS_ALL_DICT[self.msg_name].RATE_HZ is not None

    def build(self, current: list[MessageBody] = None) -> list[MessageBody]:
        """ Returns the iterations to give to the Function. Each iteration starts from the Function's current
        one (or a new default one) and only the fields written in the template are changed"""
        if self.bodies is not None:
            return [b.clone() for b in self.bodies]
        msg_cls = MSG_NAME_CLS_ALL_DICT[self.msg_name]
        current = current or []
        result = []
        for i, values in enumerate(self.iterations):
            body = current[i].clone() if i < len(current) else msg_cls()
            for name, value in values.items():
                setattr(body, name, value)
            result.append(body)
        return result


@dataclass
class FunctionConfig:
    """ Everything that would be done by hand in the window of one Function. None = leave as it is"""
    name: str
    fid: int = None
    status: str = None
    block_tx: bool = None
    block_rx: bool = None
    mcast_messages: list[str] = None       # None = keep the Function's starting messages
    messages: list[MessageConfig] = field(default_factory=list)
    start: bool = False


@dataclass
class Scenario:
    name: str
    description: str
    path: Path
    functions: list[FunctionConfig] = field(default_factory=list)


# ------------------------------------------------------------------------------------------------
# Loading and validation
# ------------------------------------------------------------------------------------------------
def load_scenario(path, known_functions=None) -> Scenario:
    """ Reads and validates a scenario template. Raises ScenarioError listing every problem found.

    Args:
        path: scenario file (.json, .yaml or .yml)
        known_functions: names of the Functions available in the simulator (None = don't check)
    """
    path = Path(path)
    data = _read_file(path)
    if not isinstance(data, dict):
        raise ScenarioError(f"{path.name}: the file must contain an object with 'functions'")

    errors = []
    references = {}
    if "reference_file" in data:
        ref_path = Path(data["reference_file"])
        if not ref_path.is_absolute():
            ref_path = path.parent / ref_path
        try:
            references = load_reference_payloads(ref_path)
        except (OSError, SyntaxError) as e:
            errors.append(f"reference_file: could not read {ref_path}: {e}")

    functions = data.get("functions")
    if not isinstance(functions, dict) or not functions:
        errors.append("'functions' must be a non-empty object {function name: configuration}")
        functions = {}

    configs = []
    for f_name, raw in functions.items():
        where = f"functions.{f_name}"
        if known_functions is not None and f_name not in known_functions:
            errors.append(f"{where}: function does not exist (available: {', '.join(known_functions)})")
            continue
        if not isinstance(raw, dict):
            errors.append(f"{where}: must be an object")
            continue
        configs.append(_parse_function(f_name, raw, references, where, errors))

    if errors:
        raise ScenarioError(f"{path.name} has {len(errors)} error(s):\n- " + "\n- ".join(errors))
    return Scenario(name=str(data.get("name") or path.stem), description=str(data.get("description", "")),
                    path=path, functions=configs)


def _read_file(path: Path):
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as e:
        raise ScenarioError(f"could not open {path}: {e}")
    if path.suffix.lower() in (".yaml", ".yml"):
        try:
            import yaml
        except ImportError:
            raise ScenarioError("PyYAML is not installed: use a .json scenario or run 'pip install pyyaml'")
        try:
            return yaml.safe_load(text)
        except yaml.YAMLError as e:
            raise ScenarioError(f"{path.name}: invalid YAML: {e}")
    try:
        return json.loads(text)
    except json.JSONDecodeError as e:
        raise ScenarioError(f"{path.name}: invalid JSON at line {e.lineno}, column {e.colno}: {e.msg}")


def _unknown_keys(raw: dict, allowed: set, where: str, errors: list):
    unknown = [k for k in raw if k not in allowed and not str(k).startswith("_")]
    if unknown:
        errors.append(f"{where}: unknown keys {unknown} (allowed: {sorted(allowed)})")


def _parse_function(name: str, raw: dict, references: dict, where: str, errors: list) -> FunctionConfig:
    _unknown_keys(raw, _FUNCTION_KEYS, where, errors)
    cfg = FunctionConfig(name=name, start=bool(raw.get("start", False)))

    if "fid" in raw:
        if isinstance(raw["fid"], int) and 0 <= raw["fid"] <= 255:
            cfg.fid = raw["fid"]
        else:
            errors.append(f"{where}.fid: must be an integer between 0 and 255")
    if "status" in raw:
        if raw["status"] in STATUS_MAP:
            cfg.status = raw["status"]
        else:
            errors.append(f"{where}.status: '{raw['status']}' must be one of {list(STATUS_MAP)}")
    for key in ("block_tx", "block_rx"):
        if key in raw:
            if isinstance(raw[key], bool):
                setattr(cfg, key, raw[key])
            else:
                errors.append(f"{where}.{key}: must be true or false")

    if "mcast_messages" in raw:
        selection = raw["mcast_messages"]
        if not isinstance(selection, list):
            errors.append(f"{where}.mcast_messages: must be a list of message names")
        else:
            bad = [m for m in selection if m not in MSG_NAME_CLS_MCAST_DICT]
            if bad:
                errors.append(f"{where}.mcast_messages: {bad} are not multicast messages "
                              f"(available: {', '.join(sorted(MSG_NAME_CLS_MCAST_DICT))})")
            cfg.mcast_messages = [m for m in selection if m in MSG_NAME_CLS_MCAST_DICT]

    messages = raw.get("messages", {})
    if not isinstance(messages, dict):
        errors.append(f"{where}.messages: must be an object {{message name: values}}")
        messages = {}
    for msg_name, msg_raw in messages.items():
        msg_cfg = _parse_message(msg_name, msg_raw, references, f"{where}.messages.{msg_name}", errors)
        if msg_cfg is not None:
            cfg.messages.append(msg_cfg)
    return cfg


def _parse_message(msg_name: str, raw, references: dict, where: str, errors: list):
    msg_cls = MSG_NAME_CLS_ALL_DICT.get(msg_name)
    if msg_cls is None:
        errors.append(f"{where}: '{msg_name}' is not a class in Messages.py (MSG_CLS_REGISTRY)")
        return None
    if isinstance(raw, list):  # shortcut: the list of iterations directly
        raw = {"iterations": raw}
    if not isinstance(raw, dict):
        errors.append(f"{where}: must be an object or a list of iterations")
        return None
    _unknown_keys(raw, _MESSAGE_KEYS, where, errors)
    sources = [k for k in _MESSAGE_KEYS if k in raw]
    if len(sources) != 1:
        errors.append(f"{where}: use exactly one of {sorted(_MESSAGE_KEYS)}")
        return None

    n_errors = len(errors)
    if "iterations" in raw:
        iterations = _parse_iterations(msg_cls, raw["iterations"], where, errors)
        n_its = len(iterations or [])
        cfg = MessageConfig(msg_name, iterations=iterations)
    else:
        if "from_reference" in raw:
            names = raw["from_reference"] if isinstance(raw["from_reference"], list) else [raw["from_reference"]]
            payloads = []
            for ref in names:
                if ref not in references:
                    errors.append(f"{where}: '{ref}' not found in reference_file "
                                  f"(available: {', '.join(references) or 'none, is reference_file set?'})")
                else:
                    payloads.append((ref, references[ref]))
        else:
            hex_list = raw["raw_hex"] if isinstance(raw["raw_hex"], list) else [raw["raw_hex"]]
            payloads = []
            for i, hex_text in enumerate(hex_list):
                try:
                    payloads.append((f"raw_hex[{i}]", bytes.fromhex(str(hex_text).replace(" ", ""))))
                except ValueError:
                    errors.append(f"{where}: raw_hex[{i}] is not valid hexadecimal")
        bodies = []
        for label, data in payloads:
            bodies.extend(_decode_payload(msg_cls, data, f"{where}: {label}", errors))
        n_its = len(bodies)
        cfg = MessageConfig(msg_name, bodies=bodies)

    if len(errors) == n_errors and n_its > msg_cls.MAX_IT:
        errors.append(f"{where}: {n_its} iterations, but {msg_name} allows {msg_cls.MAX_IT}")
    return cfg if len(errors) == n_errors else None


def _parse_iterations(msg_cls, iterations, where: str, errors: list):
    if not isinstance(iterations, list) or not iterations:
        errors.append(f"{where}.iterations: must be a non-empty list of {{field: value}}")
        return None
    field_types = dict(msg_cls._fields_)
    parsed = []
    for n, values in enumerate(iterations, start=1):
        if not isinstance(values, dict):
            errors.append(f"{where}.iterations[{n}]: must be an object {{field: value}}")
            continue
        clean = {}
        for f_name, value in values.items():
            if str(f_name).startswith("_"):
                continue
            if f_name not in field_types:
                errors.append(f"{where}.iterations[{n}]: '{f_name}' is not a field of {msg_cls.__name__} "
                              f"(fields: {', '.join(field_types)})")
                continue
            converted = _convert_value(field_types[f_name], value, f"{where}.iterations[{n}].{f_name}", errors)
            if converted is not None:
                clean[f_name] = converted
        parsed.append(clean)
    return parsed


def _convert_value(field_type, value, where: str, errors: list):
    """ Validates a value against its ctypes type (CTYPES_LIMITS). A string with an IP is converted with
    ip_to_uint32, a list fills an array field from its first position"""
    if isinstance(value, str) and validate_ip_addr(value):
        value = ip_to_uint32(value)
    is_array = hasattr(field_type, "_length_")
    limits = CTYPES_LIMITS.get(field_type._type_ if is_array else field_type)

    def check(v) -> bool:
        if isinstance(v, bool) or not isinstance(v, int):
            errors.append(f"{where}: {v!r} is not an integer")
            return False
        if limits and not limits["min"] <= v <= limits["max"]:
            errors.append(f"{where}: {v} out of range [{limits['min']}, {limits['max']}]")
            return False
        return True

    if is_array and isinstance(value, list):
        if len(value) > field_type._length_:
            errors.append(f"{where}: {len(value)} values, but the field holds {field_type._length_}")
            return None
        return field_type(*value) if all(check(v) for v in value) else None
    return value if check(value) else None


def _decode_payload(msg_cls, data: bytes, where: str, errors: list) -> list:
    """ Decodes a complete UDP payload with Messages.py and returns its iterations (the header is discarded:
    the Function builds its own FID, sequence number and timestamp when sending)"""
    if len(data) < 16:
        errors.append(f"{where}: {len(data)} bytes, less than a header (16)")
        return []
    msg_id = extract_msg_id(int.from_bytes(data[0:2], "little"))
    payload_cls = MSG_CLS_REGISTRY.get(msg_id)
    if payload_cls is not msg_cls:
        found = payload_cls.__name__ if payload_cls else "not in MSG_CLS_REGISTRY"
        errors.append(f"{where}: is MSG_ID {msg_id} ({found}), not a {msg_cls.__name__}")
        return []
    try:
        msg = Message.from_bytes(data)
    except Exception as e:
        errors.append(f"{where}: could not be decoded: {e}")
        return []
    expected = 16 + msg.header.single_it_len * msg.header.number_of_it
    if len(data) != expected:
        errors.append(f"{where}: {len(data)} bytes, but its header says {expected}")
        return []
    return msg.bodies


def _eval_bytes(node: ast.AST) -> bytes:
    """ Evaluates a bytes expression without running the file: literals, "+", bytes.fromhex("...")"""
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return _eval_bytes(node.left) + _eval_bytes(node.right)
    if isinstance(node, ast.Call) and ast.unparse(node.func) in ("bytes.fromhex", "bytearray.fromhex"):
        return bytes.fromhex(ast.literal_eval(node.args[0]))
    value = ast.literal_eval(node)
    if not isinstance(value, (bytes, bytearray)):
        raise ValueError("not a bytes value")
    return bytes(value)


def load_reference_payloads(path) -> dict[str, bytes]:
    """ Reads the module-level MSG_* bytes constants of a script WITHOUT executing it"""
    tree = ast.parse(Path(path).read_text(encoding="utf-8"), filename=str(path))
    payloads = {}
    for node in tree.body:
        if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name) \
                and node.targets[0].id.startswith("MSG_"):
            try:
                payloads[node.targets[0].id] = _eval_bytes(node.value)
            except Exception:
                pass
    return payloads


# ------------------------------------------------------------------------------------------------
# Applying a scenario to the simulator
# ------------------------------------------------------------------------------------------------
def apply_scenario(app, scenario: Scenario):
    """ Sets up the simulator as described by the scenario, through the same paths as the GUI buttons.
    A Function whose window is open is closed first (as clicking its X: it is stopped and reset)"""
    for cfg in scenario.functions:
        name = cfg.name
        if app._function_widgets[name]["popup_open"]:
            app._function_popup[name]._on_close()
        function = app._functions[name]  # fresh Function after the reset

        if cfg.fid is not None:
            app._change_fid(function, cfg.fid)                                    # "Overwrite FID"
        status = cfg.status or {v: k for k, v in STATUS_MAP.items()}[function.status]
        app._change_status(function, status)                                      # "Change Status"
        for direction in ("tx", "rx"):                                            # "Block tx" / "Block rx"
            block = getattr(cfg, f"block_{direction}")
            if block is not None:
                app._send_command(name, "set_block", {"block": block, "direction": direction})

        # "Select mcast messages": the selection plus every multicast message configured in the template
        current = list(function._function_msgs_mcast)
        wanted = list(cfg.mcast_messages) if cfg.mcast_messages is not None else list(current)
        wanted += [m.msg_name for m in cfg.messages if m.is_mcast and m.msg_name not in wanted]
        for msg_name in current:
            if msg_name not in wanted:
                app._send_command(name, "remove_msg", {"msg_name": msg_name, "is_tcp": False})
        for msg_name in wanted:
            if msg_name not in function._function_msgs_mcast:
                app._send_command(name, "add_msg", {"msg_body": MSG_NAME_CLS_MCAST_DICT[msg_name]()})

        # "Open msg config" + "Update values"
        for msg_cfg in cfg.messages:
            store = function._function_msgs_mcast if msg_cfg.is_mcast else function._function_msgs_tcp
            bodies = msg_cfg.build(store.get(msg_cfg.msg_name))
            app._send_command(name, "update_msg", {"msg_body_its": bodies})

        app._create_function_popup(function)
        if cfg.start:
            app._start_function(function=function)                               # "Start"
        print(f"[INFO] Scenario '{scenario.name}': {name} configured"
              f"{' and started' if cfg.start else ''}")


{
    "_help": [
        "Scenario template for the NDAS Simulator: 'Open new scenario' in the main window applies it as if the buttons were clicked.",
        "Keys starting with '_' are comments and are ignored. Anything not written keeps its current/default value.",
        "functions: one entry per Function (RWR, CMDS...). Its window is closed (stopped and reset) and reopened with this setup.",
        "  fid, status ('Fully Op.', 'Fully Op. (Mnt)', 'Degraded Fault', 'Degraded Op. Mode', 'Non Op. Mode', 'Fail'), block_tx, block_rx, start (true = press Start).",
        "  mcast_messages: selection of 'Select mcast messages'. Without it, the starting messages are kept. Configured multicast messages are always added.",
        "  messages: values of 'Open msg config', by class name (Messages.py). Three ways:",
        "    list of iterations [{field: value}, ...]: only the fields that change; the rest keep the defaults of Messages.py. IP strings ('127.0.0.1') are converted.",
        "    {\"from_reference\": \"MSG_X\"} or [\"MSG_A\", \"MSG_B\"]: payloads of reference_file (read, never executed), one per iteration.",
        "    {\"raw_hex\": \"...\"} or a list: complete UDP payloads in hex (print(payload.hex())), one per iteration.",
        "  When a message comes from bytes, its header is discarded: the Function sends it with its own FID, sequence number and timestamp."
    ],
    "name": "CMDS + RWR (FEL)",
    "description": "pl_set_CMDS_RWR of test_FEL_mcast_tx.py: CMDS Discovery + 3 inventories, RWR track report + Discovery.",
    "reference_file": "S:/test_FEL_mcast_tx.py",
    "functions": {
        "CMDS": {
            "fid": 8,
            "status": "Fully Op.",
            "start": false,
            "messages": {
                "DiscoveryMessage": {"from_reference": "MSG_CMDS_DISCOVERY_OPER_AUTO"},
                "InventorySummaryMessage": {"from_reference": [
                    "MSG_CMDS_FLARE_4x_AT_1_2_3",
                    "MSG_CMDS_FLARE_10x_AT_1_3_3",
                    "MSG_CMDS_CHAFS_7x_AT_1_6_3"
                ]}
            }
        },
        "RWR": {
            "fid": 199,
            "status": "Fully Op.",
            "start": false,
            "messages": {
                "TrackReportMessage": {"from_reference": "MSG_RWR_TRACK_REPORT"},
                "DiscoveryMessage": [
                    {"validity": 1, "addr": "127.0.0.1", "last_BIT_ts": 1, "mode": 1}
                ]
            }
        }
    }
}

