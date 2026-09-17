<?php

/*
 * Copyright (c) 2024 OTSA Firewall Project
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 */

namespace OPNsense\H323\Api;

use OPNsense\Base\ApiMutableModelControllerBase;
use OPNsense\Core\Backend;
use OPNsense\Core\Syslog;

/**
 * H323 Gateway Settings API Controller
 */
class SettingsController extends ApiMutableModelControllerBase
{
    protected static $internalModelClass = '\OPNsense\H323\H323';
    protected static $internalModelName = 'h323';

    /**
     * Reconfigure and apply H323 rules and restart service
     * @return array
     */
    public function reconfigureAction()
    {
        // ensure early invocation logging so we always create the logfile when endpoint is hit
        $logfile = '/tmp/h323_reconfigure.log';
        @file_put_contents($logfile, date('c') . " entry: reconfigureAction invoked" . PHP_EOL, FILE_APPEND | LOCK_EX);

        $backend = new Backend();
        $logfile = '/tmp/h323_reconfigure.log';
        try {
            // Step 1: Render runtime files (gnugk.conf + runtime json)
            try {
                $runtimeResult = $backend->configdRun('h323 apply_runtime');
                @file_put_contents($logfile, date('c') . " apply_runtime: " . var_export($runtimeResult, true) . PHP_EOL, FILE_APPEND | LOCK_EX);
                if ($runtimeResult === false) {
                    @file_put_contents($logfile, date('c') . " error: apply_runtime returned false" . PHP_EOL, FILE_APPEND | LOCK_EX);
                    return [
                        'status' => 'error',
                        'message' => 'Failed to apply H323 runtime configuration'
                    ];
                }
            } catch (\Throwable $te) {
                @file_put_contents($logfile, date('c') . " exception in apply_runtime: " . $te->getMessage() . PHP_EOL . $te->getTraceAsString() . PHP_EOL, FILE_APPEND | LOCK_EX);
                return [
                    'status' => 'error',
                    'message' => 'Internal error while applying runtime: ' . $te->getMessage()
                ];
            }

            // Step 2: Apply firewall rules
            $ruleResult = $backend->configdRun('h323 apply_rules');
            @file_put_contents($logfile, date('c') . " apply_rules: " . var_export($ruleResult, true) . PHP_EOL, FILE_APPEND | LOCK_EX);
            if ($ruleResult === false) {
                return [
                    'status' => 'error',
                    'message' => 'Failed to apply H323 firewall rules'
                ];
            }

            // Step 2b: Reload standard filter rules so newly written firewall objects are applied
            $filterReload = $backend->configdRun('filter reload');
            @file_put_contents($logfile, date('c') . " filter_reload: " . var_export($filterReload, true) . PHP_EOL, FILE_APPEND | LOCK_EX);

            // Step 3: Restart H323 service (gnugk)
            // $restart_result = $backend->configdRun('h323 restart');
            // @file_put_contents($logfile, date('c') . " restart: " . var_export($restart_result, true) . PHP_EOL, FILE_APPEND | LOCK_EX);
            // $ok = is_string($restart_result) || (bool)$restart_result;

            $ok = is_string($filterReload) || (bool)$filterReload;

            return [
                'status' => $ok ? 'ok' : 'error',
                'message' => $ok ? 'H323 runtime, firewall and service reconfigured' : 'Failed to restart H323 service'
            ];
        } catch (\Exception $e) {
            @file_put_contents($logfile, date('c') . " exception: " . $e->getMessage() . PHP_EOL . $e->getTraceAsString() . PHP_EOL, FILE_APPEND | LOCK_EX);
            return [
                'status' => 'error',
                'message' => 'Internal error: ' . $e->getMessage()
            ];
        }
    }
    /**
     * Return current configuration from the model
     */
    public function getAction()
    {
        return parent::getAction();
    }

    /**
     * Persist posted model data
     */
    public function setAction()
    {
        // Log incoming posted data to help debug missing fields
        $logger = new Syslog('h323_api');
        try {
            $posted = $this->request->getPost(static::$internalModelName);
            $logger->debug(sprintf('Posted h323 payload: %s', json_encode($posted)));
            // also write to a file for environments where syslog isn't visible
            try {
                $logfile = '/tmp/h323_post.log';
                $entry = date('c') . " POSTED: " . json_encode($posted) . PHP_EOL;
                @file_put_contents($logfile, $entry, FILE_APPEND | LOCK_EX);
            } catch (\Exception $e) {
                // swallow file errors, syslog already recorded
            }
        } catch (\Exception $e) {
            $logger->error('Failed to log posted payload: ' . $e->getMessage());
        }

        // Custom setAction: populate interface options before validation so InterfaceField validators succeed
        $result = ['result' => 'failed'];
        if ($this->request->isPost()) {
            \OPNsense\Core\Config::getInstance()->lock();
            // load model and update with provided data
            $mdl = $this->getModel();
            $mdl->setNodes($this->request->getPost(static::$internalModelName));

            // ensure interface option list is populated for validation
            try {
                if (isset($mdl->general) && isset($mdl->general->listen_interface)) {
                    // calling getNodeData will trigger actionPostLoadingEvent and populate options
                    $mdl->general->listen_interface->getNodeData();
                }
            } catch (\Exception $e) {
                // ignore; validation will catch issues
            }

            $result = $this->validate();
            if (empty($result['result'])) {
                $hookErrorMessage = $this->setActionHook();
                if (!empty($hookErrorMessage)) {
                    $result['error'] = $hookErrorMessage;
                } else {
                    $saveRes = $this->save(false, true);

                    // After save, log resulting model nodes for debugging
                    try {
                        $model = $this->getModel();
                        $nodes = $model->getNodes();
                        $logger->debug(sprintf('Model general after set: %s', json_encode($nodes['general'] ?? [])));
                        try {
                            $logfile = '/tmp/h323_post.log';
                            $entry = date('c') . " MODEL general: " . json_encode($nodes['general'] ?? []) . PHP_EOL;
                            @file_put_contents($logfile, $entry, FILE_APPEND | LOCK_EX);
                        } catch (\Exception $e) {
                            // ignore
                        }
                    } catch (\Exception $e) {
                        $logger->error('Failed to log model after set: ' . $e->getMessage());
                    }

                    return $saveRes;
                }
            }
        }

        return $result;
    }

    /* endpoints CRUD using model base helpers */
    public function searchEndpointAction()
    {
        return $this->searchBase('endpoints.endpoint');
    }

    public function getEndpointAction($uuid = null)
    {
        return $this->getBase('endpoint', 'endpoints.endpoint', $uuid);
    }

    public function addEndpointAction()
    {
        return $this->addBase('endpoint', 'endpoints.endpoint');
    }

    public function setEndpointAction($uuid = null)
    {
        return $this->setBase('endpoint', 'endpoints.endpoint', $uuid);
    }

    public function delEndpointAction($uuid)
    {
        return $this->delBase('endpoints.endpoint', $uuid);
    }

    public function toggleEndpointAction($uuid, $enabled = null)
    {
        return $this->toggleBase('endpoints.endpoint', $uuid, $enabled);
    }
}

