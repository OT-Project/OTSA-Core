{#
 # Copyright (c) 2015-2025 Franco Fichtner <franco@opnsense.org>
 # Copyright (c) 2015-2018 Deciso B.V.
 # All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without modification,
 # are permitted provided that the following conditions are met:
 #
 # 1.  Redistributions of source code must retain the above copyright notice,
 # this list of conditions and the following disclaimer.
 #
 # 2.  Redistributions in binary form must reproduce the above copyright notice,
 # this list of conditions and the following disclaimer in the documentation
 # and/or other materials provided with the distribution.
 #
 # THIS SOFTWARE IS PROVIDED "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES,
 # INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 # AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 # AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 # OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 # SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 # INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 # CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 # ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 # POSSIBILITY OF SUCH DAMAGE.
 #}

<style>
    /* "dropdown in responsive table" issue workaround: display dummy road so dropdowns fits the table */
    @media screen and (max-width: 767px) {
        .dropdown_helper {
            display: block !important;
        }
    }
    .dropdown_helper {
        display: none;
    }
    /* OTSA: hide technical controls — audit dropdown, major-upgrade button, plugin conflict resolver.
       !important is required because JS calls .show() on these elements after loadInfo. */
    #audit_actions,
    #upgrade_maj,
    #plugin_actions {
        display: none !important;
    }
    /* OTSA: hide the output console and package list table in the Updates tab — replaced with a friendlier card. */
    #updates #updatelist,
    #updates #update_status_container {
        display: none !important;
    }
    #otsa_update_view {
        padding: 40px 20px;
        text-align: center;
        min-height: 240px;
    }
    #otsa_update_view .fa-3x {
        margin-bottom: 15px;
    }
</style>

<script>

    function generic_search(that, entries) {
        let search = $(that).val().toLowerCase();
        $('.' + entries).each(function () {
            let row_by_col = $(this).find('td').map(function () {
                return $(this).text();
            }).get();
            let name = row_by_col.join(',').toLowerCase();
            if (entries == 'plugin_entry' && !$(this).hasClass('filter_sup_inst') && !$("#plugin_show_community").is(':checked')) {
                $(this).hide();
            } else if (search.length != 0 && name.indexOf(search) == -1) {
                $(this).hide();
            } else {
                $(this).show();
            }
        });
    }

    function cancel_update() {
        $('#updatelist').hide();
        $('#update_status_container').show();
    }

    /**
     * retrieve update status from backend
     */
    function updateStatus() {
        $('#upgrade_maj').hide();
        $('#upgrade').hide();

        ajaxGet('/api/core/firmware/status', {}, function (data, status){
            if (data['status'] == "update") {
                let show_log = '';

                $.status_reboot = data['status_reboot'];

                // show upgrade list
                $('#upgrade').show();
                $('#updatestatus').html(data['status_msg']);
                $('#updatelist > tbody').empty();
                $('#updatetab > a').tab('show');
                $.each(data['all_packages'], function (index, row) {
                    $('#updatelist > tbody').append('<tr><td>'+row['name']+'</td>' +
                    '<td>'+row['old']+'</td><td>'+row['new']+'</td><td>' +
                    row['reason']+'</td><td>'+row['repository'] + '</td></tr>');

                    if (row['name'] == data['product_target'] && row['new'] != 'N/A') {
                        show_log = row['new'].replace(/[_-].*/, '');
                    }
                });
                $('#update_status_container').hide();
                $('#updatelist').show();

                // display the current changelog if one was found
                if (show_log != '') {
                    changelog(show_log);
                }

                packagesInfo(false);
            } else if (data['status'] == "upgrade") {
                $.status_reboot = data['status_reboot'];

                if (data['upgrade_major_message'] != '') {
                    /* we trust this data, it was signed by us and secured by csrf */
                    stdDialogInform(
                        '{{ lang._('Upgrade instructions') }}',
                        htmlDecode(data['upgrade_major_message']),
                        "{{ lang._('OK') }}",
                        function () { show_upgrade(data) },
                        'warning'
                    );
                } else {
                    show_upgrade(data);
                }

                packagesInfo(false);
            } else if (data['status'] == "error") {
                stdDialogInform('{{ lang._('Firmware status') }}', data['status_msg'], "{{ lang._('Close') }}", undefined, 'danger');
                packagesInfo(true);
            } else if (data['status'] == "none") {
                stdDialogInform('{{ lang._('Firmware status') }}', data['status_msg'], "{{ lang._('Close') }}", undefined, 'success');
                packagesInfo(true);
            } else {
                // in case new responses are added
                console.log('Unknown check response');
                console.log(data);
            }
        });
    }

    /**
     * perform backend action and install poller to update status
     */
    function backend(type) {
        $.upgrade_check = type == 'check';

        $('#update_status').html('');
        $('#updatelist').hide();
        $('#update_status_container').show();
        $('#updatetab > a').tab('show');
        $('#updatetab_progress').addClass("fa fa-spinner fa-pulse");

        ajaxCall('/api/core/firmware/' + type, {}, function () {
            setTimeout(trackStatus, 500);
        });
    }

    /**
     * read package details from backend
     */
    function details(package)
    {
        ajaxCall('/api/core/firmware/details/' + package, {}, function (data, status) {
            var details = "{{ lang._('Sorry, plugin details are currently not available.') }}";
            if (data['details'] != undefined) {
                details = data['details'];
            }
            stdDialogInform("{{ lang._('Plugin details') }}", details, "{{ lang._('Close') }}");
        });
    }

    /**
     * read license from backend
     */
    function license(package)
    {
        ajaxCall('/api/core/firmware/license/' + package, {}, function (data, status) {
            var license = "{{ lang._('Sorry, the package does not have an associated license file.') }}";
            if (data['license'] != undefined) {
                license = data['license'];
            }
            stdDialogInform("{{ lang._('License details') }}", license, "{{ lang._('Close') }}");
        });
    }

    /**
     * read changelog from backend
     */
    function changelog(version)
    {
        ajaxCall('/api/core/firmware/changelog/' + version, {}, function (data, status) {
            if (data['html'] != undefined) {
                header = data['version'];
                if (data['date'] != '') {
                    header += ' (' + data['date'] + ')';
                }
                /* we trust this data, it was signed by us and secured by csrf */
                stdDialogInform(header, htmlDecode(data['html']), "{{ lang._('Close') }}", undefined, 'primary');
            }
        });
    }

    /**
     * perform package action that requires reboot confirmation
     */
    function action_may_reboot(pkg_act, pkg_name)
    {
        if (pkg_act == 'reinstall' && (pkg_name == 'kernel' || pkg_name == 'base')) {
            // reboot required, inform the user.
            BootstrapDialog.show({
                type:BootstrapDialog.TYPE_WARNING,
                title: "{{ lang._('Reboot required') }}",
                message: "{{ lang._('The firewall will reboot directly after this set reinstall.') }}",
                buttons: [{
                    label: "{{ lang._('OK') }}",
                    cssClass: 'btn-warning',
                    action: function(dialogRef){
                        dialogRef.close();
                        backend(pkg_act + "/" + pkg_name);
                    }
                },{
                    label: "{{ lang._('Cancel') }}",
                    action: function(dialogRef){
                        dialogRef.close();
                    }
                }]
            });
        } else {
            backend(pkg_act + "/" + pkg_name);
        }
    }

    function show_upgrade(data) {
        $('#upgrade_maj').show();
        $('#updatestatus').html(data['status_msg']);
        $('#updatelist > tbody').empty();
        $('#updatetab > a').tab('show');
        $.each(data['all_sets'], function (index, row) {
            $('#updatelist > tbody').append('<tr><td>'+row['name']+'</td>' +
            '<td>'+row['old']+'</td><td>'+row['new']+'</td><td>' +
            row['reason']+'</td><td>'+row['repository'] + '</td></tr>');
        });
        $('#update_status_container').hide();
        $('#updatelist').show();
        changelog(data['upgrade_major_version']);
    }

    /**
     *  check if a reboot is required, warn user or just upgrade
     */
    function upgrade_ui(major)
    {
        if (major !== true && $.status_reboot != "1") {
            backend('update');
        } else {
            let reboot_msg = "{{ lang._('The firewall will reboot directly after this firmware update.') }}";
            if (major === true) {
                reboot_msg = "{{ lang._('The firewall will download all firmware sets and reboot multiple times for this upgrade. All operating system files and packages will be reinstalled as a consequence. This may take several minutes to complete.') }}";
            }
            // reboot required, inform the user.
            BootstrapDialog.show({
                type:BootstrapDialog.TYPE_WARNING,
                title: "{{ lang._('Reboot required') }}",
                message: reboot_msg,
                buttons: [{
                    label: "{{ lang._('OK') }}",
                    cssClass: 'btn-warning',
                    action: function(dialogRef){
                        dialogRef.close();
                        backend(major === true ? 'upgrade' : 'update');
                    }
                },{
                    label: "{{ lang._('Cancel') }}",
                    action: function(dialogRef){
                        dialogRef.close();
                    }
                }]
            });
        }
    }

    function rebootWait() {
        $.ajax({
            url: '/',
            timeout: 2500
        }).fail(function () {
            setTimeout(rebootWait, 2500);
        }).done(function () {
            $(location).attr('href', '/');
        });
    }

    function trackStatus() {
        ajaxGet('/api/core/firmware/upgradestatus', { v: Date.now() }, function(data, status) {
            if (status != 'success') {
                // recover from temporary errors
                setTimeout(trackStatus, 1000);
                return;
            }
            if (data['log'] != undefined && data['log'] != '') {
                var autoscroll = $('#update_status')[0].scrollTop +
                    $('#update_status')[0].clientHeight ===
                    $('#update_status')[0].scrollHeight;
                $('#update_status').html(data['log']);
                if (autoscroll) {
                    $('#update_status').scrollTop($('#update_status')[0].scrollHeight);
                }
            }
            if (data['status'] == 'done') {
                $('#updatetab_progress').removeClass("fa fa-spinner fa-pulse");
                if ($.upgrade_check === true) {
                    updateStatus();
                } else {
                    packagesInfo(true);
                }
            } else if (data['status'] == 'reboot') {
                BootstrapDialog.show({
                    type:BootstrapDialog.TYPE_INFO,
                    title: "{{ lang._('Your system is rebooting') }}",
                    closable: false,
                    message: "{{ lang._('The upgrade has finished and the system is being rebooted at the moment, please wait...') }}" +
                        ' <i class="fa fa-cog fa-spin"></i>',
                    onshow: function (dialogRef) {
                        setTimeout(rebootWait, 45000);
                    },
                });
            } else {
                // schedule next poll
                setTimeout(trackStatus, 500);
            }
        });
    }

    /**
     * show package info
     */
    function packagesInfo(reset) {
        $("#statustab_progress").addClass("fa fa-spinner fa-pulse");
        ajaxGet('/api/core/firmware/info', {}, function (data, status) {
            $('#packageslist > tbody').empty();
            $('#pluginlist > tbody').empty();
            var installed = {};

            $.each(data['product'], function(key, value) {
                if (key == 'product_check') {
                    if (value != null) {
                        $('#product_time_check').text(value['last_check']);
                    } else {
                        $('#product_time_check').text("{{ lang._('N/A') }}");
                    }
                } else {
                    $('#' + key).text(value);
                }
            });

            if (data['product']['product_license'] != undefined) {
                $.each(data['product']['product_license'], function(key, value) {
                    $('#product_license_' + key).text(value).closest('tr').show();
                });
                if (!Object.keys(data['product']['product_license']).length) {
                    $('[id^=product_license_]').closest('tr').hide();
                }
            }

            $("#statustab_progress").removeClass("fa fa-spinner fa-pulse");

            if (reset === true) {
                ajaxGet('/api/core/firmware/upgradestatus', { v: Date.now() }, function(data, status) {
                    if (data['log'] != undefined && data['log'] != '') {
                        $('#update_status').html(data['log']);
                    } else {
                        $('#update_status').html('{{ lang._('No previous action log found.') }}');
                    }
                    $('#update_status').scrollTop($('#update_status')[0].scrollHeight);
                });

                $('#updatelist').hide();
                $('#update_status_container').show();
            }

            var local_count = 0;
            var plugin_count = 0;
            var misconfigured_plugins = 0;
            var missing_plugins = 0;
            var changelog_count = 0;
            var changelog_max = 15;
            if ($.changelog_keep_full != undefined) {
                changelog_max = 9999;
            }

            $.each(data['package'], function(index, row) {
                if (row['installed'] == "1") {
                    local_count += 1;
                } else {
                    return 1;
                }
                $('#packageslist > tbody').append(
                    '<tr class="package_entry">' +
                    '<td>' + row['name'] + '</td>' +
                    '<td>' + row['version'] + '</td>' +
                    '<td>' + row['flatsize'] + '</td>' +
                    '<td>' + row['repository'] + '</td>' +
                    '<td>' + row['license'] + '</td>' +
                    '<td>' + row['comment'] + '</td>' +
                    '<td style="white-space:nowrap;vertical-align:middle;"><div class="input-group">' +
                    '<button class="btn btn-default btn-xs act_license" data-package="' + row['name'] + '" ' +
                    '  data-toggle="tooltip" title="{{ lang._('License') }}">' +
                    '<i class="fa fa-balance-scale fa-fw"></i></button> ' +
                    '<button class="btn btn-default btn-xs act_reinstall" data-package="' + row['name'] + '" ' +
                    '  data-toggle="tooltip" title="{{ lang._('Reinstall') }}">' +
                    '<i class="fa fa-recycle fa-fw"></i></button> ' + (row['locked'] === '1' ?
                        '<button data-toggle="tooltip" title="{{ lang._('Unlock') }}" class="btn btn-default btn-xs act_unlock" data-package="' + row['name'] + '">' +
                        '<i class="fa fa-lock fa-fw">' +
                        '</i></button>' :
                        '<button class="btn btn-default btn-xs act_lock" data-package="' + row['name'] + '" ' +
                        '  data-toggle="tooltip" title="{{ lang._('Lock') }}" >' +
                        '<i class="fa fa-unlock fa-fw"></i></button>'
                    ) + '</div></td>' +
                    '</tr>'
                );
            });

            if (local_count == 0) {
                $('#packageslist > tbody').append(
                    '<tr><td colspan=6>{{ lang._('No packages were found on your system. Please call for help.') }}</td></tr>'
                );
            }

            $.each(data['plugin'], function(index, row) {
                if (row['provided'] == "1") {
                    plugin_count += 1;
                }
                let status_text = '';
                let bold_on = '';
                let bold_off = '';
                if (row['installed'] == "1" && row['configured'] == "0") {
                    status_text = ' ({{ lang._('misconfigured') }})';
                    bold_on = '<b>';
                    bold_off = '</b>';
                    misconfigured_plugins = 1;
                } else if (row['installed'] == "0" && row['configured'] == "1") {
                    status_text = ' ({{ lang._('missing') }})';
                    bold_on = '<span class="text-danger"><b>';
                    bold_off = '</b></span>';
                    missing_plugins = 1;
                } else if (row['installed'] == "1") {
                    if (row['provided'] == "0") {
                        status_text = ' ({{ lang._('orphaned') }})';
                    } else {
                        status_text = ' ({{ lang._('installed') }})';
                    }
                    bold_on = '<b>';
                    bold_off = '</b>';
                }
                let cls_filter_sup_inst = '';
                if (['1', '2'].includes(row['tier']) || row['installed'] == '1' || row['configured'] == "1") {
                    cls_filter_sup_inst = 'filter_sup_inst'; // supported [tier 1,2] or (should be) installed
                }
                $('#pluginlist > tbody').append(
                    '<tr class="plugin_entry '+cls_filter_sup_inst+'">' +
                    '<td>' + bold_on + row['name'] + status_text + bold_off + '</td>' +
                    '<td>' + bold_on + row['version'] + bold_off + '</td>' +
                    '<td>' + bold_on + row['flatsize'] + bold_off + '</td>' +
                    '<td>' + bold_on + row['tier'] + bold_off + '</td>' +
                    '<td>' + bold_on + row['repository'] + bold_off + '</td>' +
                    '<td>' + bold_on + row['comment'] + bold_off + '</td>' +
                    '<td style="white-space:nowrap;vertical-align:middle;"><div class="input-group">' +
                    '<button class="btn btn-default btn-xs act_details" data-package="' + row['name'] + '" ' +
                        ' data-toggle="tooltip" title="{{ lang._('Info') }}">' +
                        '<i class="fa fa-info-circle fa-fw"></i></button>' +
                        (row['installed'] == "1" ?
                        '<button class="btn btn-default btn-xs act_remove" data-package="' + row['name'] + '" '+
                        '  data-toggle="tooltip" title="{{ lang._('Remove') }}">' +
                        '<i class="fa fa-trash fa-fw">' +
                        '</i></button>' :
                        '<button class="btn btn-default btn-xs act_install" data-package="' + row['name'] + '" ' +
                        'data-repository="'+row['repository']+'" data-toggle="tooltip" title="{{ lang._('Install') }}">' +
                        '<i class="fa fa-plus fa-fw">' +
                        '</i></button>'
                    ) + '</div></td>' + '</tr>'
                );
            });

            if (plugin_count == 0) {
                $('#pluginlist > tbody').append(
                    '<tr><td colspan=5>{{ lang._('Check for updates to view available plugins.') }}</td></tr>'
                );
            }

            if (data['product']['product_log']) {
                $('#audit_upgrade').parent().show();
            } else {
                $('#audit_upgrade').parent().hide();
            }
            $('#audit_actions').show();
            $("#plugin_search").keyup();
            $("#package_search").keyup();

            if (misconfigured_plugins || missing_plugins) {
                if (!missing_plugins) {
                    $("#plugin_get").parent().hide();
                } else {
                    $("#plugin_get").parent().show();
                }
                $('#plugin_actions').show();
            } else {
                $('#plugin_actions').hide();
            }
            $("#plugin_show_community").change();

            $("#changeloglist > tbody").empty();
            $("#changeloglist > thead").html("<tr><th>{{ lang._('Version') }}</th>" +
            "<th>{{ lang._('Date') }}</th><th></th></tr>");

            const installed_version = data['product_version'].replace(/[_-].*/, '');

            $.each(data['changelog'], function(index, row) {
                changelog_count += 1;

                let status_text = '';
                let bold_on = '';
                let bold_off = '';

                if (installed_version == row['version']) {
                    status_text = ' ({{ lang._('installed') }})';
                    bold_on = '<b>';
                    bold_off = '</b>';
                }

                $('#changeloglist > tbody').append(
                    '<tr' + (changelog_count > changelog_max ? ' class="changelog-hidden" style="display: none;" ' : '' ) +
                    '><td>' + bold_on + row['version'] + status_text + bold_off + '</td><td>' + bold_on + row['date'] + bold_off + '</td>' +
                    '<td><button class="btn btn-default btn-xs act_changelog" data-version="' + row['version'] + '" ' +
                    'data-toggle="tooltip" title="{{ lang._('View') }}">' +
                    '<i class="fa fa-book fa-fw"></i></button></td></tr>'
                );
            });

            if (!data['changelog'].length) {
                $('#changeloglist > tbody').append(
                    '<tr><td colspan=3>{{ lang._('Check for updates to view changelog history.') }}</td></tr>'
                );
            }

            if (changelog_count > changelog_max) {
                $('#changeloglist > tbody').append(
                    '<tr class= "changelog-full"><td colspan=3><a id="changelog-act" href="#">{{ lang._('Click to view full changelog history.') }}</a></td></tr>'
                );
                $("#changelog-act").click(function(event) {
                    event.preventDefault();
                    $(".changelog-hidden").attr('style', '');
                    $(".changelog-full").attr('style', 'display: none;');
                    $.changelog_keep_full = 1;
                });
            }

            // link buttons to actions
            $(".act_reinstall").click(function(event) {
                event.preventDefault();
                action_may_reboot('reinstall', $(this).data('package'));
            });
            $(".act_unlock").click(function(event) {
                event.preventDefault();
                backend('unlock/' + $(this).data('package'));
            });
            $(".act_lock").click(function(event) {
                event.preventDefault();
                backend('lock/' + $(this).data('package'));
            });
            $(".act_remove").click(function(event) {
                event.preventDefault();
                let plugin_name = $(this).data('package');
                BootstrapDialog.show({
                    type:BootstrapDialog.TYPE_WARNING,
                    title: "{{ lang._('Confirm removal') }}",
                    message: "{{ lang._('Do you really want to remove this plugin?') }}" + " <strong>" + plugin_name + "</strong>",
                    buttons: [{
                        label: "{{ lang._('OK') }}",
                        cssClass: 'btn-warning',
                        action: function (dialogRef) {
                            dialogRef.close();
                            backend('remove/' + plugin_name);
                        }
                    },{
                        label: "{{ lang._('Cancel') }}",
                        action: function(dialogRef){
                            dialogRef.close();
                        }
                    }]
                });
            });
            $(".act_details").click(function(event) {
                event.preventDefault();
                details($(this).data('package'));
            });
            $(".act_install").click(function(event) {
                event.preventDefault();
                let package_name = $(this).data('package');
                /* XXX temporary placeholder to inform the user that he/she is installing from a different (external) source */
                if ($(this).data('repository') !== 'OPNsense') {
                    BootstrapDialog.show({
                        type:BootstrapDialog.TYPE_INFO,
                        title: "{{ lang._('Third party software') }}",
                        message: "{{ lang._('This software package is provided by an external vendor, for more information contact the author')}}",
                        buttons: [{
                            label: "{{ lang._('Install') }}",
                            action: function(dialogRef){
                                dialogRef.close();
                                backend('install/' + package_name);
                            }
                        }, {
                            label: "{{ lang._('Cancel') }}",
                            action: function(dialogRef){
                                dialogRef.close();
                            }
                        }]
                    });
                } else {
                    backend('install/' + package_name);
                }
            });
            $(".act_changelog").click(function(event) {
                event.preventDefault();
                changelog($(this).data('version'));
            });
            $(".act_license").click(function(event) {
                event.preventDefault();
                license($(this).data('package'));
            });
            // attach tooltip to generated buttons
            $('[data-toggle="tooltip"]').tooltip();
        });
    }

    $( document ).ready(function() {
        // link event handlers
        $('#checkupdate').click(function () { backend('check'); });
        $('#upgrade').click(function () { upgrade_ui(false); });
        $('#upgrade_maj').click(function () { upgrade_ui(true); });
        $('#upgrade_cancel').click(cancel_update);
        $("#plugin_see").click(function () { $('#plugintab > a').tab('show'); });
        $("#plugin_get").click(function () { backend('syncPlugins'); });
        $("#plugin_set").click(function () { backend('resyncPlugins'); });
        $('#audit_cleanup').click(function () { backend('cleanup'); });
        $('#audit_connection').click(function () { backend('connection'); });
        $('#audit_health').click(function () { backend('health'); });
        $('#audit_security').click(function () { backend('audit'); });
        $('#audit_upgrade').click(function () {
            ajaxCall('/api/core/firmware/log/0', {}, function (data, status) {
                if (data['log'] != undefined) {
                    stdDialogConfirm("{{ lang._('Upgrade log') }}", data['log'],
                      "{{ lang._('Clear') }}", "{{ lang._('Close') }}", function () {
                        ajaxCall('/api/core/firmware/log/1');
                        $('#audit_upgrade').parent().hide();
                      }, 'primary');
                }
            });
        });

        // populate package information
        packagesInfo(true);

        $("#plugin_search").keyup(function () { generic_search(this, 'plugin_entry'); });
        $("#package_search").keyup(function () { generic_search(this, 'package_entry'); });
        $("#plugin_show_community").change(function(){ $("#plugin_search").keyup();})

        ajaxGet('/api/core/firmware/running', {}, function(data, status) {
            if (data['status'] == 'busy') {
                // if action is already running reattach now...
                backend('audit');
            } else if (window.location.hash == '#checkupdate') {
                // dashboard link: run check automatically after delay
                setTimeout(function () {
                    ajaxGet('/api/core/firmware/running', {}, function(data, status) {
                        if (data['status'] != 'busy') {
                            backend('check');
                        }
                    });
                }, 2000);
            }
        });

        // handle firmware config options
        function fillOptions() {
            ajaxGet('/api/core/firmware/get_options', {}, function(firmwareoptions, status) {
                ajaxGet('/api/core/firmware/get', {}, function(config, status) {
                    var firmwareconfig = config['firmware'];
                    var custom_selected = true;

                    $("#firmware_mirror").find('option').remove();
                    $("#firmware_type").find('option').remove();
                    $("#firmware_flavour").find('option').remove();
                    $("#firmware_reboot").prop('checked', firmwareconfig['reboot'] == '1');

                    $.each(firmwareoptions.mirrors, function(key, value) {
                        var selected = false;
                        if (key == firmwareconfig['mirror']) {
                            selected = true;
                            custom_selected = false;
                        }
                        $("#firmware_mirror").append($("<option/>")
                                .attr("value",key)
                                .text(value)
                                .prop('selected', selected)
                        );
                    });
                    if (firmwareoptions['mirrors_allow_custom']) {
                        $("#firmware_mirror :first-child").after($("<option/>")
                            .attr("value", firmwareconfig['mirror'])
                            .text("(custom)")
                            .attr("data-custom", "1")
                            .prop('selected', custom_selected)
                        );
                    }

                    $("#firmware_subscription").val(firmwareconfig['subscription']);

                    $("#firmware_mirror").selectpicker('refresh');
                    $("#firmware_mirror").change();

                    custom_selected = true;
                    $.each(firmwareoptions.flavours, function(key, value) {
                        var selected = false;
                        if (key == firmwareconfig['flavour']) {
                            selected = true;
                            custom_selected = false;
                        }
                        $("#firmware_flavour").append($("<option/>")
                                .attr("value",key)
                                .text(value)
                                .prop('selected', selected)
                        );
                    });
                    if (firmwareoptions['flavours_allow_custom']) {
                        $("#firmware_flavour :first-child").after($("<option/>")
                            .attr("value", firmwareconfig['flavour'])
                            .text("(custom)")
                            .attr("data-custom", "1")
                            .prop('selected', custom_selected)
                        );
                    }
                    $("#firmware_flavour").selectpicker('refresh');
                    $("#firmware_flavour").change();
                    if (firmwareconfig['flavour'] !== '' || firmwareconfig['reboot'] !== '') {
                        $("i.fa-toggle-off#show_advanced_firmware").click();
                    }

                    $.each(firmwareoptions.families, function(key, value) {
                        var selected = false;
                        if (key == firmwareconfig['type']) {
                            selected = true;
                        }
                        $("#firmware_type").append($("<option/>")
                                .attr("value",key)
                                .text(value)
                                .prop('selected', selected)
                        );
                    });
                    $("#firmware_type").selectpicker('refresh');
                    $("#firmware_type").change();
                });
            });
        }
        fillOptions();
        $("#reset_mirror").click(fillOptions);

        // Resolve the URL that the Test/Save buttons should act on.
        //
        // Source of truth depends on which option is selected:
        //  - preset mirror  -> use the <option value="..."> directly (always
        //    correct, immune to stale input or selectpicker init races)
        //  - (custom)       -> use what the operator typed into the input
        function selectedMirrorUrl() {
            var $opt = $("#firmware_mirror").find('option:selected');
            if (!$opt.length) {
                return $("#firmware_mirror_value").val() || '';
            }
            if ($opt.attr('data-custom') === "1") {
                return $("#firmware_mirror_value").val() || '';
            }
            return $opt.attr('value') || '';
        }

        // Keep the visible URL input in sync with the dropdown selection.
        // For presets the input is just a read-only display of the URL; for
        // (custom) the input is the editable buffer and must not be overwritten
        // on every change of unrelated state.
        function refreshMirrorInput() {
            var $opt = $("#firmware_mirror").find('option:selected');
            var isCustom = $opt.length && $opt.attr('data-custom') === "1";
            if (isCustom) {
                // Restore the saved custom URL the first time custom becomes
                // selected; afterwards leave whatever the operator typed.
                if (!$("#firmware_mirror_value").val()) {
                    $("#firmware_mirror_value").val($opt.attr('value') || '');
                }
            } else {
                $("#firmware_mirror_value").val($opt.length ? ($opt.attr('value') || '') : '');
            }
            $("#firmware_mirror_value").prop('readonly', !isCustom);
        }
        $("#firmware_mirror").change(refreshMirrorInput);

        // When operator edits the URL while (custom) is selected, mirror the
        // edit into the option's value attribute so the underlying <select>
        // and any consumers (selectpicker, Save POST) stay consistent.
        $("#firmware_mirror_value").on('input', function() {
            var $opt = $("#firmware_mirror").find('option:selected');
            if ($opt.length && $opt.attr('data-custom') === "1") {
                $opt.attr('value', $(this).val());
            }
        });
        $("#firmware_flavour").change(function() {
            $("#firmware_flavour_value").val($(this).val());
            if ($(this).find(':selected').data("custom") == 1) {
                $("#firmware_flavour_custom").show();
            } else {
                $("#firmware_flavour_custom").hide();
            }
        });

        $("#test_mirror").click(function() {
            // Always derive URL from the dropdown selection (or operator input
            // for custom). This bypasses any stale state in the visible input
            // caused by selectpicker init races or partial change events.
            // Normalise to the documented convention (root URL, no trailing
            // slash) before checking. Keep this in sync with the server-side
            // rtrim in FirmwareController::testMirrorAction().
            var url = (selectedMirrorUrl() || '').replace(/\/+$/, '');
            $("#firmware_mirror_value").val(url);
            var $btn = $(this);
            var $result = $("#test_mirror_result");
            var $icon = $("#test_mirror_icon");

            $result.removeClass("text-success text-danger").text("");
            if (!url || !/^https?:\/\//.test(url)) {
                $result.addClass("text-danger").text("{{ lang._('Invalid URL') }}");
                return;
            }

            $btn.prop("disabled", true);
            $icon.removeClass("fa-plug").addClass("fa-spinner fa-pulse");
            $result.text("{{ lang._('Testing...') }}");

            ajaxCall('/api/core/firmware/test_mirror', { 'mirror': url }, function(data, status) {
                $btn.prop("disabled", false);
                $icon.removeClass("fa-spinner fa-pulse").addClass("fa-plug");

                if (!data) {
                    $result.addClass("text-danger").text("{{ lang._('No response from server') }}");
                    return;
                }
                if (data.status === 'ok') {
                    $result.addClass("text-success").html('<i class="fa fa-check"></i> ' + "{{ lang._('DNS, HTTP, signature: OK') }}");
                } else {
                    var step = data.step || '?';
                    var msg = data.message || "{{ lang._('Test failed') }}";
                    var html = '<i class="fa fa-times"></i> ' + "{{ lang._('Failed at') }} <code>" + $("<div/>").text(step).html() + "</code>: " + $("<div/>").text(msg).html();
                    // When the controller couldn't parse the backend output,
                    // show the raw bytes so the operator (or the dev) can see
                    // what configd actually returned — usually points at a
                    // missing /usr/local/sbin/otsa-test-mirror or a script
                    // crash before it printed JSON.
                    if (step === 'parse' && data.raw) {
                        html += '<br><small>raw: <code>' + $("<div/>").text(data.raw).html() + '</code></small>';
                    }
                    $result.addClass("text-danger").html(html);
                }
            });
        });

        $("#change_mirror").click(function(){
            var confopt = {};
            // Save the URL the dropdown is pointing at (or operator's custom
            // input), not whatever leftover value lives in the input field.
            // Strip trailing slashes so the stored value matches the
            // documented "root URL, no trailing slash" convention.
            confopt.mirror = (selectedMirrorUrl() || '').replace(/\/+$/, '');

            // Block obviously invalid URLs before the round-trip. Server-side
            // setAction() applies the canonical check; this mirrors the same
            // first-line check used by the Test button so operators get
            // immediate feedback instead of waiting for a validation error.
            if (!confopt.mirror || !/^https?:\/\//.test(confopt.mirror)) {
                stdDialogInform(
                    '{{ lang._('Firmware status') }}',
                    "{{ lang._('Invalid mirror URL. Expected a root URL like http://192.168.150.49 (no trailing slash).') }}",
                    "{{ lang._('Close') }}",
                    undefined,
                    'danger'
                );
                return;
            }

            $("#settingstab_progress").addClass("fa fa-spinner fa-pulse");
            confopt.flavour = $("#firmware_flavour_value").val();
            confopt.type = $("#firmware_type").val();
            confopt.reboot = $("#firmware_reboot").is(":checked") ? '1' : '0';
            confopt.subscription = $("#firmware_subscription").val();
            ajaxCall('/api/core/firmware/set', { 'firmware': confopt }, function (data, status) {
                $("#settingstab_progress").removeClass("fa fa-spinner fa-pulse");
                if (data['status'] == 'ok') {
                    packagesInfo(true);
                } else {
                    let validation_msgs = '<ul>';
                    for (i = 0; i < data['status_msg'].length; i++) {
                        validation_msgs += '<li>' + $("<textarea/>").html(data['status_msg'][i]).text() + '</li>';
                    }
                    validation_msgs += '</ul>';

                    stdDialogInform('{{ lang._('Firmware status') }}', htmlDecode(validation_msgs), "{{ lang._('Close') }}", undefined, 'danger');
                }
            });
        });

        $("#update_status_copy").click(function () {
            $("#update_status").select();
            document.execCommand("copy");
            document.getSelection().removeAllRanges();
            setTimeout(function () { $("#update_status").blur(); }, 100);
        });

        // update history on tab state and implement navigation
        if(window.location.hash != "") {
            $('a[href="' + window.location.hash + '"]').click()
        }
        $('.nav-tabs a').on('shown.bs.tab', function (e) {
            history.pushState(null, null, e.target.hash);
        });
        $(window).on('hashchange', function(e) {
            $('a[href="' + window.location.hash + '"]').click()
        });

        /* OTSA: state machine for the update card — overlay UI only, leaves backend logic untouched.
           States: idle | checking | uptodate | available | updating | error */
        function otsa_card(state) {
            $('#otsa_update_view > div').hide();
            $('#otsa_update_' + state).show();
        }
        function otsa_refresh_card() {
            ajaxGet('/api/core/firmware/status', {}, function(data, status) {
                if (status !== 'success' || !data) {
                    return;
                }
                if (data['status'] == 'update' || data['status'] == 'upgrade') {
                    var current_ver = 'N/A', new_ver = 'N/A';
                    var target_name = data['product_target'] || '';
                    $.each(data['all_packages'] || [], function(i, row) {
                        if (row['name'] == target_name) {
                            current_ver = row['old'] || 'N/A';
                            new_ver = row['new'] || 'N/A';
                            return false;
                        }
                    });
                    if (data['upgrade_major_version']) {
                        new_ver = data['upgrade_major_version'];
                    }
                    $('#otsa_update_version_info').text(current_ver + ' → ' + new_ver);
                    otsa_card('available');
                } else if (data['status'] == 'none' || data['status'] == 'ok') {
                    otsa_card('uptodate');
                } else if (data['status'] == 'check') {
                    otsa_card('checking');
                } else if (data['status'] == 'error') {
                    $('#otsa_update_error_msg').text(data['status_msg'] || '');
                    otsa_card('error');
                }
            });
        }
        otsa_refresh_card();
        var otsa_check_timer = null;
        // 5 min — longer than any realistic firmware check on the OT mirror,
        // short enough that operators don't stare at a frozen card forever.
        var OTSA_CHECK_TIMEOUT_MS = 5 * 60 * 1000;
        $('#checkupdate').on('click', function() {
            otsa_card('checking');
            // The backend runs in parallel via the upstream handler (backend('check') →
            // trackStatus). Do NOT poll /api/core/firmware/status directly here:
            // the endpoint returns the cached result of the previous check while
            // the backend is still running, so it may report 'none' and flip the
            // card to uptodate before the check actually finishes. The observer
            // below refreshes the card when upstream removes the spinner on
            // #updatetab_progress.
            //
            // Fallback: if the spinner never clears (daemon crash, network
            // down mid-check), the observer never fires and the card sits in
            // 'checking' forever. Force a refresh after the timeout; if the
            // card is still 'checking', flip to 'error' with a friendly note.
            if (otsa_check_timer) {
                clearTimeout(otsa_check_timer);
            }
            otsa_check_timer = setTimeout(function() {
                otsa_check_timer = null;
                otsa_refresh_card();
                if ($('#otsa_update_checking').is(':visible')) {
                    $('#otsa_update_error_msg').text("{{ lang._('Update check timed out. Please verify network connectivity to the mirror and try again.') }}");
                    otsa_card('error');
                }
            }, OTSA_CHECK_TIMEOUT_MS);
        });
        $('#otsa_update_btn').on('click', function() {
            otsa_card('updating');
            $('#upgrade').click();
        });

        // Sync the card with the upstream tracker. trackStatus() removes the
        // 'fa-spinner' class from #updatetab_progress once the backend reports
        // status=='done' — that's when /api/core/firmware/status finally
        // reflects the current check rather than the stale cache.
        (function () {
            var tabIcon = document.getElementById('updatetab_progress');
            if (!tabIcon || typeof MutationObserver === 'undefined') {
                return;
            }
            new MutationObserver(function () {
                if (!tabIcon.classList.contains('fa-spinner')) {
                    if (otsa_check_timer) {
                        clearTimeout(otsa_check_timer);
                        otsa_check_timer = null;
                    }
                    otsa_refresh_card();
                }
            }).observe(tabIcon, { attributes: true, attributeFilter: ['class'] });
        })();
    });
</script>
<div class="container-fluid">
    <div class="row">
        <div class="col-md-12" id="content">
            <ul class="nav nav-tabs" data-tabs="tabs">
                <li id="statustab" class="active"><a data-toggle="tab" href="#status">{{ lang._('Status') }} <i id="statustab_progress"></i></a></li>
                <li id="settingstab"><a data-toggle="tab" href="#settings">{{ lang._('Settings') }} <i id="settingstab_progress"></i></a></li>
                <li id="changelogtab"><a data-toggle="tab" href="#changelog">{{ lang._('Changelog') }}</a></li>
                <li id="updatetab"><a data-toggle="tab" href="#updates">{{ lang._('Updates') }} <i id="updatetab_progress"></i></a></li>
                {# OTSA: hide Plugins/Packages tabs — the appliance does not allow installing arbitrary plugins #}
                <li id="plugintab" style="display:none"><a data-toggle="tab" href="#plugins">{{ lang._('Plugins') }}</a></li>
                <li id="packagestab" style="display:none"><a data-toggle="tab" href="#packages">{{ lang._('Packages') }}</a></li>
            </ul>
            <div class="tab-content content-box">
                <div id="updates" class="tab-pane table-responsive">
                    {# OTSA: friendly card replacing the output console and package list — shows state only, hides technical detail #}
                    <div id="otsa_update_view">
                        <div id="otsa_update_idle">
                            <i class="fa fa-info-circle fa-3x text-info"></i>
                            <h4>{{ lang._('Vui lòng nhấn "Kiểm tra cập nhật" trong tab Trạng thái.') }}</h4>
                        </div>
                        <div id="otsa_update_checking" style="display:none">
                            <i class="fa fa-spinner fa-spin fa-3x text-primary"></i>
                            <h4>{{ lang._('Đang kiểm tra phiên bản...') }}</h4>
                        </div>
                        <div id="otsa_update_uptodate" style="display:none">
                            <i class="fa fa-check-circle fa-3x text-success"></i>
                            <h4>{{ lang._('Hệ thống đang ở phiên bản mới nhất.') }}</h4>
                        </div>
                        <div id="otsa_update_available" style="display:none">
                            <i class="fa fa-arrow-circle-up fa-3x text-warning"></i>
                            <h4>{{ lang._('Có bản cập nhật mới') }}</h4>
                            <p class="lead" id="otsa_update_version_info"></p>
                            <button class="btn btn-primary btn-lg" id="otsa_update_btn">
                                <i class="fa fa-download"></i> {{ lang._('Cập nhật ngay') }}
                            </button>
                        </div>
                        <div id="otsa_update_updating" style="display:none">
                            <i class="fa fa-spinner fa-spin fa-3x text-primary"></i>
                            <h4>{{ lang._('Đang cập nhật, vui lòng chờ...') }}</h4>
                            <p>{{ lang._('Quá trình có thể mất vài phút. Không tắt thiết bị.') }}</p>
                        </div>
                        <div id="otsa_update_error" style="display:none">
                            <i class="fa fa-exclamation-circle fa-3x text-danger"></i>
                            <h4>{{ lang._('Không thể kiểm tra cập nhật') }}</h4>
                            <p id="otsa_update_error_msg"></p>
                        </div>
                    </div>
                    <table class="table table-striped table-condensed" id="updatelist" style="display: none;">
                        <thead>
                            <tr>
                              <th style="width:20%">{{ lang._('Package name') }}</th>
                              <th style="width:20%">{{ lang._('Current version') }}</th>
                              <th style="width:20%">{{ lang._('New version') }}</th>
                              <th style="width:20%">{{ lang._('Required action') }}</th>
                              <th style="width:20%">{{ lang._('Repository') }}</th>
                            </tr>
                        </thead>
                        <tbody></tbody>
                        <tfoot>
                            <tr>
                                <td></td>
                                <td style="white-space:nowrap;vertical-align:middle;">
                                    <button class="btn btn-info" id="upgrade"><i class="fa fa-check"></i> {{ lang._('Update') }}</button>
                                    <button class='btn btn-warning' id="upgrade_maj"><i class="fa fa-check"></i> {{ lang._('Upgrade') }}</button>
                                    <button class="btn btn-default" id="upgrade_cancel"><i class="fa fa-times"></i> {{ lang._('Cancel') }}</button>
                                </td>
                                <td colspan="2" style="vertical-align:middle">
                                    <strong><div id="updatestatus"></div></strong>
                                </td>
                                <td></td>
                            </tr>
                        </tfoot>
                    </table>
                    <div id="update_status_container" class="table-responsive">
                       <textarea name="output" id="update_status" class="form-control" rows="20" wrap="hard" readonly="readonly" style="max-width:100%; font-family: monospace;"></textarea>
                      <table class="table table-striped table-condensed">
                        <tbody>
                          <tr>
                            <td>
                              {{ lang._('Output shown here for diagnostic purposes. There is no general need for manual system intervention.') }}
                              <a id="update_status_copy">{{ lang._('Click here to copy to clipboard.') }}</a>
                            </td>
                          </tr>
                        </tbody>
                      </table>
                    </div>
                </div>
                <div id="status" class="tab-pane active table-responsive">
                    <table class="table table-striped table-condensed">
                        <tbody>
                            {# OTSA: hide technical fields (Type/Arch/Commit/Mirror/Repos) — not needed for end users #}
                            <tr style="display:none">
                                <td style="width: 150px;">{{ lang._('Type') }}</td>
                                <td id="product_id"></td>
                                <td></td>
                            </tr>
                            <tr>
                                <td style="width: 150px;">{{ lang._('Version') }}</td>
                                <td id="product_version"></td>
                                <td></td>
                            </tr>
                            <tr style="display:none">
                                <td style="width: 150px;">{{ lang._('Architecture') }}</td>
                                <td id="product_arch"></td>
                                <td></td>
                            </tr>
                            <tr style="display:none">
                                <td style="width: 150px;">{{ lang._('Commit') }}</td>
                                <td id="product_hash"></td>
                                <td></td>
                            </tr>
                            <tr style="display:none">
                                <td style="width: 150px;">{{ lang._('Mirror') }}</td>
                                <td id="product_mirror"></td>
                                <td></td>
                            </tr>
                            <tr style="display:none">
                                <td style="width: 150px;">{{ lang._('Repositories') }}</td>
                                <td id="product_repos"></td>
                                <td></td>
                            </tr>
                            <tr>
                                <td style="width: 150px;">{{ lang._('Updated on') }}</td>
                                <td id="product_time"></td>
                                <td></td>
                            </tr>
                            <tr>
                                <td style="width: 150px;">{{ lang._('Checked on') }}</td>
                                <td id="product_time_check"></td>
                                <td></td>
                            </tr>
                            <tr style='display:none'>
                                <td style="width: 150px;">{{ lang._('Licensed until') }}</td>
                                <td id="product_license_valid_to"></td>
                                <td></td>
                            </tr>
                            {# OTSA: branding KC01.04-21.30 #}
                            <tr>
                                <td style="width: 150px;">{{ lang._('Vendor') }}</td>
                                <td>
                                    <a href="https://bkcs.hust.edu.vn" target="_blank" rel="noopener">KC01.04-21.30 — Trung tâm An toàn thông tin, ĐHBKHN</a>
                                </td>
                                <td></td>
                            </tr>
                            <tr>
                                <td style="width: 150px;">{{ lang._('Copyright') }}</td>
                                <td>&copy; 2026 KC01.04-21.30. {{ lang._('All rights reserved.') }}</td>
                                <td></td>
                            </tr>
                            <tr>
                                <td style="width: 150px;"></td>
                                <td style="min-width: 500px;">
                                    <button class="btn btn-primary" id="checkupdate"><i class="fa fa-refresh"></i> {{ lang._('Check for updates') }}</button>
                                    <div class="btn-group dropdown" id="audit_actions" style="display:none;">
                                        <button type="button" class="btn btn-default dropdown-toggle" data-toggle="dropdown">
                                            <i class="fa fa-lock"></i> {{ lang._('Run an audit') }} <i class="caret"></i>
                                        </button>
                                        <ul class="dropdown-menu" role="menu">
                                            <li><a id="audit_cleanup" href="#">{{ lang._('Cleanup') }}</a></li>
                                            <li><a id="audit_connection" href="#">{{ lang._('Connectivity') }}</a></li>
                                            <li><a id="audit_health" href="#">{{ lang._('Health') }}</a></li>
                                            <li><a id="audit_security" href="#">{{ lang._('Security') }}</a></li>
                                            <li><a id="audit_upgrade" href="#">{{ lang._('Upgrade') }}</a></li>
                                        </ul>
                                    </div>
                                    <div class="btn-group dropdown" id="plugin_actions" style="display:none;">
                                        <button type="button" class="btn btn-default dropdown-toggle" data-toggle="dropdown">
                                            <i class="fa fa-exclamation-triangle"></i> {{ lang._('Resolve plugin conflicts') }} <i class="caret"></i>
                                        </button>
                                        <ul class="dropdown-menu" role="menu">
                                            <li><a id="plugin_see" href="#">{{ lang._('View and edit local conflicts') }}</a></li>
                                            <li><a id="plugin_get" href="#">{{ lang._('Run the automatic resolver') }}</a></li>
                                            <li><a id="plugin_set" href="#">{{ lang._('Reset all local conflicts') }}</a></li>
                                        </ul>
                                    </div>
                                </td>
                                <td></td>
                            </tr>
                            <tr class="dropdown_helper" style="padding-bottom: 120px;"></tr>
                        </tbody>
                    </table>
                </div>
                <div id="plugins" class="tab-pane table-responsive">
                    <table class="table table-striped table-condensed" id="pluginlist">
                        <thead>
                            <tr>
                                <th style="vertical-align:middle"><input type="text" class="input-sm" autocomplete="off" id="plugin_search" placeholder="{{ lang._('Name') }}"></th>
                                <th style="vertical-align:middle">{{ lang._('Version') }}</th>
                                <th style="vertical-align:middle">{{ lang._('Size') }}</th>
                                <th style="vertical-align:middle">{{ lang._('Tier') }}</th>
                                <th style="vertical-align:middle">{{ lang._('Repository') }}</th>
                                <th style="vertical-align:middle">
                                        {{ lang._('Comment') }}
                                        <span class="checkbox pull-right" style="margin:auto">
                                            <label>
                                                <input type="checkbox" id="plugin_show_community">{{ lang._('Show community plugins') }}
                                            </label>
                                        </span>
                                </th>
                                <th style="vertical-align:middle"></th>
                            </tr>
                        </thead>
                        <tbody></tbody>
                    </table>
                </div>
                <div id="packages" class="tab-pane table-responsive">
                    <table class="table table-striped table-condensed" id="packageslist">
                        <thead>
                            <tr>
                                <th style="vertical-align:middle"><input type="text" class="input-sm" autocomplete="off" id="package_search" placeholder="{{ lang._('Name') }}"></th>
                                <th style="vertical-align:middle">{{ lang._('Version') }}</th>
                                <th style="vertical-align:middle">{{ lang._('Size') }}</th>
                                <th style="vertical-align:middle">{{ lang._('Repository') }}</th>
                                <th style="vertical-align:middle">{{ lang._('License') }}</th>
                                <th style="vertical-align:middle">{{ lang._('Comment') }}</th>
                                <th style="vertical-align:middle"></th>
                            </tr>
                        </thead>
                        <tbody></tbody>
                    </table>
                </div>
                <div id="changelog" class="tab-pane table-responsive">
                    <table class="table table-striped table-condensed" id="changeloglist">
                        <thead></thead>
                        <tbody></tbody>
                    </table>
                </div>
                <div id="settings" class="tab-pane table-responsive">
                    <table class="table table-striped table-condensed">
                        <tbody>
                            {# OTSA: advanced/help toggles hidden — only Mirror (de-facto read-only) and Reboot remain #}
                            <tr style="display:none">
                                <td style="text-align:left"><i class="fa fa-toggle-off text-danger" id="show_advanced_firmware"></i></a> <small>{{ lang._('advanced mode') }}</small></td>
                                <td colspan="2" style="text-align:right">
                                    <small>{{ lang._('full help') }}</small> <a href="#"><i class="fa fa-toggle-off text-danger" id="show_all_help_firmware"></i></a>
                                </td>
                            </tr>
                            <tr>
                                <td style="width: 150px;"><a id="help_for_mirror" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> {{ lang._('Mirror') }}</td>
                                <td>
                                    <select class="selectpicker" id="firmware_mirror"  data-size="5" data-live-search="true">
                                    </select>
                                    <div id="firmware_mirror_custom" style="margin-top: 6px;">
                                        <input type="text" id="firmware_mirror_value" style="width: 100%;" placeholder="http://192.168.150.49">
                                    </div>
                                    <div style="margin-top: 6px;">
                                        <button class="btn btn-default btn-sm" id="test_mirror" type="button">
                                            <i class="fa fa-plug" id="test_mirror_icon"></i> {{ lang._('Test connection') }}
                                        </button>
                                        <span id="test_mirror_result" style="margin-left: 8px;"></span>
                                    </div>
                                    <div class="hidden" data-for="help_for_mirror">
                                        {{ lang._('Default mirror là kho KC01.04-21.30. Chọn "(custom)" để nhập URL khác (vd staging) rồi bấm "Test connection" để xác minh DNS, HTTP, và chữ ký pkg trước khi lưu.') }}
                                    </div>
                                </td>
                                <td></td>
                            </tr>
                            {# OTSA: hide Flavour — flavour is not used in the 26.1 snapshot #}
                            <tr style="display:none">
                                <td><a id="help_for_flavour" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> {{ lang._('Flavour') }}</td>
                                <td>
                                    <select class="selectpicker" id="firmware_flavour">
                                    </select>
                                    <div style="display:none;" id="firmware_flavour_custom">
                                        <input type="text" id="firmware_flavour_value">
                                    </div>
                                    <div class="hidden" data-for="help_for_flavour">
                                        {{ lang._('Select an alternate firmware flavour.') }}
                                    </div>
                                </td>
                                <td></td>
                            </tr>
                            {# OTSA: hide Type — only the Community family is shipped #}
                            <tr style="display:none">
                                <td><a id="help_for_type" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> {{ lang._('Type') }}</td>
                                <td>
                                    <select class="selectpicker" id="firmware_type">
                                    </select>
                                    <div class="hidden" data-for="help_for_type">
                                        {{ lang._('Select the release type.') }}
                                    </div>
                                </td>
                                <td></td>
                            </tr>
                            {# OTSA: hide Subscription — licensing is not used #}
                            <tr style="display:none">
                                <td style="width: 150px;"><a id="help_for_subscription" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a> {{ lang._('Subscription') }}</td>
                                <td>
                                    <input type="text" id="firmware_subscription">
                                    <div class="hidden" data-for="help_for_subscription">
                                        {{ lang._('Provide subscription key.') }}
                                    </div>
                                </td>
                                <td></td>
                            </tr>
                            {# OTSA: data-advanced removed so the Reboot row is always shown #}
                            <tr>
                                <td style="width: 150px;"><i class="fa fa-info-circle text-muted"></i> {{ lang._('Reboot') }}</td>
                                <td>
                                    <input type="checkbox" id="firmware_reboot">
                                    {{ lang._('Always reboot after a successful update') }}
                                </td>
                                <td></td>
                            </tr>
                            <tr>
                                <td style="width: 150px;"><i class="fa fa-info-circle text-muted"></i> {{ lang._('Usage') }}</td>
                                <td>
                                    {{ lang._('In order to apply these settings a firmware update must be performed after save, which can include a reboot of the system.') }}
                                </td>
                                <td></td>
                            </tr>
                            <tr>
                                <td></td>
                                <td>
                                    <button class="btn btn-primary" id="change_mirror" type="button"><i class="fa fa-floppy-o"></i> {{ lang._('Save') }}</button>
                                    <button class="btn btn-default" id="reset_mirror" type="button"><i class="fa fa-times"></i> {{ lang._('Cancel') }}</button>
                                </td>
                                <td></td>
                            </tr>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>
    <div class="row">
        <div class="col-md-12">
            &nbsp;
        </div>
    </div>
</div>
