#!/usr/bin/env python3
"""Generate runtime files for H323 (gnugk) from OPNsense model config."""

import json
import os
import pwd
import grp
import sys
import xml.etree.ElementTree as ET

CONFIG_XML = "/conf/config.xml"
RUNTIME_DIR = "/etc/h323"
GNUGK_CONF = f"{RUNTIME_DIR}/gnugk.conf"
RUNTIME_JSON = "/var/db/h323/config.json"


def infer_deployment_mode(upstream_server: str) -> str:
    local_servers = {"", "127.0.0.1", "localhost", "::1"}
    return "local" if (upstream_server or "").strip().lower() in local_servers else "upstream"


def read_model_config():
    tree = ET.parse(CONFIG_XML)
    root = tree.getroot()
    h323_node = root.find(".//OPNsense/h323")
    if h323_node is None:
        return {"general": {}, "endpoints": []}

    general_node = h323_node.find("general")
    general = {
        "enabled": (general_node.findtext("enabled", "0") == "1") if general_node is not None else False,
        "signaling_port": int(general_node.findtext("signaling_port", "1720")) if general_node is not None else 1720,
        "rtp_port_range_start": int(general_node.findtext("rtp_port_range_start", "5000")) if general_node is not None else 5000,
        "rtp_port_range_end": int(general_node.findtext("rtp_port_range_end", "5100")) if general_node is not None else 5100,
        "nat_enabled": (general_node.findtext("nat_enabled", "1") == "1") if general_node is not None else True,
        "gateway_alias": general_node.findtext("gateway_alias", "OTSA-H323") if general_node is not None else "OTSA-H323",
        "listen_interface": general_node.findtext("listen_interface", "") if general_node is not None else "",
        "deployment_mode": general_node.findtext("deployment_mode", "local") if general_node is not None else "local",
        "outbound_interface": general_node.findtext("outbound_interface", "") if general_node is not None else "",
        "upstream_server": general_node.findtext("upstream_server", "") if general_node is not None else "",
    }

    endpoints = []
    endpoints_root = h323_node.find("endpoints")
    if endpoints_root is not None:
        for ep in endpoints_root.findall("endpoint"):
            endpoints.append(
                {
                    "name": ep.findtext("name", ""),
                    "address": ep.findtext("address", ""),
                    "enabled": ep.findtext("enabled", "1") == "1",
                    "description": ep.findtext("description", ""),
                }
            )

    return {"general": general, "endpoints": endpoints}


def detect_interface_ip(interface_name: str) -> str:
    if not interface_name:
        return "0.0.0.0"
    try:
        tree = ET.parse(CONFIG_XML)
        root = tree.getroot()
        iface_node = root.find(f".//interfaces/{interface_name}")
        if iface_node is None:
            return "0.0.0.0"
        ipaddr = (iface_node.findtext("ipaddr", "") or "").strip()
        if ipaddr in ("", "dhcp", "pppoe"):
            return "0.0.0.0"
        return ipaddr
    except Exception:
        return "0.0.0.0"


def build_gnugk_config(model):
    g = model["general"]
    home_ip = detect_interface_ip(g.get("listen_interface", ""))
    deployment_mode = infer_deployment_mode(g.get("upstream_server", ""))

    lines = []
    lines.append("[Gatekeeper::Main]")
    lines.append(f"Name={g.get('gateway_alias', 'OTSA-H323')}")
    lines.append(f"Home={home_ip}")
    lines.append("")

    lines.append("[RoutedMode]")
    lines.append("GKRouted=1")
    lines.append("H245Routed=1")
    lines.append(f"CallSignalPort={g.get('signaling_port', 1720)}")
    lines.append("")

    lines.append("[Proxy]")
    lines.append("Enable=1" if g.get("enabled", False) else "Enable=0")
    lines.append("EnableNATedH323=1" if g.get("nat_enabled", True) else "EnableNATedH323=0")
    lines.append(f"; DeploymentMode={deployment_mode}")
    if g.get("outbound_interface"):
        lines.append(f"; OutboundInterface={g.get('outbound_interface')}")
    if g.get("upstream_server"):
        lines.append(f"; UpstreamServer={g.get('upstream_server')}")
    lines.append("")

    lines.append("[RTP]")
    lines.append(f"RTPPortRange={g.get('rtp_port_range_start', 5000)}-{g.get('rtp_port_range_end', 5100)}")
    lines.append("")

    lines.append("[Neighbors]")
    for ep in model.get("endpoints", []):
        if ep.get("enabled") and ep.get("name") and ep.get("address"):
            lines.append(f"{ep['name']}={ep['address']}")
    lines.append("")

    return "\n".join(lines)


def safe_chown(path):
    try:
        uid = pwd.getpwnam("h323").pw_uid
        gid = grp.getgrnam("h323").gr_gid
        os.chown(path, uid, gid)
    except KeyError:
        # user/group may not exist in prototype env
        pass


def write_runtime_files(model):
    os.makedirs(RUNTIME_DIR, exist_ok=True)
    os.makedirs(os.path.dirname(RUNTIME_JSON), exist_ok=True)

    gnugk_conf = build_gnugk_config(model)

    with open(GNUGK_CONF, "w", encoding="utf-8") as f:
        f.write(gnugk_conf)
    with open(RUNTIME_JSON, "w", encoding="utf-8") as f:
        json.dump({"h323": model}, f, indent=2)

    os.chmod(GNUGK_CONF, 0o640)
    os.chmod(RUNTIME_JSON, 0o640)
    safe_chown(GNUGK_CONF)
    safe_chown(RUNTIME_JSON)


def main():
    try:
        model = read_model_config()
        write_runtime_files(model)
        print("H323 runtime configuration generated")
        return 0
    except Exception as e:
        print(f"Error applying H323 runtime config: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
