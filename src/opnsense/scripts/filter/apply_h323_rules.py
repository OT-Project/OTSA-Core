#!/usr/bin/env python3
"""
H.323 Gateway Firewall Rule Generator

This script reads the H323 model configuration from OPNsense config.xml and generates 
PF firewall rules to allow traffic to/from the H323 proxy gateway. It creates an anchor 
file that can be included in the OPNsense filter rules.

When the H323 proxy is enabled, it ensures:
- UDP 1719 (RAS) is allowed inbound on the listen interface
- TCP 1720 (H.225 call setup) is allowed inbound on the listen interface
- UDP RTP port range is allowed
- Optional NAT/rdr rules for 1719/1720/RTP if NAT mode is enabled

When disabled, all rules are removed.
"""

import sys
import os
import xml.etree.ElementTree as ET
import uuid

# OPNsense paths
CONFIG_PATH = '/conf/config.xml'
ANCHOR_DIR = '/var/lib/filter'
H323_ANCHOR_FILE = os.path.join(ANCHOR_DIR, 'h323.anchor')


def infer_deployment_mode(upstream_server: str) -> str:
    local_servers = {"", "127.0.0.1", "localhost", "::1"}
    return 'local' if (upstream_server or '').strip().lower() in local_servers else 'upstream'


def ensure_path(parent, path):
    """Ensure nested XML path exists and return the last node."""
    node = parent
    for part in path:
        child = node.find(part)
        if child is None:
            child = ET.SubElement(node, part)
        node = child
    return node


def load_model_config():
    """Load H323 model configuration from OPNsense config.xml"""
    try:
        tree = ET.parse(CONFIG_PATH)
        root = tree.getroot()
        
        # Navigate to OPNsense/h323 node
        h323_node = root.find('.//OPNsense/h323')
        if h323_node is None:
            return None
        
        config = {}
        general = h323_node.find('general')
        if general is not None:
            config['enabled'] = general.findtext('enabled', '0') == '1'
            config['listen_interface'] = general.findtext('listen_interface', '')
            config['signaling_port'] = general.findtext('signaling_port', '1720')
            config['rtp_port_range_start'] = general.findtext('rtp_port_range_start', '5000')
            config['rtp_port_range_end'] = general.findtext('rtp_port_range_end', '5100')
            config['nat_enabled'] = general.findtext('nat_enabled', '1') == '1'
            config['gateway_alias'] = general.findtext('gateway_alias', 'OTSA-H323')
            config['outbound_interface'] = general.findtext('outbound_interface', '')
            config['upstream_server'] = general.findtext('upstream_server', '')
        
        return config
    except Exception as e:
        print(f"Error loading model config: {e}", file=sys.stderr)
        return None


def generate_pf_rules(config):
    """Generate PF firewall rules for H323 proxy"""
    if not config or not config.get('enabled'):
        return None
    
    listen_iface = config.get('listen_interface', '')
    if not listen_iface:
        print("Warning: listen_interface not configured, skipping rule generation", file=sys.stderr)
        return None
    
    signaling_port = config.get('signaling_port', '1720')
    ras_port = '1719'
    rtp_start = config.get('rtp_port_range_start', '5000')
    rtp_end = config.get('rtp_port_range_end', '5100')
    gateway_alias = config.get('gateway_alias', 'h323')
    
    rules = []
    rules.append(f"# H323 Gateway Firewall Rules")
    rules.append(f"# Proxy: {gateway_alias}")
    rules.append(f"# Interface: {listen_iface}")
    rules.append(f"# RAS: UDP/{ras_port}, Signaling: TCP/{signaling_port}, RTP: UDP/{rtp_start}:{rtp_end}")
    rules.append(f"")

    # Allow inbound RAS (gatekeeper registration/admission/status)
    rules.append(f"# H.323 RAS")
    rules.append(f"pass in on {listen_iface} proto udp from any to any port {ras_port} keep state")
    rules.append(f"")
    
    # Allow inbound H.225 call setup (TCP 1720)
    rules.append(f"# H.225 Call Setup")
    rules.append(f"pass in on {listen_iface} proto tcp from any to any port {signaling_port} keep state")
    rules.append(f"")
    
    # Allow inbound and outbound RTP (UDP port range)
    rules.append(f"# RTP Media")
    rules.append(f"pass in on {listen_iface} proto udp from any to any port {rtp_start}:{rtp_end} keep state")
    rules.append(f"pass out on {listen_iface} proto udp from any to any port {rtp_start}:{rtp_end} keep state")

    deployment_mode = infer_deployment_mode(config.get('upstream_server', ''))
    outbound_iface = (config.get('outbound_interface') or '').strip()
    upstream_server = (config.get('upstream_server') or '').strip()

    if deployment_mode == 'upstream' and outbound_iface and upstream_server:
        rules.append("")
        rules.append(f"# Upstream Gateway")
        rules.append(f"pass out on {outbound_iface} proto udp from any to {upstream_server} port {ras_port} keep state")
        rules.append(f"pass out on {outbound_iface} proto tcp from any to {upstream_server} port {signaling_port} keep state")
        rules.append(f"pass out on {outbound_iface} proto udp from any to {upstream_server} port {rtp_start}:{rtp_end} keep state")
    
    return "\n".join(rules)


def remove_existing_h323_objects(root):
    """Remove previously generated H323 firewall/NAT entries."""
    filter_rules = root.findall('./OPNsense/Firewall/Filter/rules/rule')
    for rule in list(filter_rules):
        descr = (rule.findtext('description', '') or '')
        if descr.startswith('H323 Proxy:'):
            rule_parent = root.find('./OPNsense/Firewall/Filter/rules')
            if rule_parent is not None:
                rule_parent.remove(rule)

    nat_rules = root.findall('./nat/rule')
    for rule in list(nat_rules):
        descr = (rule.findtext('descr', '') or '')
        if descr.startswith('H323 Proxy:'):
            nat_parent = root.find('./nat')
            if nat_parent is not None:
                nat_parent.remove(rule)


def next_sequence(rule_parent):
    """Return next sequence number for a firewall-style ordered collection."""
    max_seq = 0
    for rule in rule_parent.findall('./rule'):
        for field_name in ('sequence', 'seq'):
            seq_text = rule.findtext(field_name, '')
            try:
                max_seq = max(max_seq, int(seq_text))
            except Exception:
                continue
    return str(max_seq + 10 if max_seq else 10)


def upsert_config_objects(config):
    """Write visible firewall and NAT objects into config.xml."""
    try:
        tree = ET.parse(CONFIG_PATH)
        root = tree.getroot()
    except Exception as e:
        print(f"Error parsing config.xml: {e}", file=sys.stderr)
        return False

    remove_existing_h323_objects(root)

    if not config or not config.get('enabled'):
        try:
            tree.write(CONFIG_PATH, encoding='utf-8', xml_declaration=True)
            return True
        except Exception as e:
            print(f"Error writing disabled config.xml: {e}", file=sys.stderr)
            return False

    listen_iface = config.get('listen_interface', '')
    deployment_mode = infer_deployment_mode(config.get('upstream_server', ''))
    outbound_iface = (config.get('outbound_interface') or '').strip()
    upstream_server = (config.get('upstream_server') or '').strip()
    ras_port = '1719'
    signaling_port = str(config.get('signaling_port', '1720'))
    rtp_start = str(config.get('rtp_port_range_start', '5000'))
    rtp_end = str(config.get('rtp_port_range_end', '5100'))

    # Firewall rules section
    fw_root = ensure_path(root, ['OPNsense', 'Firewall', 'Filter'])
    fw_rules = ensure_path(fw_root, ['rules'])

    def add_filter_rule(description, protocol, destination_port):
        rule = ET.SubElement(fw_rules, 'rule')
        rule.set('uuid', str(uuid.uuid4()))
        ET.SubElement(rule, 'enabled').text = '1'
        ET.SubElement(rule, 'statetype').text = 'keep'
        ET.SubElement(rule, 'sequence').text = next_sequence(fw_rules)
        ET.SubElement(rule, 'action').text = 'pass'
        ET.SubElement(rule, 'quick').text = '1'
        ET.SubElement(rule, 'interfacenot').text = '0'
        ET.SubElement(rule, 'interface').text = listen_iface
        ET.SubElement(rule, 'direction').text = 'in'
        ET.SubElement(rule, 'ipprotocol').text = 'inet'
        ET.SubElement(rule, 'protocol').text = protocol
        ET.SubElement(rule, 'source_net').text = 'any'
        ET.SubElement(rule, 'source_not').text = '0'
        ET.SubElement(rule, 'destination_net').text = listen_iface
        ET.SubElement(rule, 'destination_not').text = '0'
        ET.SubElement(rule, 'destination_port').text = destination_port
        ET.SubElement(rule, 'log').text = '1'
        ET.SubElement(rule, 'nosync').text = '0'
        ET.SubElement(rule, 'nopfsync').text = '0'
        ET.SubElement(rule, 'description').text = description
        return rule

    add_filter_rule('H323 Proxy: Signaling', 'tcp', signaling_port)
    add_filter_rule('H323 Proxy: RAS', 'udp', ras_port)
    add_filter_rule('H323 Proxy: RTP', 'udp', f'{rtp_start}:{rtp_end}')

    if deployment_mode == 'upstream' and outbound_iface and upstream_server:
        def add_outbound_filter_rule(description, protocol, destination_port):
            rule = ET.SubElement(fw_rules, 'rule')
            rule.set('uuid', str(uuid.uuid4()))
            ET.SubElement(rule, 'enabled').text = '1'
            ET.SubElement(rule, 'statetype').text = 'keep'
            ET.SubElement(rule, 'sequence').text = next_sequence(fw_rules)
            ET.SubElement(rule, 'action').text = 'pass'
            ET.SubElement(rule, 'quick').text = '1'
            ET.SubElement(rule, 'interfacenot').text = '0'
            ET.SubElement(rule, 'interface').text = outbound_iface
            ET.SubElement(rule, 'direction').text = 'out'
            ET.SubElement(rule, 'ipprotocol').text = 'inet'
            ET.SubElement(rule, 'protocol').text = protocol
            ET.SubElement(rule, 'source_net').text = 'any'
            ET.SubElement(rule, 'source_not').text = '0'
            ET.SubElement(rule, 'destination_net').text = upstream_server
            ET.SubElement(rule, 'destination_not').text = '0'
            ET.SubElement(rule, 'destination_port').text = destination_port
            ET.SubElement(rule, 'log').text = '1'
            ET.SubElement(rule, 'nosync').text = '0'
            ET.SubElement(rule, 'nopfsync').text = '0'
            ET.SubElement(rule, 'description').text = description
            return rule

        add_outbound_filter_rule('H323 Proxy: Upstream RAS', 'udp', ras_port)
        add_outbound_filter_rule('H323 Proxy: Upstream Signaling', 'tcp', signaling_port)
        add_outbound_filter_rule('H323 Proxy: Upstream RTP', 'udp', f'{rtp_start}:{rtp_end}')

    # NAT / port-forward section
    nat_root = ensure_path(root, ['nat'])
    if config.get('nat_enabled', True):
        nat_target = upstream_server if deployment_mode == 'upstream' and upstream_server else '127.0.0.1'

        def add_nat_rule(description, protocol, destination_port, local_port, target_port=None):
            nat_rule = ET.SubElement(nat_root, 'rule')
            nat_rule.set('uuid', str(uuid.uuid4()))
            ET.SubElement(nat_rule, 'sequence').text = next_sequence(nat_root)
            ET.SubElement(nat_rule, 'disabled').text = '0'
            ET.SubElement(nat_rule, 'nordr').text = '0'
            ET.SubElement(nat_rule, 'interface').text = listen_iface
            ET.SubElement(nat_rule, 'ipprotocol').text = 'inet'
            ET.SubElement(nat_rule, 'protocol').text = protocol
            source = ET.SubElement(nat_rule, 'source')
            ET.SubElement(source, 'network').text = 'any'
            ET.SubElement(source, 'address').text = ''
            ET.SubElement(source, 'port').text = ''
            ET.SubElement(source, 'not').text = '0'
            destination = ET.SubElement(nat_rule, 'destination')
            ET.SubElement(destination, 'network').text = 'any'
            ET.SubElement(destination, 'address').text = ''
            ET.SubElement(destination, 'port').text = destination_port
            ET.SubElement(destination, 'not').text = '0'
            ET.SubElement(nat_rule, 'target').text = nat_target
            ET.SubElement(nat_rule, 'local-port').text = target_port or local_port
            ET.SubElement(nat_rule, 'poolopts').text = ''
            ET.SubElement(nat_rule, 'log').text = '1'
            ET.SubElement(nat_rule, 'categories').text = ''
            ET.SubElement(nat_rule, 'tagged').text = ''
            ET.SubElement(nat_rule, 'natreflection').text = ''
            ET.SubElement(nat_rule, 'pass').text = 'pass'
            ET.SubElement(nat_rule, 'descr').text = description
            return nat_rule

        add_nat_rule('H323 Proxy: RAS Port Forward', 'udp', ras_port, ras_port)

        nat_rule = ET.SubElement(nat_root, 'rule')
        nat_rule.set('uuid', str(uuid.uuid4()))
        ET.SubElement(nat_rule, 'sequence').text = next_sequence(nat_root)
        ET.SubElement(nat_rule, 'disabled').text = '0'
        ET.SubElement(nat_rule, 'nordr').text = '0'
        ET.SubElement(nat_rule, 'interface').text = listen_iface
        ET.SubElement(nat_rule, 'ipprotocol').text = 'inet'
        ET.SubElement(nat_rule, 'protocol').text = 'tcp'
        source = ET.SubElement(nat_rule, 'source')
        ET.SubElement(source, 'network').text = 'any'
        ET.SubElement(source, 'address').text = ''
        ET.SubElement(source, 'port').text = ''
        ET.SubElement(source, 'not').text = '0'
        destination = ET.SubElement(nat_rule, 'destination')
        ET.SubElement(destination, 'network').text = 'any'
        ET.SubElement(destination, 'address').text = ''
        ET.SubElement(destination, 'port').text = signaling_port
        ET.SubElement(destination, 'not').text = '0'
        ET.SubElement(nat_rule, 'target').text = nat_target
        ET.SubElement(nat_rule, 'local-port').text = signaling_port
        ET.SubElement(nat_rule, 'poolopts').text = ''
        ET.SubElement(nat_rule, 'log').text = '1'
        ET.SubElement(nat_rule, 'categories').text = ''
        ET.SubElement(nat_rule, 'tagged').text = ''
        ET.SubElement(nat_rule, 'natreflection').text = ''
        ET.SubElement(nat_rule, 'pass').text = 'pass'
        ET.SubElement(nat_rule, 'descr').text = 'H323 Proxy: Signaling Port Forward'

        add_nat_rule('H323 Proxy: RTP Port Forward', 'udp', f'{rtp_start}:{rtp_end}', f'{rtp_start}:{rtp_end}')

    try:
        tree.write(CONFIG_PATH, encoding='utf-8', xml_declaration=True)
        print(f"Updated config.xml with H323 firewall objects for {listen_iface}")
        return True
    except Exception as e:
        print(f"Error writing config.xml firewall objects: {e}", file=sys.stderr)
        return False


def write_anchor_file(rules_content, anchor_file):
    """Write anchor rules to file"""
    if not rules_content:
        # If rules are None and file exists, remove it (proxy disabled)
        if os.path.exists(anchor_file):
            try:
                os.remove(anchor_file)
                print(f"Removed anchor file: {anchor_file}")
            except Exception as e:
                print(f"Error removing anchor file {anchor_file}: {e}", file=sys.stderr)
                return False
        return True
    
    try:
        os.makedirs(os.path.dirname(anchor_file), exist_ok=True)
        with open(anchor_file, 'w') as f:
            f.write(rules_content)
        os.chmod(anchor_file, 0o644)
        print(f"Wrote anchor file: {anchor_file}")
        return True
    except Exception as e:
        print(f"Error writing anchor file {anchor_file}: {e}", file=sys.stderr)
        return False


def reload_firewall_rules():
    """Reload firewall rules via OPNsense backend"""
    try:
        # Use the standard configd filter reload action
        result = os.system("configctl filter reload >/dev/null 2>&1")
        if result == 0:
            print("Firewall rules reloaded")
            return True
        print(f"Warning: filter reload returned {result}", file=sys.stderr)
        return True
    except Exception as e:
        print(f"Warning: Error reloading firewall rules: {e}", file=sys.stderr)
        return True  # Don't fail if reload script not found


def main():
    """Main entry point"""
    # Load model configuration
    config = load_model_config()
    if config is None:
        print("Error: Could not load H323 model configuration", file=sys.stderr)
        sys.exit(1)
    
    # Generate rules (or None if disabled)
    pf_rules = generate_pf_rules(config) if config.get('enabled') else None
    
    # Write/remove anchor file (kept for compatibility / legacy use)
    if not write_anchor_file(pf_rules, H323_ANCHOR_FILE):
        sys.exit(1)

    # Write visible firewall/NAT objects into config.xml so they appear in the GUI
    if not upsert_config_objects(config):
        sys.exit(1)
    
    # Reload filter rules
    if not reload_firewall_rules():
        print("Warning: Firewall rules may not have been fully reloaded", file=sys.stderr)
    
    print("H323 firewall rules applied successfully")
    sys.exit(0)


if __name__ == '__main__':
    main()
