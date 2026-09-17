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

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;

/**
 * H323 Service API Controller - provides service control and status endpoints
 */
class ServiceController extends ApiControllerBase
{
    /**
     * Get H323 service status
     * @return array status information
     */
    public function statusAction()
    {
        $backend = new Backend();
        $status = $backend->configdRun('h323 status');
        
        // Parse response: typically "running" or "stopped"
        $is_running = strpos($status, 'running') !== false || strpos($status, 'active') !== false;
        
        return [
            'status' => $is_running ? 'running' : 'stopped',
            'widget' => [
                'caption_start' => 'Start H323',
                'caption_stop' => 'Stop H323',
                'caption_restart' => 'Restart H323'
            ]
        ];
    }

    /**
     * Start H323 service
     * @return array result
     */
    public function startAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed'];
        }

        $backend = new Backend();
        $backend->configdRun('h323 start');
        
        return ['status' => 'ok'];
    }

    /**
     * Stop H323 service
     * @return array result
     */
    public function stopAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed'];
        }

        $backend = new Backend();
        $backend->configdRun('h323 stop');
        
        return ['status' => 'ok'];
    }

    /**
     * Restart H323 service
     * @return array result
     */
    public function restartAction()
    {
        if (!$this->request->isPost()) {
            return ['status' => 'failed'];
        }

        $backend = new Backend();
        $backend->configdRun('h323 restart');
        
        return ['status' => 'ok'];
    }
}
