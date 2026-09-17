<?php

/*
 * Copyright (C) 2004 Scott Ullrich <sullrich@gmail.com>
 * Copyright (C) 2004 Fred Mol <fredmol@xs4all.nl>
 * Copyright (C) 2015-2024 Franco Fichtner <franco@opnsense.org>
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 * OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

function openssh_enabled()
{
    global $config;

    return isset($config['system']['ssh']['enabled']) ||
        (!isset($config['system']['ssh']['noauto']) && is_install_media());
}

function openssh_configure()
{
    return [
        'early' => ['openssh_configure_do'],
        'local' => ['openssh_configure_do'],
        'newwanip' => ['openssh_configure_do:2'],
    ];
}

function openssh_services()
{
    $services = [];

    if (openssh_enabled()) {
        $pconfig = [];
        $pconfig['description'] = gettext('Secure Shell Daemon');
        $pconfig['configd']['restart'] = ['openssh restart'];
        $pconfig['configd']['start'] = ['openssh start'];
        $pconfig['configd']['stop'] = ['openssh stop'];
        $pconfig['pidfile'] = '/var/run/sshd.pid';
        $pconfig['name'] = 'openssh';
        $services[] = $pconfig;
    }

    return $services;
}

/**
 *  sync configuration via xmlrpc
 * @return array
 */
function openssh_xmlrpc_sync()
{
    return [[
        'description' => gettext('OpenSSH'),
        'section' => 'system.ssh',
        'services' => ['openssh'],
        'id' => 'ssh',
    ]];
}


function openssh_stop()
{
    mwexecf('service sshd stop');
}

function openssh_host_key_types()
{
    return ['rsa', 'ecdsa', 'ed25519'];
}

function openssh_host_key_path($type)
{
    return "/conf/sshd/ssh_host_{$type}_key";
}

function openssh_host_key_fingerprint($type)
{
    $pub = openssh_host_key_path($type) . '.pub';
    if (!file_exists($pub)) {
        return null;
    }

    $output = [];
    $rc = 0;
    exec('/usr/local/bin/ssh-keygen -l -E sha256 -f ' . escapeshellarg($pub) . ' 2>/dev/null', $output, $rc);
    if ($rc !== 0 || empty($output)) {
        return null;
    }

    /* ssh-keygen -l output: "<bits> SHA256:<hash> <comment> (<algorithm>)" */
    if (preg_match('/^(\d+)\s+(\S+)\s+(.*)\s+\(([^)]+)\)\s*$/', $output[0], $m)) {
        return [
            'bits' => (int)$m[1],
            'sha256' => $m[2],
            'comment' => trim($m[3]),
            'algorithm' => $m[4],
        ];
    }

    return null;
}

function openssh_rsa_bit_choices()
{
    return [3072, 4096, 11776];
}

function openssh_host_key_public_text($type)
{
    $pub = openssh_host_key_path($type) . '.pub';
    return file_exists($pub) ? trim(file_get_contents($pub)) : null;
}

function openssh_host_keys_known_hosts_block()
{
    global $config;
    $hostname = $config['system']['hostname'] ?? 'opnsense';
    $domain = $config['system']['domain'] ?? '';
    $fqdn = $domain ? "{$hostname}.{$domain}" : $hostname;

    $ips = [];
    foreach (interfaces_addresses(['lan', 'wan']) as $ip => $info) {
        if (!empty($info['family']) && $info['family'] === 'inet') {
            $ips[] = preg_replace('#/\d+$#', '', $ip);
        }
    }

    $host_aliases = array_values(array_filter(array_unique(array_merge([$fqdn, $hostname], $ips))));
    $prefix = implode(',', $host_aliases);

    $lines = [
        "# OTSA host keys for {$fqdn}",
        "# Generated " . date('c'),
        "# Import these entries into your SSH client's known_hosts file via an",
        "# out-of-band channel (USB, signed email, in person) — do NOT fetch over",
        "# an unauthenticated network or you defeat the point.",
    ];

    foreach (openssh_host_key_types() as $type) {
        $pub = openssh_host_key_public_text($type);
        if ($pub === null) {
            continue;
        }
        $parts = explode(' ', $pub, 3);
        if (count($parts) < 2) {
            continue;
        }
        $lines[] = "{$prefix} {$parts[0]} {$parts[1]}";
    }

    return implode("\n", $lines) . "\n";
}

function openssh_regenerate_host_keys(array $types, $rsa_bits = null)
{
    @mkdir('/conf/sshd', 0777, true);

    $valid = openssh_host_key_types();
    $rsa_valid_bits = openssh_rsa_bit_choices();
    $rsa_bits = is_int($rsa_bits) && in_array($rsa_bits, $rsa_valid_bits, true) ? $rsa_bits : null;

    $result = [];

    foreach ($types as $type) {
        if (!in_array($type, $valid, true)) {
            continue;
        }

        $file = openssh_host_key_path($type);
        $old = openssh_host_key_fingerprint($type);

        @unlink($file . '.pub');
        @unlink($file);

        if ($type === 'rsa' && $rsa_bits !== null) {
            $rc = mwexecf('/usr/local/bin/ssh-keygen -t %s -b %s -N "" -f %s',
                          [$type, (string)$rsa_bits, $file]);
        } else {
            $rc = mwexecf('/usr/local/bin/ssh-keygen -t %s -N "" -f %s', [$type, $file]);
        }

        if ($rc === 0 && file_exists($file) && file_exists("{$file}.pub")) {
            $new = openssh_host_key_fingerprint($type);
            $result[$type] = [
                'status' => 'ok',
                'old_fingerprint' => $old['sha256'] ?? null,
                'new_fingerprint' => $new['sha256'] ?? null,
                'old_bits' => $old['bits'] ?? null,
                'bits' => $new['bits'] ?? null,
                'algorithm' => $new['algorithm'] ?? null,
            ];
        } else {
            $result[$type] = [
                'status' => 'error',
                'message' => sprintf('ssh-keygen exited %d', $rc),
                'old_fingerprint' => $old['sha256'] ?? null,
                'new_fingerprint' => null,
                'old_bits' => $old['bits'] ?? null,
                'bits' => null,
            ];
        }
    }

    return $result;
}

function openssh_configure_do($verbose = false, $interface_map = null)
{
    global $config;

    if (!plugins_argument_map($interface_map)) {
        return;
    }

    $sshcfg = null;

    if (isset($config['system']['ssh']['enabled'])) {
        $sshcfg = $config['system']['ssh'];
    } elseif (!isset($config['system']['ssh']['noauto']) && is_install_media()) {
        /* only revert to installer config when ssh is not set at all */
        $sshcfg = ['permitrootlogin' => 1, 'passwordauth' => 1];
    }

    if ($sshcfg === null) {
        openssh_stop();
        return;
    }

    $interfaces = [];

    if (!empty($sshcfg['interfaces'])) {
        $interfaces = explode(',', $sshcfg['interfaces']);
        array_unshift($interfaces, 'lo0');
    }

    /* return if interfaces specified do not match or interfaces are not bound at all */
    if (!empty($interface_map) && !count(array_intersect($interface_map, $interfaces))) {
        return;
    }

    /* lock the config generation and service start/stop, also secures key generation */
    $fobj = new \OPNsense\Core\FileObject('/usr/local/etc/ssh/sshd_config', 'a+', null, LOCK_EX);

    mwexecf('service sshd stop');

    /* make sshd key store */
    @mkdir('/conf/sshd', 0777, true);

    /* make ssh home directory */
    @mkdir('/var/empty', 0555, true);

    /* Check for all needed key files. If any are missing, the keys need to be regenerated. */
    $generate_keys = false;
    foreach (openssh_host_key_types() as $type) {
        $file = openssh_host_key_path($type);
        if (!file_exists($file) || !file_exists("{$file}.pub")) {
            $generate_keys = true;
            break;
        }
    }

    if ($generate_keys) {
        $rsa_bits = isset($sshcfg['rsa_bits']) ? (int)$sshcfg['rsa_bits'] : null;
        openssh_regenerate_host_keys(openssh_host_key_types(), $rsa_bits);
    }

    $sshport = isset($sshcfg['port']) ? $sshcfg['port'] : 22;

    $sshconf = "# This file was automatically generated by /usr/local/etc/inc/plugins.inc.d/openssh.inc\n";
    $sshconf .= 'Include /usr/local/etc/ssh/sshd_config.d/*.conf' . PHP_EOL;
    $sshconf .= "Port {$sshport}\n";
    $sshconf .= "Protocol 2\n";
    $sshconf .= "Compression yes\n";
    $sshconf .= "ClientAliveInterval 30\n";
    $sshconf .= "UseDNS no\n";
    $sshconf .= "X11Forwarding no\n";
    $sshconf .= "PubkeyAuthentication yes\n";
    $sshconf .= "Subsystem sftp internal-sftp\n";
    /* Per-user access control is enforced via the SSH Management drop-in
     * (AllowUsers user@CIDR …) under sshd_config.d/. No global AllowGroups. */
    if (isset($sshcfg['permitrootlogin'])) {
        $sshconf .= "PermitRootLogin yes\n";
    } else {
        $sshconf .= "PermitRootLogin no\n";
    }
    if (isset($sshcfg['passwordauth'])) {
        $sshconf .= "ChallengeResponseAuthentication yes\n";
        $sshconf .= "PasswordAuthentication yes\n";
    } else {
        $sshconf .= "ChallengeResponseAuthentication no\n";
        $sshconf .= "PasswordAuthentication no\n";
    }
    if (!empty($sshcfg['rekeylimit'])) {
        $sshconf .= sprintf("RekeyLimit %s\n", $sshcfg['rekeylimit']);
    }
    if (!empty($sshcfg['loglevel'])) {
        $sshconf .= sprintf("LogLevel %s\n", $sshcfg['loglevel']);
    }

    foreach (openssh_host_key_types() as $type) {
        $file = openssh_host_key_path($type);
        if (!file_exists($file)) {
            continue;
        }
        $sshconf .= "HostKey {$file}\n";
    }

    $listeners = [];

    foreach (interfaces_addresses($interfaces) as $tmpaddr => $info) {
        if (!$info['bind']) {
            continue;
        }

        if (count($listeners) >= 16) {
            log_msg("The SSH listening address $tmpaddr cannot be added due to MAX_LISTEN_SOCKS limit reached.", LOG_WARNING);
            continue;
        }

        $listeners[] = $tmpaddr;
    }

    foreach ($listeners as $listener) {
        $sshconf .= "ListenAddress {$listener}\n";
    }

    $supported = null;
    $advanced = [
        [ 'config' => 'Ciphers', 'node' => 'ciphers', 'key' => 'cipher'],
        [ 'config' => 'HostKeyAlgorithms', 'node' => 'keys', 'key' => 'key'],
        [ 'config' => 'KexAlgorithms', 'node' => 'kex', 'key' => 'kex'],
        [ 'config' => 'MACs', 'node' => 'macs', 'key' => 'mac'],
        [ 'config' => 'PubkeyAcceptedAlgorithms', 'node' => 'keysig', 'key' => 'key-sig'],
    ];

    foreach ($advanced as $adv) {
        if (empty($sshcfg[$adv['node']])) {
            continue;
        }

        if ($supported === null) {
            /* cache return as it includes all probable values */
            $supported = json_decode(configd_run('openssh query'), true);
        }

        $selected = [];

        foreach (explode(',', $sshcfg[$adv['node']]) as $elem) {
            if (in_array($elem, $supported[$adv['key']])) {
                $selected[] = $elem;
            } else {
                log_msg("OpenSSH: Configured {$adv['node']} value '{$elem}' is not supported.", LOG_WARNING);
            }
        }

        if (count($selected) == 0) {
            log_msg("OpenSSH: No configured {$adv['node']} value is supported - using defaults.", LOG_WARNING);
        } else {
            $sshconf .= $adv['config'] . ' ' . implode(',', $selected) . PHP_EOL;
        }
    }

    $fobj->truncate(0)->write($sshconf);

    service_log('Configuring OpenSSH...', $verbose);

    if (count($interfaces) && !count($listeners)) {
        service_log("failed.\n", $verbose);
    } elseif (mwexecf('service sshd restart')) {
        service_log("failed.\n", $verbose);
    } else {
        service_log("done.\n", $verbose);
    }

    unset($fobj);
}
