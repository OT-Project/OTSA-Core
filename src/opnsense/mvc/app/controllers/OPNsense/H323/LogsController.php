<?php

/*
 * Copyright (c) 2024 OTSA Firewall Project
 * All rights reserved.
 */

namespace OPNsense\H323;

use OPNsense\Base\IndexController;

/**
 * H323 Gateway Logs Controller
 */
class LogsController extends IndexController
{
    /**
     * Render logs page
     */
    public function indexAction()
    {
        $this->view->active_tab = 'logs';
        $this->view->title = gettext('Services: H323 Proxy');
        $this->view->headTitle = gettext('Services: H323 Proxy');
        $this->view->pick('OPNsense/H323/logs');
    }
}
