<?php

/*
 * Copyright (C) 2024 OTSA Contributors
 * All rights reserved.
 */

namespace OPNsense\H323\FieldTypes;

use OPNsense\Base\FieldTypes\InterfaceField;
use OPNsense\Core\Config;

/**
 * Class H323InterfaceField - extends InterfaceField to filter for physical interfaces only
 * (excludes interface groups and virtual interfaces without a physical device)
 * @package OPNsense\H323\FieldTypes
 */
class H323InterfaceField extends InterfaceField
{
    /**
     * Override to filter for physical interfaces only and set default to first available
     */
    protected function actionPostLoadingEvent()
    {
        // Call parent to populate the base option list
        parent::actionPostLoadingEvent();

        // Filter to keep only physical interfaces (those with 'if' field pointing to actual device)
        $configObj = Config::getInstance()->object();
        $physicalInterfaces = array();

        if (isset($configObj->interfaces) && $configObj->interfaces->count() > 0) {
            foreach ($configObj->interfaces->children() as $key => $value) {
                // Only include interfaces that have a physical device assigned
                if (!empty($value->if)) {
                    $physicalInterfaces[$key] = true;
                }
            }
        }

        // Filter the internal option list to only include physical interfaces
        $filteredOptions = array();
        foreach ($this->internalOptionList as $key => $label) {
            if (isset($physicalInterfaces[$key])) {
                $filteredOptions[$key] = $label;
            }
        }

        $this->internalOptionList = $filteredOptions;
    }

    /**
     * Override getNodeData to ensure filtering is applied and set default to first interface
     */
    public function getNodeData($defaults = array())
    {
        // Ensure filtering is applied by calling actionPostLoadingEvent
        $this->actionPostLoadingEvent();

        // Get parent's result which uses our filtered internalOptionList
        $result = parent::getNodeData($defaults);

        // If no value is set, use the first available interface as default
        if (empty($this->internalValue) && is_array($result) && count($result) > 0) {
            // Find first non-empty option key (skip empty string key)
            foreach ($result as $key => $option) {
                if ($key !== "") {
                    $this->internalValue = $key;
                    break;
                }
            }
        }

        return $result;
    }
}
