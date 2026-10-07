# Born_2_be_root - 11/10/2022

!# Just the Born_2_be_root :)

Documentacion - https://drive.google.com/drive/folders/1W3xtPNuVMlD9KfL1pCW4qMHRBYVVNFG8?usp=share_link

"""
FelTest.py

Command line test bench against NDAS_FEL, equivalent to test_FEL_mcast_tx.py ("pocket simulator"),
but building every message with the simulator's own classes (Messages.py) instead of hand-written bytes.

Usage (from the src folder):
    python FelTest.py list                                   # scenarios and reference payloads
    python FelTest.py roundtrip [--emit]                     # decode/encode check, no network
    python FelTest.py send CMDS_RWR                          # whole scenario every 50 ms (loop)
    python FelTest.py send CMDS_RWR --mode step              # one message each Enter
    python FelTest.py send CMDS_RWR --mode single --index 2  # repeat one message of the scenario
    python FelTest.py send CMDS_RWR --dry-run                # build and print, don't send
Ctrl+C stops any sending mode.
"""
import argparse
import ast
import ctypes
import json
import os
import re
import socket
import time
from dataclasses import dataclass, field

from Constants import MULTICAST_PORT
from Messages import (
    Message, DFCIWrapperMessage, MSG_CLS_REGISTRY, MSG_NAME_CLS_ALL_DICT,
    build_message, extract_msg_id, ip_to_uint32,
)

# ------------------------------------------------------------------------------------------------
# Configuration (all of it can be overridden from the command line)
# ------------------------------------------------------------------------------------------------
LOOPBACK_IP = "127.0.0.69"                     # own source IP, different from every other node
FEL_CONFIG_PATH = r"S:\Config_FEL.json"        # multicast group of each message
REFERENCE_PATH = r"S:\test_FEL_mcast_tx.py"   # reference payloads (MSG_* constants)
TX_PERIOD = 0.05                               # seconds between sends in loop modes
SOCKET_TIMEOUT = 2.2

# Name used in Config_FEL.json for each Message class, when it differs from the class name
# without the "Message" suffix (e.g. "InventorySummaryMessage": "InventoryStatus").
# Names known from Config_FEL.json: Discovery, TrackReport, Geolocation, Fusion, Delete,
# MasterTrackList, DispenserStatus, InventoryStatus, NonExpandableStatus, FunctionalBIT,
# SystemCapabilityChange
CONFIG_NAME_ALIASES: dict[str, str] = {
    "DiscoveryMessage": "Discovery",
}


# ------------------------------------------------------------------------------------------------
# Reference payloads
# ------------------------------------------------------------------------------------------------
def _eval_bytes(node: ast.AST) -> bytes:
    """ Evaluates a bytes expression without running the file: literals, "+",
    bytes.fromhex("..."), bytes([...]) and bytearray(...)"""
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return _eval_bytes(node.left) + _eval_bytes(node.right)
    if isinstance(node, ast.Call):
        func = ast.unparse(node.func)
        args = [ast.literal_eval(a) for a in node.args]
        if func in ("bytes.fromhex", "bytearray.fromhex"):
            return bytes.fromhex(args[0])
        if func in ("bytes", "bytearray"):
            return bytes(*args)
    value = ast.literal_eval(node)
    if not isinstance(value, (bytes, bytearray)):
        raise ValueError("not a bytes value")
    return bytes(value)


def load_reference_payloads(path: str) -> dict[str, bytes]:
    """ Reads the module-level MSG_* bytes constants of the reference script WITHOUT executing it"""
    with open(path, encoding="utf-8") as f:
        tree = ast.parse(f.read(), filename=path)
    payloads = {}
    for node in tree.body:
        if not isinstance(node, ast.Assign) or len(node.targets) != 1:
            continue
        target = node.targets[0]
        if isinstance(target, ast.Name) and target.id.startswith("MSG_"):
            try:
                payloads[target.id] = _eval_bytes(node.value)
            except Exception:
                print(f"[WARN] {target.id}: could not read it as bytes, skipped")
    return payloads


# ------------------------------------------------------------------------------------------------
# Multicast groups from Config_FEL.json
# ------------------------------------------------------------------------------------------------
_MCAST_RE = re.compile(r"2(2[4-9]|3\d)\.\d{1,3}\.\d{1,3}\.\d{1,3}")


def _norm(name: str) -> str:
    name = re.sub(r"message$", "", name.lower())
    return re.sub(r"[^a-z0-9]", "", name)


def load_fel_groups(path: str) -> dict[str, str]:
    """ Returns {normalized message name: multicast group} found anywhere in the json.
    Supports {"TrackReport": "224.6.106.1"}, {"TrackReport": {"Ip": "224.6.106.1"}}
    and {"Name": "TrackReport", "Ip": "224.6.106.1"}.
    """
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    groups: dict[str, str] = {}

    def is_mcast(v):
        return isinstance(v, str) and _MCAST_RE.fullmatch(v)

    def walk(node, key=None):
        if isinstance(node, dict):
            ips = [v for v in node.values() if is_mcast(v)]
            for k, v in node.items():
                if is_mcast(v):
                    groups.setdefault(_norm(k), v)
                else:
                    walk(v, k)
            if len(ips) == 1:
                if key:
                    groups.setdefault(_norm(key), ips[0])
                for v in node.values():
                    if isinstance(v, str) and not is_mcast(v):
                        groups.setdefault(_norm(v), ips[0])
        elif isinstance(node, list):
            for v in node:
                walk(v, key)

    walk(data)
    return groups


def group_for(msg_cls_name: str, groups: dict[str, str]) -> str:
    for candidate in (CONFIG_NAME_ALIASES.get(msg_cls_name), msg_cls_name):
        if candidate and _norm(candidate) in groups:
            return groups[_norm(candidate)]
    raise KeyError(f"no multicast group for {msg_cls_name} in Config_FEL.json "
                   f"(add it to CONFIG_NAME_ALIASES). Names found: {sorted(groups)}")


# ------------------------------------------------------------------------------------------------
# Scenario messages built from the simulator's classes
# ------------------------------------------------------------------------------------------------
def body_to_dict(body) -> dict:
    values = {}
    for name, field_type in body._fields_:
        value = getattr(body, name)
        values[name] = list(value) if hasattr(field_type, "_length_") else int(value)
    if isinstance(body, DFCIWrapperMessage):
        values["payload"] = bytes(body.payload)
    return values


def dict_to_body(msg_cls, values: dict):
    body = msg_cls()
    field_types = dict(msg_cls._fields_)
    for name, value in values.items():
        if name == "payload":
            body.payload = bytes(value)
        elif isinstance(value, (list, tuple)):
            setattr(body, name, field_types[name](*value))
        else:
            setattr(body, name, value)
    return body


@dataclass
class ScenarioMsg:
    """ One message of a scenario: class name, sender FID and the field values of each iteration"""
    msg_cls_name: str
    fid: int
    iterations: list[dict] = field(default_factory=lambda: [{}])
    version: int = 1
    group: str = None   # None -> taken from Config_FEL.json
    label: str = ""

    @classmethod
    def from_reference(cls, payloads: dict[str, bytes], name: str) -> "ScenarioMsg":
        """ Decodes a reference payload with Messages.py and keeps its values as a ScenarioMsg"""
        raw = payloads[name]
        msg_id = extract_msg_id(int.from_bytes(raw[0:2], "little"))
        if msg_id not in MSG_CLS_REGISTRY:
            raise KeyError(f"{name}: MSG_ID {msg_id} is not in MSG_CLS_REGISTRY")
        msg = Message.from_bytes(raw)
        return cls(
            msg_cls_name=type(msg.bodies[0]).__name__,
            fid=msg.header.function_id,
            iterations=[body_to_dict(b) for b in msg.bodies],
            version=(msg.header.msg_version_id >> 13) & 0x3,
            label=name,
        )

    def build(self, seq_number: int) -> Message:
        msg_cls = MSG_NAME_CLS_ALL_DICT[self.msg_cls_name]
        bodies = [dict_to_body(msg_cls, it) for it in self.iterations]
        return build_message(bodies, function_id=self.fid, seq_number=seq_number, msg_version=self.version)

    def code(self) -> str:
        """ Python code that recreates this ScenarioMsg (to paste it in SCENARIOS)"""
        its = ",\n        ".join(repr(it) for it in self.iterations)
        return (f"ScenarioMsg({self.msg_cls_name!r}, fid={self.fid}, version={self.version},\n"
                f"    iterations=[\n        {its}\n    ])")


def discovery(fid: int, ip: str, status: int = 1, mode: int = 1) -> ScenarioMsg:
    #! validity/last_BIT_ts/mode are provisional values, to be confirmed against the spec
    return ScenarioMsg("DiscoveryMessage", fid, [dict(
        validity=1, addr=ip_to_uint32(ip), data_loader=0, last_BIT_ts=1, status=status, mode=mode
    )], label=f"Discovery FID {fid}")


def _cmds_summary(ref):
    return [ScenarioMsg.from_reference(ref, name) for name in (
        "MSG_CMDS_DISCOVERY_OPER_AUTO",
        "MSG_CMDS_FLARE_4x_AT_1_2_3",
        "MSG_CMDS_FLARE_10x_AT_1_3_3",
        "MSG_CMDS_CHAFS_7x_AT_1_6_3",
    )]


def _rwr_threat(ref):
    track = ScenarioMsg.from_reference(ref, "MSG_RWR_TRACK_REPORT")
    return [track, discovery(fid=track.fid, ip=LOOPBACK_IP)]


# Each scenario receives the reference payloads and returns its list of ScenarioMsg.
# Messages can be taken from a reference payload or written with explicit values
# (python FelTest.py roundtrip --emit prints the code of every reference payload).
SCENARIOS = {
    "CMDS_summary": _cmds_summary,
    "RWR_threat": _rwr_threat,
    "CMDS_RWR": lambda ref: _cmds_summary(ref) + _rwr_threat(ref),
}


# ------------------------------------------------------------------------------------------------
# Round trip test (no network)
# ------------------------------------------------------------------------------------------------
def roundtrip(payloads: dict[str, bytes], emit: bool = False) -> bool:
    """ Decodes every reference payload with Messages.py, re-encodes it and compares byte by byte"""
    all_ok = True
    for name, raw in payloads.items():
        msg_id = extract_msg_id(int.from_bytes(raw[0:2], "little")) if len(raw) >= 2 else None
        body_cls = MSG_CLS_REGISTRY.get(msg_id)
        if body_cls is None:
            print(f"[FAIL] {name}: MSG_ID {msg_id} is not in MSG_CLS_REGISTRY")
            all_ok = False
            continue
        try:
            msg = Message.from_bytes(raw)
            header = msg.header
            expected_len = 16 + header.single_it_len * header.number_of_it
            problems = []
            if body_cls is not DFCIWrapperMessage:
                if ctypes.sizeof(body_cls) != header.single_it_len:
                    problems.append(f"sizeof({body_cls.__name__})={ctypes.sizeof(body_cls)} "
                                    f"but header says {header.single_it_len}")
                if len(raw) != expected_len:
                    problems.append(f"payload has {len(raw)} bytes, header says {expected_len}")
            encoded = bytes(msg)
            if encoded != raw:
                diff = next((i for i, (a, b) in enumerate(zip(encoded, raw)) if a != b),
                            min(len(encoded), len(raw)))
                problems.append(f"re-encoded bytes differ at offset {diff} "
                                f"({len(encoded)} vs {len(raw)} bytes)")
        except Exception as e:
            print(f"[FAIL] {name}: could not decode: {e}")
            all_ok = False
            continue
        status = "OK  " if not problems else "FAIL"
        print(f"[{status}] {name}: {body_cls.__name__}, FID {header.function_id}, "
              f"{header.number_of_it} it., {len(raw)} B")
        for p in problems:
            print(f"        - {p}")
        all_ok &= not problems
        if emit and body_cls is not DFCIWrapperMessage:
            print(ScenarioMsg.from_reference(payloads, name).code() + "\n")
    print("Round trip:", "all payloads OK" if all_ok else "there are failures")
    return all_ok


# ------------------------------------------------------------------------------------------------
# Sending
# ------------------------------------------------------------------------------------------------
class FelSender:
    """ Sends scenario messages to FEL through loopback multicast, with its own source IP"""

    def __init__(self, groups: dict[str, str], ip: str = LOOPBACK_IP, port: int = MULTICAST_PORT,
                 dry_run: bool = False):
        self._groups = groups
        self._port = port
        self._dry_run = dry_run
        self._seq: dict[tuple[int, int], int] = {}
        self._sock = None if dry_run else self._open_socket(ip)

    @staticmethod
    def _open_socket(ip: str) -> socket.socket:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.settimeout(SOCKET_TIMEOUT)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_LOOP, 1)
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 1)
        if os.name == "nt":
            sock.bind((ip, 0))  # on Windows the bound address selects the multicast interface
        else:
            sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_IF, socket.inet_aton(ip))
        return sock

    def send(self, entry: ScenarioMsg):
        msg_id = MSG_NAME_CLS_ALL_DICT[entry.msg_cls_name].MSG_ID
        key = (entry.fid, msg_id)
        self._seq[key] = (self._seq.get(key, -1) + 1) & 0xFFFF
        data = bytes(entry.build(self._seq[key]))
        group = entry.group or group_for(entry.msg_cls_name, self._groups)
        if not self._dry_run:
            self._sock.sendto(data, (group, self._port))
        print(f"[TX] {entry.label or entry.msg_cls_name} -> {group}:{self._port} "
              f"({len(data)} B, seq {self._seq[key]}){' [dry-run]' if self._dry_run else ''}")

    def loop(self, entries: list[ScenarioMsg], period: float = TX_PERIOD):
        """ Sends the whole scenario every period seconds until Ctrl+C"""
        while True:
            for entry in entries:
                self.send(entry)
            time.sleep(period)

    def step(self, entries: list[ScenarioMsg]):
        """ Sends the scenario one message at a time, waiting for Enter between them"""
        for i, entry in enumerate(entries):
            input(f"Enter to send [{i}] {entry.label or entry.msg_cls_name}...")
            self.send(entry)

    def single(self, entry: ScenarioMsg, period: float = TX_PERIOD):
        """ Repeats one message every period seconds until Ctrl+C"""
        while True:
            self.send(entry)
            time.sleep(period)

    def close(self):
        if self._sock:
            self._sock.close()


# ------------------------------------------------------------------------------------------------
# Command line
# ------------------------------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="NDAS_FEL multicast test bench")
    parser.add_argument("--ref", default=REFERENCE_PATH, help="reference script with MSG_* payloads")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("list", help="list scenarios and reference payloads")

    rt = sub.add_parser("roundtrip", help="decode/encode the reference payloads (no network)")
    rt.add_argument("--emit", action="store_true", help="print ScenarioMsg code for each payload")

    tx = sub.add_parser("send", help="send a scenario")
    tx.add_argument("scenario", choices=sorted(SCENARIOS))
    tx.add_argument("--mode", choices=("loop", "step", "single"), default="loop")
    tx.add_argument("--index", type=int, default=0, help="message of the scenario for --mode single")
    tx.add_argument("--period", type=float, default=TX_PERIOD, help="seconds between sends")
    tx.add_argument("--config", default=FEL_CONFIG_PATH, help="Config_FEL.json")
    tx.add_argument("--ip", default=LOOPBACK_IP, help="own source IP")
    tx.add_argument("--dry-run", action="store_true", help="build and print, don't send")
    args = parser.parse_args()

    payloads = load_reference_payloads(args.ref)

    if args.cmd == "list":
        print("Scenarios:", ", ".join(sorted(SCENARIOS)))
        print("Reference payloads:", ", ".join(payloads) or "(none)")
        return
    if args.cmd == "roundtrip":
        raise SystemExit(0 if roundtrip(payloads, emit=args.emit) else 1)

    try:
        entries = SCENARIOS[args.scenario](payloads)
    except KeyError as e:
        raise SystemExit(f"[ERROR] scenario {args.scenario}: missing payload or class {e}")
    sender = FelSender(load_fel_groups(args.config), ip=args.ip, dry_run=args.dry_run)
    try:
        if args.mode == "loop":
            sender.loop(entries, args.period)
        elif args.mode == "step":
            sender.step(entries)
        else:
            if not 0 <= args.index < len(entries):
                raise SystemExit(f"--index must be between 0 and {len(entries) - 1}")
            sender.single(entries[args.index], args.period)
    except KeyboardInterrupt:
        print("\n[INFO] stopped")
    finally:
        sender.close()


if __name__ == "__main__":
    main()
