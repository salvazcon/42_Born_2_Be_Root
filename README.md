# Born_2_be_root - 11/10/2022

!# Just the Born_2_be_root :)

Documentacion - https://drive.google.com/drive/folders/1W3xtPNuVMlD9KfL1pCW4qMHRBYVVNFG8?usp=share_link

"""
Scenario.py

Scenarios (drills): a template file describes a set of messages that the simulator's own Functions send,
like test_FEL_mcast_tx.py does, but built with the classes in Messages.py and played from the GUI
("Open new scenario", see ScenarioPlayer in Popup.py).

Template format: .json (or .yaml/.yml if PyYAML is installed). See scenarios/template_scenario.json.
This module has no GUI code, so it can be used and tested on its own.
"""
import json
from dataclasses import dataclass, field
from pathlib import Path

from Constants import *
from Messages import Message, MessageBody, MSG_CLS_REGISTRY, MSG_NAME_CLS_ALL_DICT, extract_msg_id, ip_to_uint32

SCENARIO_MODES = ("loop", "step", "single")
_ENTRY_KEYS = {"label", "function", "message", "group", "port", "iterations", "raw_hex", "enabled"}


class ScenarioError(Exception):
    """ The scenario file can't be read or has invalid content"""
    pass


@dataclass
class ScenarioEntry:
    """ One message of a scenario, ready to be sent by a Function"""
    label: str
    function: str
    msg_name: str
    bodies: list[MessageBody]
    group: str
    port: int


@dataclass
class Scenario:
    name: str
    description: str
    mode: str
    period_ms: int
    path: Path
    entries: list[ScenarioEntry] = field(default_factory=list)

    def functions(self) -> list[str]:
        """ Functions used by the scenario, in order of appearance"""
        return list(dict.fromkeys(e.function for e in self.entries))


def load_scenario(path, known_functions=None) -> Scenario:
    """ Reads and validates a scenario template. Raises ScenarioError listing every problem found.

    Args:
        path: scenario file (.json, .yaml or .yml)
        known_functions: names of the Functions available in the simulator (None = don't check)
    """
    path = Path(path)
    data = _read_file(path)
    if not isinstance(data, dict):
        raise ScenarioError(f"{path.name}: the file must contain an object with 'messages'")

    errors = []
    name = str(data.get("name") or path.stem)
    description = str(data.get("description", ""))

    mode = data.get("mode", "loop")
    if mode not in SCENARIO_MODES:
        errors.append(f"mode '{mode}' must be one of {', '.join(SCENARIO_MODES)}")
        mode = "loop"

    period_ms = data.get("period_ms", 50)
    if not isinstance(period_ms, int) or period_ms <= 0:
        errors.append(f"period_ms must be a positive integer (got {period_ms!r})")
        period_ms = 50

    default_port = data.get("port", MULTICAST_PORT)
    if not _valid_port(default_port):
        errors.append(f"port must be an integer between 1 and 65535 (got {default_port!r})")
        default_port = MULTICAST_PORT

    groups = data.get("groups", {})
    if not isinstance(groups, dict):
        errors.append("groups must be an object {name: multicast IP}")
        groups = {}
    for g_name, g_ip in groups.items():
        if not (isinstance(g_ip, str) and validate_ip_addr(g_ip)):
            errors.append(f"groups.{g_name}: '{g_ip}' is not a valid IP")

    raw_entries = data.get("messages")
    if not isinstance(raw_entries, list) or not raw_entries:
        errors.append("messages must be a non-empty list")
        raw_entries = []

    entries = []
    for i, raw in enumerate(raw_entries):
        if not isinstance(raw, dict):
            errors.append(f"messages[{i}]: must be an object")
            continue
        if raw.get("enabled", True) is False:
            continue
        entry_errors = []
        entry = _parse_entry(raw, groups, default_port, known_functions, entry_errors)
        label = raw.get("label") or f"{raw.get('function', '?')} {raw.get('message', '?')}"
        errors.extend(f"messages[{i}] ({label}): {e}" for e in entry_errors)
        if entry is not None:
            entries.append(entry)

    if not errors and not entries:
        errors.append("every message is disabled (enabled: false)")
    if errors:
        raise ScenarioError(f"{path.name} has {len(errors)} error(s):\n- " + "\n- ".join(errors))
    return Scenario(name=name, description=description, mode=mode, period_ms=period_ms,
                    path=path, entries=entries)


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


def _valid_port(port) -> bool:
    return isinstance(port, int) and 0 < port < 65536


def _parse_entry(raw: dict, groups: dict, default_port: int, known_functions, errors: list):
    unknown = [k for k in raw if k not in _ENTRY_KEYS and not k.startswith("_")]
    if unknown:
        errors.append(f"unknown keys {unknown} (allowed: {sorted(_ENTRY_KEYS)})")

    function = raw.get("function")
    if not isinstance(function, str) or not function:
        errors.append("'function' is required (e.g. \"CMDS\")")
    elif known_functions is not None and function not in known_functions:
        errors.append(f"function '{function}' does not exist (available: {', '.join(known_functions)})")

    has_raw, has_its = "raw_hex" in raw, "iterations" in raw
    if has_raw and has_its:
        errors.append("use either 'iterations' or 'raw_hex', not both")
        return None

    msg_name = raw.get("message")
    bodies = None
    if has_raw:
        msg_name, bodies = _bodies_from_hex(raw["raw_hex"], msg_name, errors)
    else:
        msg_cls = MSG_NAME_CLS_ALL_DICT.get(msg_name)
        if msg_cls is None:
            errors.append(f"message '{msg_name}' is not a class in Messages.py (MSG_CLS_REGISTRY)")
        else:
            bodies = _bodies_from_iterations(msg_cls, raw.get("iterations", [{}]), errors)

    group = _resolve_group(raw.get("group"), msg_name, groups, errors)
    port = raw.get("port", default_port)
    if not _valid_port(port):
        errors.append(f"port must be an integer between 1 and 65535 (got {port!r})")

    if errors or bodies is None:
        return None
    return ScenarioEntry(label=raw.get("label") or f"{function} {msg_name}", function=function,
                         msg_name=msg_name, bodies=bodies, group=group, port=port)


def _bodies_from_iterations(msg_cls, iterations, errors: list):
    if not isinstance(iterations, list) or not iterations:
        errors.append("'iterations' must be a non-empty list of {field: value}")
        return None
    if len(iterations) > msg_cls.MAX_IT:
        errors.append(f"{len(iterations)} iterations, but {msg_cls.__name__} allows {msg_cls.MAX_IT}")
        return None
    field_types = dict(msg_cls._fields_)
    bodies = []
    for n, values in enumerate(iterations, start=1):
        if not isinstance(values, dict):
            errors.append(f"iteration {n}: must be an object {{field: value}}")
            continue
        body = msg_cls()  # missing fields keep their default value (0)
        for f_name, value in values.items():
            if f_name.startswith("_"):
                continue
            if f_name not in field_types:
                errors.append(f"iteration {n}: '{f_name}' is not a field of {msg_cls.__name__} "
                              f"(fields: {', '.join(field_types)})")
                continue
            converted = _convert_value(field_types[f_name], value, f"iteration {n}: {f_name}", errors)
            if converted is not None:
                setattr(body, f_name, converted)
        bodies.append(body)
    return bodies


def _convert_value(field_type, value, where: str, errors: list):
    """ Validates a field value against its ctypes type. Strings with an IP are converted with ip_to_uint32"""
    if isinstance(value, str) and validate_ip_addr(value):
        value = ip_to_uint32(value)
    is_array = hasattr(field_type, "_length_")
    elem_type = field_type._type_ if is_array else field_type
    limits = CTYPES_LIMITS.get(elem_type)

    def in_range(v):
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
        if all(in_range(v) for v in value):
            return field_type(*value)
        return None
    return value if in_range(value) else None


def _bodies_from_hex(raw_hex, msg_name, errors: list):
    """ Decodes a complete UDP payload (header + iterations) with Messages.py. The header is discarded:
    when sent, the Function builds its own (FID, sequence number, timestamp)"""
    try:
        data = bytes.fromhex(str(raw_hex).replace(" ", "").replace("\n", ""))
    except ValueError:
        errors.append("'raw_hex' is not valid hexadecimal")
        return msg_name, None
    if len(data) < 16:
        errors.append(f"'raw_hex' has {len(data)} bytes, less than a header (16)")
        return msg_name, None
    msg_id = extract_msg_id(int.from_bytes(data[0:2], "little"))
    body_cls = MSG_CLS_REGISTRY.get(msg_id)
    if body_cls is None:
        errors.append(f"'raw_hex' has MSG_ID {msg_id}, which is not in MSG_CLS_REGISTRY")
        return msg_name, None
    if msg_name is not None and msg_name != body_cls.__name__:
        errors.append(f"'raw_hex' is a {body_cls.__name__} (MSG_ID {msg_id}), not a {msg_name}")
        return msg_name, None
    try:
        msg = Message.from_bytes(data)
    except Exception as e:
        errors.append(f"'raw_hex' could not be decoded: {e}")
        return body_cls.__name__, None
    expected = 16 + msg.header.single_it_len * msg.header.number_of_it
    if len(data) != expected:
        errors.append(f"'raw_hex' has {len(data)} bytes, but its header says {expected}")
        return body_cls.__name__, None
    return body_cls.__name__, msg.bodies


def _resolve_group(group, msg_name, groups: dict, errors: list):
    """ group can be a name from 'groups', an IP, or nothing (the class MULTICAST_ADDR is used)"""
    if group is None:
        msg_cls = MSG_NAME_CLS_ALL_DICT.get(msg_name)
        addr = getattr(msg_cls, "MULTICAST_ADDR", None) if msg_cls else None
        if msg_cls and not addr:
            errors.append(f"{msg_name} has no MULTICAST_ADDR: set 'group'")
        return addr
    if group in groups:
        return groups[group]
    if isinstance(group, str) and validate_ip_addr(group):
        return group
    errors.append(f"group '{group}' is not an IP nor a name in 'groups' ({', '.join(groups) or 'empty'})")
    return None

{
    "_help": [
        "Scenario template for the NDAS Simulator. Open it with 'Open new scenario' in the main window.",
        "Keys starting with '_' are comments and are ignored.",
        "mode: loop = whole set every period_ms | step = one message each 'Next step' (or Enter) | single = repeat the selected message every period_ms",
        "groups: multicast group of each message (from Config_FEL.json). In a message, 'group' can be a name from 'groups' or an IP; without 'group' the class MULTICAST_ADDR is used.",
        "Each message: 'function' (RWR, CMDS...) that sends it, with its own FID, and 'message' (class name in Messages.py).",
        "Values: 'iterations' = list of {field: value}, one per iteration; missing fields are 0; an IP string ('127.0.0.1') is converted to its numeric value.",
        "Or 'raw_hex' = complete UDP payload in hex (in test_FEL_mcast_tx.py: print(MSG_XXX.hex())). It is decoded with Messages.py; its header is replaced by the Function's.",
        "'enabled': false skips a message. 'label' is the text shown in the player."
    ],
    "name": "CMDS + RWR (template)",
    "description": "Equivalent to pl_set_CMDS_RWR of test_FEL_mcast_tx.py: CMDS Discovery + 3 inventories, RWR track report + Discovery.",
    "mode": "loop",
    "period_ms": 50,
    "port": 50002,
    "groups": {
        "Discovery": "224.6.104.1",
        "TrackReport": "224.6.106.1",
        "Geolocation": "224.6.106.3",
        "Fusion": "224.6.106.4",
        "Delete": "224.6.106.7",
        "MasterTrackList": "224.6.106.9",
        "DispenserStatus": "224.6.107.1",
        "InventoryStatus": "224.6.107.2",
        "NonExpandableStatus": "224.6.107.3",
        "FunctionalBIT": "224.6.108.1",
        "SystemCapabilityChange": "224.6.108.2"
    },
    "messages": [
        {
            "label": "CMDS Discovery (operational, auto)",
            "function": "CMDS",
            "message": "DiscoveryMessage",
            "group": "Discovery",
            "iterations": [
                {"validity": 1, "addr": "127.0.0.1", "data_loader": 0, "last_BIT_ts": 1, "status": 1, "mode": 1}
            ]
        },
        {
            "label": "CMDS inventory: FLARE 4x at 1.2.3",
            "enabled": false,
            "function": "CMDS",
            "message": "InventorySummaryMessage",
            "group": "InventoryStatus",
            "raw_hex": "PASTE HERE MSG_CMDS_FLARE_4x_AT_1_2_3.hex() AND SET enabled TO true"
        },
        {
            "label": "CMDS inventory: FLARE 10x at 1.3.3",
            "enabled": false,
            "function": "CMDS",
            "message": "InventorySummaryMessage",
            "group": "InventoryStatus",
            "raw_hex": "PASTE HERE MSG_CMDS_FLARE_10x_AT_1_3_3.hex() AND SET enabled TO true"
        },
        {
            "label": "CMDS inventory: CHAFF 7x at 1.6.3",
            "enabled": false,
            "function": "CMDS",
            "message": "InventorySummaryMessage",
            "group": "InventoryStatus",
            "raw_hex": "PASTE HERE MSG_CMDS_CHAFS_7x_AT_1_6_3.hex() AND SET enabled TO true"
        },
        {
            "label": "RWR track report",
            "enabled": false,
            "function": "RWR",
            "message": "TrackReportMessage",
            "group": "TrackReport",
            "raw_hex": "PASTE HERE MSG_RWR_TRACK_REPORT.hex() AND SET enabled TO true"
        },
        {
            "label": "RWR Discovery",
            "function": "RWR",
            "message": "DiscoveryMessage",
            "group": "Discovery",
            "iterations": [
                {"validity": 1, "addr": "127.0.0.1", "data_loader": 0, "last_BIT_ts": 1, "status": 1, "mode": 1}
            ]
        }
    ]
}

