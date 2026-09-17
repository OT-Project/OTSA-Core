{#
 # Copyright (c) 2024 OTSA Firewall Project
 # All rights reserved.
 #
 # Redistribution and use in source and binary forms, with or without modification,
 # are permitted provided that the following conditions are met:
 #
 # 1. Redistributions of source code must retain the above copyright notice,
 #    this list of conditions and the following disclaimer.
 #
 # 2. Redistributions in binary form must reproduce the above copyright notice,
 #    this list of conditions and the following disclaimer in the documentation
 #    and/or other materials provided with the distribution.
 #
 # THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 # INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 # AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 #}

<!-- service controls are provided by the main layout (see layouts/default.volt)
    avoid duplicating the container here so the buttons appear under the page title
    and above the tabs in the standard header area -->

<ul class="nav nav-tabs" data-tabs="tabs" id="maintabs">
    <li><a data-toggle="tab" href="#settings" id="settings_tab">{{ lang._('Settings') }}</a></li>
    <li style="display: none;"><a data-toggle="tab" href="#endpoints">{{ lang._('Endpoints') }}</a></li>
    <li><a href="/ui/h323/logs">{{ lang._('Logs') }}</a></li>
</ul>

<div class="tab-content content-box">
    <div id="settings" class="tab-pane fade in">
        <div id="response_message" class="alert alert-info" style="display:none; margin: 10px;"></div>

        <form id="frm_h323_settings" class="form-inline">
            <div class="table-responsive">
                <table class="table table-striped table-condensed" style="table-layout: fixed; width: 100%;">
                    <colgroup>
                        <col style="width: 25%;" />
                        <col style="width: 40%;" />
                        <col style="width: 35%;" />
                    </colgroup>
                    <tbody>
                        <tr>
                            <td style="text-align: left"></td>
                            <td colspan="2" style="text-align: right;">
                                <small>{{ lang._('full help') }}</small>
                                <a href="#"><i class="fa fa-toggle-off text-danger" style="cursor: pointer;" id="show_all_help_page"></i></a>
                            </td>
                        </tr>

                        <tr>
                            <td>
                                <div class="control-label">
                                    <a id="help_for_h323_general_enabled" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a>
                                    <b>{{ lang._('Enable h323 service') }}</b>
                                </div>
                            </td>
                            <td>
                                <input type="hidden" name="h323[general][enabled]" value="0" />
                                <input type="checkbox" id="h323.general.enabled" name="h323[general][enabled]" value="1" />
                                <div class="hidden" data-for="help_for_h323_general_enabled"><small>{{ lang._('This will activate the H323 proxy service.') }}</small></div>
                            </td>
                            <td><span class="help-block"></span></td>
                        </tr>

                        <tr>
                            <td>
                                <div class="control-label">
                                    <a id="help_for_h323_general_listen_interface" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a>
                                    <b>{{ lang._('Inbound interface') }}</b>
                                </div>
                            </td>
                            <td>
                                <select id="h323.general.listen_interface" name="h323[general][listen_interface]" class="selectpicker" data-live-search="true" data-width="100%">
                                    <option value="">{{ lang._('Any') }}</option>
                                </select>
                                <div class="hidden" data-for="help_for_h323_general_listen_interface"><small>{{ lang._('Select the interface where your H323 requests come from.') }}</small></div>
                            </td>
                            <td><span class="help-block"></span></td>
                        </tr>

                        <tr>
                            <td>
                                <div class="control-label">
                                    <a id="help_for_h323_general_outbound_interface" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a>
                                    <b>{{ lang._('Outbound interface') }}</b>
                                </div>
                            </td>
                            <td>
                                <select id="h323.general.outbound_interface" name="h323[general][outbound_interface]" class="selectpicker" data-live-search="true" data-width="100%">
                                    <option value="">{{ lang._('Any') }}</option>
                                    <option value="lo0">{{ lang._('Loopback') }}</option>
                                </select>
                                <div class="hidden" data-for="help_for_h323_general_outbound_interface"><small>{{ lang._('Select the interface to use for the H.323 gateway connection path. Use Loopback for local service.') }}</small></div>
                            </td>
                            <td><span class="help-block"></span></td>
                        </tr>

                        <tr>
                            <td>
                                <div class="control-label">
                                    <a id="help_for_h323_general_upstream_server" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a>
                                    <b>{{ lang._('Upstream server') }}</b>
                                </div>
                            </td>
                            <td>
                                <input type="text" id="h323.general.upstream_server" name="h323[general][upstream_server]" class="form-control" placeholder="192.168.1.1" />
                                <div class="hidden" data-for="help_for_h323_general_upstream_server"><small>{{ lang._('IP address or hostname of the upstream H.323 gateway. For local service, use 127.0.0.1.') }}</small></div>
                            </td>
                            <td><span class="help-block"></span></td>
                        </tr>

                        <tr>
                            <td>
                                <div class="control-label">
                                    <a id="help_for_h323_general_signaling_port" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a>
                                    <b>{{ lang._('Signaling port (TCP)') }}</b>
                                </div>
                            </td>
                            <td>
                                <input type="number" id="h323.general.signaling_port" name="h323[general][signaling_port]" class="form-control" min="1024" max="65535" value="1720" />
                                <div class="hidden" data-for="help_for_h323_general_signaling_port"><small>{{ lang._('H.225 call setup port, default: 1720.') }}</small></div>
                            </td>
                            <td><span class="help-block"></span></td>
                        </tr>

                        <tr>
                            <td>
                                <div class="control-label">
                                    <a id="help_for_h323_general_rtp_start" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a>
                                    <b>{{ lang._('RTP port range start') }}</b>
                                </div>
                            </td>
                            <td>
                                <input type="number" id="h323.general.rtp_port_range_start" name="h323[general][rtp_port_range_start]" class="form-control" min="1024" max="65535" value="5000" />
                                <div class="hidden" data-for="help_for_h323_general_rtp_start"><small>{{ lang._('RTP media port range start.') }}</small></div>
                            </td>
                            <td><span class="help-block"></span></td>
                        </tr>

                        <tr>
                            <td>
                                <div class="control-label">
                                    <a id="help_for_h323_general_rtp_end" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a>
                                    <b>{{ lang._('RTP port range end') }}</b>
                                </div>
                            </td>
                            <td>
                                <input type="number" id="h323.general.rtp_port_range_end" name="h323[general][rtp_port_range_end]" class="form-control" min="1024" max="65535" value="5100" />
                                <div class="hidden" data-for="help_for_h323_general_rtp_end"><small>{{ lang._('RTP media port range end.') }}</small></div>
                            </td>
                            <td><span class="help-block"></span></td>
                        </tr>

                        <tr>
                            <td>
                                <div class="control-label">
                                    <a id="help_for_h323_general_nat_enabled" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a>
                                    <b>{{ lang._('Enable NAT traversal') }}</b>
                                </div>
                            </td>
                            <td>
                                <input type="hidden" name="h323[general][nat_enabled]" value="0" />
                                <input type="checkbox" id="h323.general.nat_enabled" name="h323[general][nat_enabled]" value="1" />
                                <div class="hidden" data-for="help_for_h323_general_nat_enabled"><small>{{ lang._('Enable NAT traversal handling for endpoints behind NAT.') }}</small></div>
                            </td>
                            <td><span class="help-block"></span></td>
                        </tr>

                        <tr>
                            <td>
                                <div class="control-label">
                                    <a id="help_for_h323_general_gateway_alias" href="#" class="showhelp"><i class="fa fa-info-circle"></i></a>
                                    <b>{{ lang._('Gateway alias') }}</b>
                                </div>
                            </td>
                            <td>
                                <input type="text" id="h323.general.gateway_alias" name="h323[general][gateway_alias]" class="form-control" value="OTSA-H323" />
                                <div class="hidden" data-for="help_for_h323_general_gateway_alias"><small>{{ lang._('Logical identifier used by the H323 gateway.') }}</small></div>
                            </td>
                            <td><span class="help-block"></span></td>
                        </tr>

                        <tr>
                            <td colspan="3">
                                <button type="button" class="btn btn-primary" id="reconfigureAct" data-endpoint="/api/h323/settings/reconfigure" data-label="{{ lang._('Apply') }}" data-service-widget="h323" data-error-title="{{ lang._('Error reconfiguring H323 service.') }}"></button>
                            </td>
                        </tr>
                    </tbody>
                    <tfoot><tr><td colspan="3" style="padding: 0;"></td></tr></tfoot>
                </table>
            </div>
        </form>
    </div>

    <div id="endpoints" class="tab-pane fade in">
        <div style="padding: 10px;">
            <button class="btn btn-xs btn-primary" id="btn_add_endpoint" type="button" onclick="addEndpointModal();">
                <span class="fa fa-fw fa-plus"></span> {{ lang._('Add Endpoint') }}
            </button>
        </div>
        <table class="table table-condensed table-hover table-striped table-responsive" id="endpoints_table">
            <thead>
                <tr>
                    <th>{{ lang._('Name') }}</th>
                    <th>{{ lang._('Address') }}</th>
                    <th>{{ lang._('Enabled') }}</th>
                    <th>{{ lang._('Description') }}</th>
                    <th>{{ lang._('Actions') }}</th>
                </tr>
            </thead>
            <tbody id="endpoints_body"></tbody>
            <tfoot></tfoot>
        </table>
    </div>

</div>

<!-- Endpoint Modal -->
<div class="modal fade" id="endpointModal" tabindex="-1" role="dialog" aria-labelledby="endpointModalLabel">
    <div class="modal-dialog" role="document">
        <div class="modal-content">
            <div class="modal-header">
                <button type="button" class="close" data-dismiss="modal" aria-label="{{ lang._('Close') }}"><span aria-hidden="true">&times;</span></button>
                <h4 class="modal-title" id="endpointModalLabel">{{ lang._('Edit Endpoint') }}</h4>
            </div>
            <form id="frm_endpoint">
                <input type="hidden" id="ep_id" name="id" />
                <div class="modal-body">
                    <div class="form-group">
                        <label for="ep_name">{{ lang._('Endpoint Name') }}</label>
                        <input type="text" class="form-control" id="ep_name" name="name" required />
                    </div>
                    <div class="form-group">
                        <label for="ep_address">{{ lang._('IP Address') }}</label>
                        <input type="text" class="form-control" id="ep_address" name="address" placeholder="192.168.1.10" required />
                    </div>
                    <div class="checkbox">
                        <label><input type="checkbox" id="ep_enabled" name="enabled" checked /> {{ lang._('Enabled') }}</label>
                    </div>
                    <div class="form-group">
                        <label for="ep_description">{{ lang._('Description') }}</label>
                        <textarea class="form-control" id="ep_description" name="description" rows="3"></textarea>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-default" data-dismiss="modal">{{ lang._('Cancel') }}</button>
                    <button type="submit" class="btn btn-primary">{{ lang._('Save Endpoint') }}</button>
                </div>
            </form>
        </div>
    </div>
</div>

<script>
$(document).ready(function() {
    // Toggle service controls based on enabled checkbox
    function syncServiceStatusUI() {
        if ($('[id="h323.general.enabled"]').is(':checked')) {
            $('#service_status_container').show();
            updateServiceControlUI('h323');
        } else {
            $('#service_status_container').hide().empty();
        }
    }

    // When user toggles enable mark settings as changed; update service controls
    // only after the user applies the new configuration (on successful reconfigure).
    window.h323_pending_changes = false;
    $('[id="h323.general.enabled"]').on('change', function() {
        window.h323_pending_changes = true;
        // Inform the user they need to apply to update the service status
        showMessage('{{ lang._("Settings modified, click Apply to update service status") }}', 'info');
    });
    
    // populate interfaces first, then load configuration
    populateInterfaceSelect().always(function() {
        // Load configuration
        $.get('/api/h323/settings/get', function(data) {
            if (data.h323) {
                var h323 = data.h323;
                if (h323.general) {
                    $('[id="h323.general.enabled"]').prop('checked', h323.general.enabled == 1);
                    $('[id="h323.general.signaling_port"]').val(h323.general.signaling_port || 1720);
                    $('[id="h323.general.rtp_port_range_start"]').val(h323.general.rtp_port_range_start || 5000);
                    $('[id="h323.general.rtp_port_range_end"]').val(h323.general.rtp_port_range_end || 5100);
                    $('[id="h323.general.nat_enabled"]').prop('checked', h323.general.nat_enabled == 1);
                    $('[id="h323.general.gateway_alias"]').val(h323.general.gateway_alias || 'OTSA-H323');
                    $('[id="h323.general.upstream_server"]').val(h323.general.upstream_server || '');
                    
                    syncServiceStatusUI();
                    
                    // set selected inbound interface if present
                    if (h323.general.listen_interface) {
                        var li = h323.general.listen_interface;
                        // InterfaceField is returned as an object of options with selected flags
                        if (typeof li === 'object') {
                            var selectedKey = null;
                            Object.keys(li).forEach(function(k) {
                                if (li[k] && li[k].selected) selectedKey = k;
                            });
                            if (selectedKey !== null) {
                                $('[id="h323.general.listen_interface"]').val(selectedKey).trigger('change');
                            }
                        } else {
                            // fallback: plain string
                            $('[id="h323.general.listen_interface"]').val(li).trigger('change');
                        }
                    }
                    
                    // set selected outbound interface if present
                    if (h323.general.outbound_interface) {
                        var oi = h323.general.outbound_interface;
                        $('[id="h323.general.outbound_interface"]').val(oi);
                        $('[id="h323.general.outbound_interface"]').selectpicker('refresh');
                    }
                }
                // load endpoints into table (model format: h323.endpoints.endpoint)
                var eps = [];
                if (h323.endpoints) {
                    if (h323.endpoints.endpoint) {
                        eps = Array.isArray(h323.endpoints.endpoint) ? h323.endpoints.endpoint : [h323.endpoints.endpoint];
                    }
                }
                renderEndpoints(eps);
            }
        });
    });

    $('#reconfigureAct').SimpleActionButton({
        onPreAction: function() {
            var dfObj = new $.Deferred();
            
            saveFormToEndpoint('/api/h323/settings/set', 'frm_h323_settings', function() {
                dfObj.resolve();
            }, true, function(data) {
                // Show error message on validation failure
                if (data && data.validations) {
                    var msgs = [];
                    for (var k in data.validations) { 
                        if (data.validations.hasOwnProperty(k)) { 
                            msgs.push(k + ': ' + data.validations[k]); 
                        } 
                    }
                    showMessage(msgs.join('; '), 'danger');
                } else {
                    showMessage('Failed to save settings', 'danger');
                }
                dfObj.reject();
            });
            return dfObj;
        },
        onAction: function(data, status) {
            if (status === 'success') {
                showMessage('H323 service reconfigured successfully', 'success');
                // Clear pending-change flag and update service controls now that changes are applied
                window.h323_pending_changes = false;
                syncServiceStatusUI();
            } else {
                showMessage('Failed to reconfigure H323 service', 'danger');
            }
        }
    });

    var default_tab = '{{ active_tab|default("") }}';
    var selected_tab = window.location.hash != '' ? window.location.hash : (default_tab !== '' ? '#' + default_tab : '#settings');
    $('a[href="' + selected_tab + '"]').tab('show');
    $('.nav-tabs a').on('shown.bs.tab', function (e) {
        history.pushState(null, null, e.target.hash);
    });
    $(window).on('hashchange', function() {
        $('a[href="' + window.location.hash + '"]').click();
    });
});

// populate the interface select using the firewall API which returns grouped interfaces
function populateInterfaceSelect() {
    return $.get('/api/firewall/filter/get_interface_list', function(data) {
        var inbound = $('[id="h323.general.listen_interface"]');
        var outbound = $('[id="h323.general.outbound_interface"]');
        
        inbound.empty();
        outbound.empty();
        
        inbound.append($('<option/>').attr('value','').text('{{ lang._("Any") }}'));
        outbound.append($('<option/>').attr('value','').text('{{ lang._("Any") }}'));
        outbound.append($('<option/>').attr('value','lo0').text('{{ lang._("Loopback") }}'));

        // add interfaces to both selects
        if (data.interfaces && data.interfaces.items) {
            var ig_in = $('<optgroup/>').attr('label', '{{ lang._("Interfaces") }}');
            var ig_out = $('<optgroup/>').attr('label', '{{ lang._("Interfaces") }}');
            data.interfaces.items.forEach(function(item) {
                ig_in.append($('<option/>').attr('value', item.value).text(item.label));
                ig_out.append($('<option/>').attr('value', item.value).text(item.label));
            });
            inbound.append(ig_in);
            outbound.append(ig_out);
        }
        $('.selectpicker').selectpicker('refresh');
    }).fail(function() {
        // ignore failure; keep default Any option
    });
}

function showMessage(message, type) {
    var messageDiv = $('#response_message');
    messageDiv.removeClass('alert-success alert-danger alert-warning alert-info');
    messageDiv.addClass('alert-' + type);
    messageDiv.text(message);
    messageDiv.show();
    
    setTimeout(function() {
        messageDiv.fadeOut();
    }, 5000);
}

function addEndpointModal() {
    $('#frm_endpoint')[0].reset();
    $('#ep_id').val('');
    $('#endpointModal').modal('show');
}

// Render endpoints list into the table
function renderEndpoints(endpoints) {
    var tbody = $('#endpoints_body');
    tbody.empty();
    endpoints.forEach(function(ep) {
        // tolerate multiple shapes: prefer uuid, fallback to id
        var uid = ep.uuid || ep.id || ep.UUID || null;
        var tr = $('<tr/>');
        tr.append($('<td/>').text(ep.name || ''));
        tr.append($('<td/>').text(ep.address || ''));
        var enabled = (ep.enabled === undefined) ? (ep.enabled = 1) : ep.enabled;
        tr.append($('<td/>').html(enabled ? '<span class="label label-success">Yes</span>' : '<span class="label label-danger">No</span>'));
        tr.append($('<td/>').text(ep.description || ''));
        var actions = $('<td/>');
        actions.append($('<button class="btn btn-xs btn-primary"/>').text('Edit').click(function(){ editEndpoint(ep); }));
        actions.append(' ');
        actions.append($('<button class="btn btn-xs btn-danger"/>').text('Delete').click(function(){ deleteEndpoint(uid || ep.id); }));
        tr.append(actions);
        tbody.append(tr);
    });
}

// Edit an existing endpoint (populate modal)
function editEndpoint(ep) {
    $('#ep_id').val(ep.uuid || ep.id || '');
    $('#ep_name').val(ep.name);
    $('#ep_address').val(ep.address);
    $('#ep_enabled').prop('checked', ep.enabled == 1);
    $('#ep_description').val(ep.description);
    $('#endpointModal').modal('show');
}

// Delete endpoint (mock)
function deleteEndpoint(id) {
    if (!confirm('{{ lang._("Delete this endpoint?") }}')) return;
    $.post('/api/h323/settings/delEndpoint/' + id, function(data) {
        if (data.result === 'deleted') {
            showMessage('{{ lang._("Endpoint deleted") }}', 'success');
            // reload list from model
            $.get('/api/h323/settings/get', function(resp) { if (resp.h323) { var e = resp.h323.endpoints && resp.h323.endpoints.endpoint ? (Array.isArray(resp.h323.endpoints.endpoint)? resp.h323.endpoints.endpoint : [resp.h323.endpoints.endpoint]) : []; renderEndpoints(e); } });
        } else {
            showMessage('{{ lang._("Failed to delete endpoint") }}', 'danger');
        }
    }).fail(function(){ showMessage('{{ lang._("Error contacting server") }}', 'danger'); });
}

// Endpoint form submission: add or update
$('#frm_endpoint').submit(function(e) {
    e.preventDefault();
    var id = $('#ep_id').val();
    var url = id ? '/api/h323/settings/setEndpoint/' + id : '/api/h323/settings/addEndpoint';
    var postData = {};
    postData['endpoint[name]'] = $('#ep_name').val();
    postData['endpoint[address]'] = $('#ep_address').val();
    postData['endpoint[enabled]'] = $('#ep_enabled').is(':checked') ? 1 : 0;
    postData['endpoint[description]'] = $('#ep_description').val();
    $.post(url, postData, function(data) {
        if (data.result && data.result === 'saved') {
            showMessage('{{ lang._("Endpoint saved") }}', 'success');
            $('#endpointModal').modal('hide');
            $.get('/api/h323/settings/get', function(resp) { if (resp.h323) { var e = resp.h323.endpoints && resp.h323.endpoints.endpoint ? (Array.isArray(resp.h323.endpoints.endpoint)? resp.h323.endpoints.endpoint : [resp.h323.endpoints.endpoint]) : []; renderEndpoints(e); } });
        } else {
            showMessage('{{ lang._("Failed to save endpoint") }}', 'danger');
        }
    }).fail(function(){ showMessage('{{ lang._("Error contacting server") }}', 'danger'); });
});
</script>
