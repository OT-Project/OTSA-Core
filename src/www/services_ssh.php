<?php

/*
 * Copyright (C) 2025 KC01.04-21.30 - OT Security Appliance
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

require_once("guiconfig.inc");
require_once("filter.inc");
require_once("system.inc");
require_once("plugins.inc.d/openssh.inc");

$ssh_rekeylimit_choices = [
    '' => gettext('System defaults'),
    'default 60s' => gettext('60 seconds'),
    'default 600s' => gettext('10 minutes'),
    '512M 60s' => gettext('512MB, 60 seconds'),
    '512M 600s' => gettext('512MB, 10 minutes'),
    '512M 1h' => gettext('512MB, 1 hour'),
    '1G 60s' => gettext('1GB, 60 seconds'),
    '1G 1h' => gettext('1GB, 1 hour'),
];

$ssh_loglevel_choices = [
    '' => gettext('Default (INFO)'),
    'QUIET' => gettext('QUIET - Minimal logging'),
    'FATAL' => gettext('FATAL - Fatal errors only'),
    'ERROR' => gettext('ERROR - Errors only'),
    'INFO' => gettext('INFO - Standard logging'),
    'VERBOSE' => gettext('VERBOSE - Session details (recommended for auditing)'),
];

$interfaces = get_configured_interface_with_descr();

if ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['action'] ?? '') === 'download_known_hosts') {
    $body = openssh_host_keys_known_hosts_block();
    $fname = ($config['system']['hostname'] ?? 'opnsense') . '-known_hosts.txt';

    header('Content-Type: text/plain; charset=utf-8');
    header('Content-Disposition: attachment; filename="' . $fname . '"');
    header('Content-Length: ' . strlen($body));
    echo $body;

    openlog('sshd_audit', LOG_PID, LOG_AUTH);
    syslog(LOG_NOTICE, sprintf(
        'host-keys export user=%s remote=%s format=known_hosts',
        $_SESSION['Username'] ?? 'unknown',
        $_SERVER['REMOTE_ADDR'] ?? '-'
    ));
    closelog();

    exit;
}

$regen_result = null;
$regen_request = ($_SERVER['REQUEST_METHOD'] === 'POST' && ($_POST['action'] ?? '') === 'regenerate_keys');

if ($regen_request) {
    $requested = (array)($_POST['key_types'] ?? []);
    $selected = array_values(array_intersect($requested, openssh_host_key_types()));

    openlog('sshd_audit', LOG_PID, LOG_AUTH);

    if (empty($selected)) {
        $regen_result = ['status' => 'noop', 'reason' => 'no_types_selected'];
        syslog(LOG_NOTICE, sprintf(
            'host-key regenerate user=%s remote=%s result=noop reason=no_types_selected',
            $_SESSION['Username'] ?? 'unknown',
            $_SERVER['REMOTE_ADDR'] ?? '-'
        ));
    } else {
        $rsa_bits_post = (int)($_POST['rsa_bits'] ?? 0);
        $rsa_bits = in_array($rsa_bits_post, openssh_rsa_bit_choices(), true)
            ? $rsa_bits_post
            : (isset($config['system']['ssh']['rsa_bits']) ? (int)$config['system']['ssh']['rsa_bits'] : null);

        /* 11776-bit RSA generation can take 5-30+ minutes; relax PHP limits. */
        @set_time_limit(0);
        @ignore_user_abort(true);

        $regen_result = openssh_regenerate_host_keys($selected, $rsa_bits);

        foreach ($regen_result as $type => $info) {
            syslog(LOG_NOTICE, sprintf(
                'host-key regenerate user=%s remote=%s type=%s bits=%s old_fp=%s new_fp=%s result=%s',
                $_SESSION['Username'] ?? 'unknown',
                $_SERVER['REMOTE_ADDR'] ?? '-',
                $type,
                $info['bits'] ?? '-',
                $info['old_fingerprint'] ?? '-',
                $info['new_fingerprint'] ?? '-',
                $info['status'] === 'ok' ? 'ok' : ('error:' . ($info['message'] ?? 'unknown'))
            ));
        }

        /* Reload sshd so the new keys take effect. Use the same path as the
         * Save handler below to stay consistent. */
        mwexec('pluginctl -s openssh restart');

        /* Persist the bit-length choice AFTER logging+restart so write_config()
         * cannot interfere with the still-open syslog connection. */
        if ($rsa_bits !== null && in_array('rsa', $selected, true)) {
            if (empty($config['system']['ssh'])) {
                $config['system']['ssh'] = [];
            }
            $config['system']['ssh']['rsa_bits'] = $rsa_bits;
            write_config('Updated SSH RSA host key length to ' . $rsa_bits . ' bits.');
        }
    }

    closelog();
}

if ($_SERVER['REQUEST_METHOD'] === 'GET' || $regen_request) {
    $pconfig = [];
    $pconfig['enablesshd'] = $config['system']['ssh']['enabled'] ?? null;
    $pconfig['sshport'] = $config['system']['ssh']['port'] ?? null;
    $pconfig['sshinterfaces'] = !empty($config['system']['ssh']['interfaces']) ? explode(',', $config['system']['ssh']['interfaces']) : [];
    $pconfig['ssh-kex'] = !empty($config['system']['ssh']['kex']) ? explode(',', $config['system']['ssh']['kex']) : [];
    $pconfig['ssh-ciphers'] = !empty($config['system']['ssh']['ciphers']) ? explode(',', $config['system']['ssh']['ciphers']) : [];
    $pconfig['ssh-macs'] = !empty($config['system']['ssh']['macs']) ? explode(',', $config['system']['ssh']['macs']) : [];
    $pconfig['ssh-keys'] = !empty($config['system']['ssh']['keys']) ? explode(',', $config['system']['ssh']['keys']) : [];
    $pconfig['ssh-keysig'] = !empty($config['system']['ssh']['keysig']) ? explode(',', $config['system']['ssh']['keysig']) : [];
    $pconfig['ssh-rekeylimit'] = !empty($config['system']['ssh']['rekeylimit']) ? $config['system']['ssh']['rekeylimit'] : '';
    $pconfig['ssh-loglevel'] = !empty($config['system']['ssh']['loglevel']) ? $config['system']['ssh']['loglevel'] : '';
    $pconfig['ssh-rsa-bits'] = !empty($config['system']['ssh']['rsa_bits']) ? (string)$config['system']['ssh']['rsa_bits'] : '4096';
    $pconfig['sshpasswordauth'] = isset($config['system']['ssh']['passwordauth']);
    $pconfig['sshdpermitrootlogin'] = isset($config['system']['ssh']['permitrootlogin']);
} elseif ($_SERVER['REQUEST_METHOD'] === 'POST' && !$regen_request) {
    $input_errors = [];
    $pconfig = $_POST;

    if (!empty($pconfig['sshport']) && !is_port($pconfig['sshport'])) {
        $input_errors[] = gettext('You must specify a valid SSH port number.');
    }

    if (!empty($pconfig['ssh-rekeylimit']) && !isset($ssh_rekeylimit_choices[$pconfig['ssh-rekeylimit']])) {
        $input_errors[] = gettext('Invalid rekey limit option.');
    }

    if (count($input_errors) == 0) {
        if (empty($config['system']['ssh'])) {
            $config['system']['ssh'] = [];
        }

        /* always store setting to prevent installer auto-start */
        $config['system']['ssh']['noauto'] = 1;

        $config['system']['ssh']['interfaces'] = !empty($pconfig['sshinterfaces']) ? implode(',', $pconfig['sshinterfaces']) : null;
        $config['system']['ssh']['kex'] = !empty($pconfig['ssh-kex']) ? implode(',', $pconfig['ssh-kex']) : null;
        $config['system']['ssh']['ciphers'] = !empty($pconfig['ssh-ciphers']) ? implode(',', $pconfig['ssh-ciphers']) : null;
        $config['system']['ssh']['macs'] = !empty($pconfig['ssh-macs']) ? implode(',', $pconfig['ssh-macs']) : null;
        $config['system']['ssh']['keys'] = !empty($pconfig['ssh-keys']) ? implode(',', $pconfig['ssh-keys']) : null;
        $config['system']['ssh']['keysig'] = !empty($pconfig['ssh-keysig']) ? implode(',', $pconfig['ssh-keysig']) : null;
        $config['system']['ssh']['rekeylimit'] = !empty($pconfig['ssh-rekeylimit']) ? $pconfig['ssh-rekeylimit'] : null;
        $config['system']['ssh']['loglevel'] = !empty($pconfig['ssh-loglevel']) ? $pconfig['ssh-loglevel'] : null;

        /* rsa_bits is owned by the Host keys form (iform_regen) — it is not part
         * of the main Save form, so this branch does not touch it. Persistence
         * happens in the regen branch above after a successful key generation. */

        if (!empty($pconfig['enablesshd'])) {
            $config['system']['ssh']['enabled'] = 'enabled';
        } elseif (isset($config['system']['ssh']['enabled'])) {
            unset($config['system']['ssh']['enabled']);
        }

        if (!empty($pconfig['sshpasswordauth'])) {
            $config['system']['ssh']['passwordauth'] = true;
        } elseif (isset($config['system']['ssh']['passwordauth'])) {
            unset($config['system']['ssh']['passwordauth']);
        }

        if (!empty($pconfig['sshport'])) {
            $config['system']['ssh']['port'] = $pconfig['sshport'];
        } elseif (isset($config['system']['ssh']['port'])) {
            unset($config['system']['ssh']['port']);
        }

        if (!empty($pconfig['sshdpermitrootlogin'])) {
            $config['system']['ssh']['permitrootlogin'] = true;
        } elseif (isset($config['system']['ssh']['permitrootlogin'])) {
            unset($config['system']['ssh']['permitrootlogin']);
        }

        write_config();

        $savemsg = get_std_save_message();

        filter_configure();
        system_login_configure();
        if (!empty($pconfig['enablesshd'])) {
            mwexec('pluginctl -s openssh restart');
        } else {
            mwexec('pluginctl -s openssh stop');
        }
    }
}

$sshoptions = json_decode(configd_run('openssh query'), true);

legacy_html_escape_form_data($pconfig);

include("head.inc");

?>
<body>
<script>
    $(document).ready(function() {
        $("#show-advanced-cryptocryptobtn").click(function (event) {
            event.preventDefault();
            $(this).parent().parent().hide();
            $(".show-advanced-crypto").show();
            $(window).trigger('resize');
        });
        // show advanced when at least one option is set
        $(".advanced-crypto").each(function () {
            if ($(this).val() != '') {
                $("#show-advanced-cryptocryptobtn").click();
            }
        });
    });
</script>
<?php include("fbegin.inc"); ?>
<section class="page-content-main">
  <div class="container-fluid">
    <div class="row">
<?php
    if (isset($input_errors) && count($input_errors) > 0) {
        print_input_errors($input_errors);
    }
    if (isset($savemsg)) {
        print_info_box($savemsg);
    }
    if (isset($regen_result)) {
        if (($regen_result['status'] ?? null) === 'noop') {
            print_info_box(gettext('No host key types were selected. Nothing was changed.'));
        } else {
            $lines = [];
            $had_error = false;
            foreach ($regen_result as $type => $info) {
                $type_label = strtoupper($type);
                if ($info['status'] === 'ok') {
                    $bits_part = '';
                    $old_bits = $info['old_bits'] ?? null;
                    $new_bits = $info['bits'] ?? null;
                    if ($new_bits !== null) {
                        if ($old_bits !== null && (int)$old_bits !== (int)$new_bits) {
                            $bits_part = sprintf(' (%d → %d bits)', $old_bits, $new_bits);
                        } else {
                            $bits_part = sprintf(' (%d bits)', $new_bits);
                        }
                    }
                    $lines[] = sprintf(
                        gettext('%s regenerated%s — new fingerprint: %s'),
                        $type_label,
                        $bits_part,
                        $info['new_fingerprint'] ?? '-'
                    );
                } else {
                    $had_error = true;
                    $lines[] = sprintf(
                        gettext('%s failed: %s'),
                        $type_label,
                        $info['message'] ?? gettext('unknown error')
                    );
                }
            }
            $msg = '<strong>' . gettext('SSH host keys regenerated. SSH service has been restarted.') . '</strong><br/>' .
                implode('<br/>', array_map('html_safe', $lines)) . '<br/><br/>' .
                '<em>' . gettext(
                    'Clients connecting via SSH will see a host-key mismatch warning ' .
                    'and must accept the new fingerprint above before connecting again.'
                ) . '</em>';
            print_alert_box($msg, $had_error ? 'danger' : 'warning');
        }
    }
?>
      <section class="col-xs-12">
        <form method="post" name="iform" id="iform">
          <div class="content-box tab-content table-responsive __mb">
            <table class="table table-striped opnsense_standard_table_form">
              <tr>
                <td style="width:22%"><strong><?= gettext('Secure Shell') ?></strong></td>
                <td style="width:78%; text-align:right">
                  <small><?=gettext("full help"); ?> </small>
                  <i class="fa fa-toggle-off text-danger" style="cursor: pointer;" id="show_all_help_page"></i>
                </td>
              </tr>
              <tr>
                <td><i class="fa fa-info-circle text-muted"></i> <?=gettext("Secure Shell Server"); ?></td>
                <td>
                  <input name="enablesshd" type="checkbox" value="yes" <?= empty($pconfig['enablesshd']) ? '' : 'checked="checked"' ?> />
                  <?=gettext("Enable Secure Shell"); ?>
                </td>
              </tr>
              <tr>
                <td><a id="help_for_sshdpermitrootlogin" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?= gettext("Root Login") ?></td>
                <td>
                  <input name="sshdpermitrootlogin" type="checkbox" value="yes" <?= empty($pconfig['sshdpermitrootlogin']) ? '' : 'checked="checked"' ?> />
                  <?=gettext("Permit root user login"); ?>
                  <div class="hidden" data-for="help_for_sshdpermitrootlogin">
                    <?= gettext(
                      'Root login is generally discouraged. It is advised ' .
                      'to log in via another user and switch to root afterwards.'
                    ) ?>
                  </div>
                </td>
              </tr>
              <tr>
                <td><a id="help_for_sshpasswordauth" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?= gettext("Authentication Method") ?></td>
                <td>
                  <input name="sshpasswordauth" type="checkbox" value="yes" <?= empty($pconfig['sshpasswordauth']) ? '' : 'checked="checked"' ?> />
                  <?=gettext("Permit password login"); ?>
                  <div class="hidden" data-for="help_for_sshpasswordauth">
                    <?= gettext('When disabled, authorized keys need to be configured for each user that has been granted secure shell access.') ?>
                  </div>
                </td>
              </tr>
              <tr>
                <td><a id="help_for_sshport" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?=gettext("SSH port"); ?></td>
                <td>
                  <input name="sshport" type="text" value="<?=$pconfig['sshport'];?>" placeholder="22" />
                  <div class="hidden" data-for="help_for_sshport">
                    <?=gettext("Leave this blank for the default of 22."); ?>
                  </div>
                </td>
              </tr>
              <tr>
                <td><a id="help_for_sshinterfaces" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?=gettext('Listen Interfaces') ?></td>
                <td>
                  <select name="sshinterfaces[]" multiple="multiple" class="selectpicker" title="<?= html_safe(gettext('All (recommended)')) ?>">
<?php foreach ($interfaces as $iface => $ifacename): ?>
                      <option value="<?= html_safe($iface) ?>" <?= !empty($pconfig['sshinterfaces']) && in_array($iface, $pconfig['sshinterfaces']) ? 'selected="selected"' : '' ?>><?= html_safe($ifacename) ?></option>
<?php endforeach ?>
                  </select>
                  <div class="hidden" data-for="help_for_sshinterfaces">
                    <?= gettext('Only accept connections from the selected interfaces. Leave empty to listen globally. Use with care.') ?>
                  </div>
                </td>
              </tr>
              <tr>
                <td><i class="fa fa-info-circle text-muted"></i> <?=gettext("Advanced");?></td>
                <td>
                  <button id="show-advanced-cryptocryptobtn" class="btn btn-xs btn-default" value="yes"><?= gettext('Show cryptographic overrides') ?></button>
                </td>
              </tr>
              <tr class="show-advanced-crypto" style="display:none">
                <td><a id="help_for_sshkex" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?=gettext("Key exchange algorithms"); ?></td>
                <td>
                    <select name="ssh-kex[]" class="selectpicker advanced-crypto" multiple="multiple" data-live-search="true" title="<?=gettext("System defaults");?>">
<?php foreach ($options = empty($sshoptions['kex']) ? [] : $sshoptions['kex'] as $option): ?>
                      <option value="<?=$option;?>" <?= !empty($pconfig['ssh-kex']) && in_array($option, $pconfig['ssh-kex']) ? 'selected="selected"' : '' ?>>
                        <?=$option;?>
                      </option>
<?php endforeach ?>
                    </select>
                    <div class="hidden" data-for="help_for_sshkex">
                      <?=gettext("The key exchange methods that are used to generate per-connection keys");?>
                    </div>
                </td>
              </tr>
              <tr class="show-advanced-crypto" style="display:none">
                <td><a id="help_for_sshciphers" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?=gettext("Ciphers"); ?></td>
                <td>
                    <select name="ssh-ciphers[]" class="selectpicker advanced-crypto" multiple="multiple" data-live-search="true" title="<?=gettext("System defaults");?>">
<?php foreach ($options = empty($sshoptions['cipher']) ? [] : $sshoptions['cipher'] as $option): ?>
                      <option value="<?=$option;?>" <?= !empty($pconfig['ssh-ciphers']) && in_array($option, $pconfig['ssh-ciphers']) ? 'selected="selected"' : '' ?>>
                        <?=$option;?>
                      </option>
<?php endforeach ?>
                    </select>
                    <div class="hidden" data-for="help_for_sshciphers">
                      <?=gettext("The ciphers to encrypt the connection");?>
                    </div>
                </td>
              </tr>
              <tr class="show-advanced-crypto" style="display:none">
                <td><a id="help_for_sshmacs" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?=gettext("MACs"); ?></td>
                <td>
                    <select name="ssh-macs[]" class="selectpicker advanced-crypto" multiple="multiple" data-live-search="true" title="<?=gettext("System defaults");?>">
<?php foreach ($options = empty($sshoptions['mac']) ? [] : $sshoptions['mac'] as $option): ?>
                      <option value="<?=$option;?>" <?= !empty($pconfig['ssh-macs']) && in_array($option, $pconfig['ssh-macs']) ? 'selected="selected"' : '' ?>>
                        <?=$option;?>
                      </option>
<?php
                    endforeach;?>
                    </select>
                    <div class="hidden" data-for="help_for_sshmacs">
                      <?=gettext("The message authentication codes used to detect traffic modification");?>
                    </div>
                </td>
              </tr>
              <tr class="show-advanced-crypto" style="display:none">
                <td><a id="help_for_sshkeys" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?=gettext("Host key algorithms"); ?></td>
                <td>
                    <select name="ssh-keys[]" class="selectpicker advanced-crypto" multiple="multiple" data-live-search="true" title="<?=gettext("System defaults");?>">
<?php foreach ($options = empty($sshoptions['key']) ? [] : $sshoptions['key'] as $option): ?>
                      <option value="<?=$option;?>" <?= !empty($pconfig['ssh-keys']) && in_array($option, $pconfig['ssh-keys']) ? 'selected="selected"' : '' ?>>
                        <?=$option;?>
                      </option>
<?php endforeach ?>
                    </select>
                    <div class="hidden" data-for="help_for_sshkeys">
                      <?= gettext('Specifies the host key algorithms that the server offers') ?>
                    </div>
                </td>
              </tr>
              <tr class="show-advanced-crypto" style="display:none">
                <td><a id="help_for_sshkeysig" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?=gettext("Public key signature algorithms"); ?></td>
                <td>
                    <select name="ssh-keysig[]" class="selectpicker advanced-crypto" multiple="multiple" data-live-search="true" title="<?=gettext("System defaults");?>">
<?php foreach ($options = empty($sshoptions['key-sig']) ? [] : $sshoptions['key-sig'] as $option): ?>
                      <option value="<?=$option;?>" <?= !empty($pconfig['ssh-keysig']) && in_array($option, $pconfig['ssh-keysig']) ? 'selected="selected"' : '' ?>>
                        <?=$option;?>
                      </option>
<?php endforeach ?>
                    </select>
                    <div class="hidden" data-for="help_for_sshkeysig">
                      <?=gettext("The signature algorithms that are used for public key authentication");?>
                    </div>
                </td>
              </tr>
              <tr class="show-advanced-crypto" style="display:none">
                <td><a id="help_for_sshrekeylimit" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?=gettext("Rekey Limit"); ?></td>
                <td>
                    <select name="ssh-rekeylimit" class="selectpicker advanced-crypto" data-live-search="true">
<?php foreach ($ssh_rekeylimit_choices as $option => $descr): ?>
                      <option value="<?=$option;?>" <?= $option == $pconfig['ssh-rekeylimit'] ? 'selected="selected"' : '' ?>>
                        <?=$descr;?>
                      </option>
<?php endforeach ?>
                    </select>
                    <div class="hidden" data-for="help_for_sshrekeylimit">
                      <?=gettext("Specifies the maximum amount of data that may be transmitted or received before the session key is renegotiated within a given time. The defaults depend on cipher and are usually the best option.");?>
                    </div>
                </td>
              </tr>
            </table>
          </div>
          <div class="content-box tab-content table-responsive __mb">
            <table class="table table-striped opnsense_standard_table_form">
              <tr>
                <td style="width:22%"><strong><?= gettext('Logging') ?></strong></td>
                <td style="width:78%; text-align:right">
                  <small><?=gettext("full help"); ?> </small>
                  <i class="fa fa-toggle-off text-danger" style="cursor: pointer;" id="show_all_help_page"></i>
                </td>
              </tr>
              <tr>
                <td><a id="help_for_sshloglevel" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?=gettext("Log Level"); ?></td>
                <td>
                    <select name="ssh-loglevel" class="selectpicker">
<?php foreach ($ssh_loglevel_choices as $option => $descr): ?>
                      <option value="<?=$option;?>" <?= $option == $pconfig['ssh-loglevel'] ? 'selected="selected"' : '' ?>>
                        <?=$descr;?>
                      </option>
<?php endforeach ?>
                    </select>
                    <div class="hidden" data-for="help_for_sshloglevel">
                      <?=gettext("Controls the verbosity of SSH logging. VERBOSE is recommended for auditing SSH session access, as it logs user logins, disconnections, key fingerprints, and session activity.");?>
                    </div>
                </td>
              </tr>
              <tr>
                <td><i class="fa fa-info-circle text-muted"></i> <?=gettext("View Log File"); ?></td>
                <td>
                  <a href="/ui/diagnostics/log/core/sshd" class="btn btn-default btn-xs">
                    <i class="fa fa-eye"></i> <?= gettext('Open SSH Log Viewer') ?>
                  </a>
                </td>
              </tr>
            </table>
          </div>
          <div class="content-box tab-content table-responsive">
            <table class="table table-striped opnsense_standard_table_form">
              <tr>
                <td style="width:22%"></td>
                <td style="width:78%"><input name="Submit" type="submit" class="btn btn-primary" value="<?= html_safe(gettext('Save')) ?>" /></td>
              </tr>
            </table>
          </div>
        </form>
        <form method="post" name="iform_regen" id="iform_regen">
          <input type="hidden" name="action" value="regenerate_keys" />
          <div class="content-box tab-content table-responsive __mb">
            <table class="table table-striped opnsense_standard_table_form">
              <tr>
                <td style="width:22%"><strong><?= gettext('Host keys') ?></strong></td>
                <td style="width:78%; text-align:right">
                  <small><?= gettext('full help') ?> </small>
                  <i class="fa fa-toggle-off text-danger" style="cursor: pointer;" id="show_all_help_page_hostkeys"></i>
                </td>
              </tr>
              <tr>
                <td colspan="2">
                  <table class="table table-condensed">
                    <thead>
                      <tr>
                        <th style="width:5%"></th>
                        <th style="width:10%"><?= gettext('Type') ?></th>
                        <th><?= gettext('Fingerprint (SHA256)') ?></th>
                        <th style="width:10%"><?= gettext('Bits') ?></th>
                        <th style="width:15%"><?= gettext('Public key') ?></th>
                      </tr>
                    </thead>
                    <tbody>
<?php foreach (openssh_host_key_types() as $type):
    $fp = openssh_host_key_fingerprint($type);
    $pub = openssh_host_key_public_text($type);
?>
                      <tr>
                        <td>
                          <input type="checkbox" name="key_types[]" value="<?= html_safe($type) ?>" id="regen_<?= html_safe($type) ?>" />
                        </td>
                        <td>
                          <label for="regen_<?= html_safe($type) ?>"><?= strtoupper($type) ?></label>
                        </td>
                        <td>
                          <?php if ($fp !== null): ?>
                            <code><?= html_safe($fp['sha256']) ?></code>
                          <?php else: ?>
                            <em class="text-muted"><?= gettext('not generated yet') ?></em>
                          <?php endif ?>
                        </td>
                        <td><?= $fp['bits'] ?? '-' ?></td>
                        <td>
                          <?php if ($pub !== null): ?>
                            <button type="button" class="btn btn-default btn-xs copy-pubkey"
                                    data-pubkey="<?= html_safe($pub) ?>"
                                    title="<?= html_safe(gettext('Copy public key to clipboard')) ?>">
                              <i class="fa fa-copy"></i> <?= gettext('Copy') ?>
                            </button>
                          <?php else: ?>
                            <em class="text-muted">—</em>
                          <?php endif ?>
                        </td>
                      </tr>
<?php endforeach ?>
                    </tbody>
                  </table>
                </td>
              </tr>
              <tr>
                <td><a id="help_for_rsa_bits" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?= gettext('RSA key length') ?></td>
                <td>
                  <?php $current_rsa_bits = openssh_host_key_fingerprint('rsa')['bits'] ?? null; ?>
                  <select name="rsa_bits" id="rsa_bits_select" class="selectpicker"
                          data-current-bits="<?= $current_rsa_bits ?? '' ?>">
<?php foreach (openssh_rsa_bit_choices() as $bits):
    $label = $bits . ' bits';
    if  ($bits === 3072) {
        $label .= ' (moderate security, faster)';
    } elseif  ($bits === 4096) {
        $label .= ' (' . gettext('default') . ')';
    } elseif ($bits === 11776) {
        $label .= ' (' . gettext('high assurance, slower') . ')';
    }
?>
                    <option value="<?= $bits ?>" <?= ($pconfig['ssh-rsa-bits'] ?? '4096') === (string)$bits ? 'selected="selected"' : '' ?>>
                      <?= html_safe($label) ?>
                    </option>
<?php endforeach ?>
                  </select>
                  <?php if ($current_rsa_bits !== null): ?>
                    <span class="text-muted" style="margin-left:8px;">
                      <?= sprintf(gettext('Current: %d bits'), $current_rsa_bits) ?>
                    </span>
                  <?php endif ?>
                  <div id="rsa_bits_change_warning" class="text-warning" style="display:none; margin-top:6px;">
                    <i class="fa fa-exclamation-triangle"></i>
                    <strong><?= gettext('Bit length sẽ chỉ áp dụng sau khi regenerate.') ?></strong>
                    <?= gettext('RSA đã được tự động chọn — bấm "Regenerate selected host keys" để sinh khóa mới với độ dài này.') ?>
                  </div>
                  <div class="hidden" data-for="help_for_rsa_bits">
                    <?= gettext('Áp dụng khi regenerate RSA host key (hoặc khi sshd tự sinh key lần đầu lúc boot). ECDSA và Ed25519 có độ dài cố định nên không bị ảnh hưởng.') ?>
                    <br/><?= gettext('Đổi giá trị ở đây KHÔNG tự áp dụng — vẫn phải bấm Regenerate để sinh khóa mới.') ?>
                    <br/><strong class="text-warning">⚠ <?= gettext('11776 bits có thể mất 5–30+ phút để sinh trên phần cứng OT thông thường; sshd sẽ bị tạm dừng trong suốt quá trình đó. Web request sẽ block đến khi xong, đừng đóng tab.') ?></strong>
                  </div>
                </td>
              </tr>
              <tr>
                <td><a id="help_for_regen_hostkeys" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?= gettext('Regenerate') ?></td>
                <td>
                  <button type="submit" id="regen_hostkeys_btn" class="btn btn-warning">
                    <i class="fa fa-refresh"></i> <?= gettext('Regenerate selected host keys') ?>
                  </button>
                  <div class="hidden" data-for="help_for_regen_hostkeys">
                    <strong class="text-danger"><?= gettext('Warning:') ?></strong>
                    <?= gettext(
                        'Regenerating host keys breaks the trust relationship with every existing SSH client. ' .
                        'On the next connection each client will see a host-key mismatch and must accept the new fingerprint shown above. ' .
                        'The SSH service is restarted immediately after regeneration; active sessions are not killed but new connections must use the new keys.'
                    ) ?>
                  </div>
                </td>
              </tr>
            </table>
          </div>
        </form>
        <form method="post" name="iform_export" id="iform_export">
          <input type="hidden" name="action" value="download_known_hosts" />
          <div class="content-box tab-content table-responsive __mb">
            <table class="table table-striped opnsense_standard_table_form">
              <tr>
                <td style="width:22%"><strong><?= gettext('Export for clients') ?></strong></td>
                <td style="width:78%; text-align:right">
                  <small><?= gettext('full help') ?> </small>
                  <i class="fa fa-toggle-off text-danger" style="cursor: pointer;" id="show_all_help_page_export"></i>
                </td>
              </tr>
              <tr>
                <td><a id="help_for_export_hostkeys" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> <?= gettext('Known_hosts file') ?></td>
                <td>
                  <button type="submit" class="btn btn-default">
                    <i class="fa fa-download"></i> <?= gettext('Download known_hosts entries') ?>
                  </button>
                  <div class="hidden" data-for="help_for_export_hostkeys">
                    <strong class="text-warning"><?= gettext('Cảnh báo TOFU (Trust On First Use):') ?></strong>
                    <?= gettext(
                        'Mặc định khi SSH client kết nối lần đầu, nó tự lưu host key của server vào known_hosts. ' .
                        'Nếu kết nối đầu tiên đó qua kênh đã bị MITM (Man-In-The-Middle), attacker key được trust ' .
                        'và mọi kiểm tra fingerprint sau đó đều vô nghĩa.'
                    ) ?>
                    <br/><br/>
                    <strong><?= gettext('Workflow khuyến cáo cho OT appliance:') ?></strong>
                    <ol>
                      <li><?= gettext('Tải file này về qua kênh đã xác thực (HTTPS GUI hiện tại + cert hợp lệ).') ?></li>
                      <li><?= gettext('Copy file tới máy admin qua kênh out-of-band (USB, ký số, in person).') ?></li>
                      <li><?= gettext('Append vào ~/.ssh/known_hosts của client trước khi SSH lần đầu.') ?></li>
                    </ol>
                    <?= gettext('File chứa entry cho cả 3 host key (RSA / ECDSA / Ed25519) với prefix là hostname + IP của LAN/WAN interface.') ?>
                  </div>
                </td>
              </tr>
            </table>
          </div>
        </form>
      </section>
    </div>
  </div>
</section>
<script>
$(document).ready(function() {
    $(document).on('click', '.copy-pubkey', function() {
        var pubkey = $(this).data('pubkey');
        var btn = $(this);
        if (!pubkey) return;
        var done = function() {
            var original = btn.html();
            btn.html('<i class="fa fa-check"></i> ' + <?= json_encode(gettext('Copied')) ?>);
            setTimeout(function() { btn.html(original); }, 1500);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(pubkey).then(done).catch(function() {
                /* Permission denied / non-secure context — fall back. */
                var ta = $('<textarea>').css({position: 'fixed', opacity: 0}).val(pubkey).appendTo('body');
                ta[0].select();
                try { document.execCommand('copy'); done(); } catch (e) {}
                ta.remove();
            });
        } else {
            var ta = $('<textarea>').css({position: 'fixed', opacity: 0}).val(pubkey).appendTo('body');
            ta[0].select();
            try { document.execCommand('copy'); done(); } catch (e) {}
            ta.remove();
        }
    });

    /* Highlight bit-length mismatch and auto-tick RSA when user changes the dropdown. */
    $('#rsa_bits_select').on('change', function() {
        var current = parseInt($(this).data('current-bits'), 10);
        var selected = parseInt($(this).val(), 10);
        if (current && selected && current !== selected) {
            $('#rsa_bits_change_warning').show();
            $('#regen_rsa').prop('checked', true);
        } else {
            $('#rsa_bits_change_warning').hide();
        }
    });

    $('#iform_regen').on('submit', function(event) {
        var checked = $(this).find('input[name="key_types[]"]:checked');
        if (checked.length === 0) {
            /* Allow submission so the server logs a noop audit entry and shows
             * a flash warning. No confirm prompt needed for a no-op. */
            return true;
        }
        var types = checked.map(function() { return this.value.toUpperCase(); }).get().join(', ');
        var extra = '';
        if ($.inArray('rsa', checked.map(function() { return this.value; }).get()) !== -1) {
            var current = parseInt($('#rsa_bits_select').data('current-bits'), 10);
            var selected = parseInt($('#rsa_bits_select').val(), 10);
            if (current && selected && current !== selected) {
                extra = '\n\n' + <?= json_encode(gettext('RSA bit length sẽ chuyển từ')) ?> +
                        ' ' + current + ' → ' + selected + ' bits.';
                if (selected >= 11776) {
                    extra += '\n' + <?= json_encode(gettext('⚠ Quá trình này có thể mất 5-30 phút và sshd sẽ tạm dừng.')) ?>;
                }
            } else if (selected) {
                extra = '\n\n' + <?= json_encode(gettext('RSA giữ nguyên độ dài')) ?> + ' ' + selected + ' bits.';
            }
        }
        var msg = <?= json_encode(gettext('Regenerate SSH host keys for')) ?> + ' ' + types + '?' + extra + '\n\n' +
                  <?= json_encode(gettext('Every existing SSH client will see a host-key mismatch on next connection. The SSH service will be restarted.')) ?>;
        if (!confirm(msg)) {
            event.preventDefault();
            return false;
        }
        return true;
    });
});
</script>
<?php include("foot.inc"); ?>
