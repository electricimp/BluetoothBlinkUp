//  ------------------------------------------------------------------------------
//  File: blinkup.device.nut
//
//  Version: 1.4.0
//
//  Copyright 2021 Twilio
//
//  SPDX-License-Identifier: MIT
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
//  MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO
//  EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES
//  OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
//  ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//  ------------------------------------------------------------------------------

/*
 * IMPORTS
 */
#require "bt_firmware.lib.nut:1.0.0"
//#require "btleblinkup.device.lib.nut:2.0.0"
#import "/Users/tsmith/GitHub/BTLEBlinkUp/btleblinkup.device.lib.nut"

/*
 * EARLY RUN CODE
 */
// Prevent the imp sleeping on connection error
server.setsendtimeoutpolicy(RETURN_ON_ERROR, WAIT_TIL_SENT, 10);

/*
 * GLOBALS
 */
local bt = null;
local agentTimer = null;
local bleTimer = null;

/*
 * CONSTANTS
 */
// Post-boot BLE activate duration in seconds
const BLE_ACTIVE_TIME_AFTER_BOOT = 120;

/*
 * FUNCTIONS
 */

// Set the GATT service UUIDs we wil use
function initUUIDs() {
    local uuids = {};
    uuids.blinkup_service_uuid    <- "FADA47BEC45548C9A5F2AF7CF368D719";
    uuids.ssid_setter_uuid        <- "5EBA195632D347C681A6A7E59F18DAC0";
    uuids.password_setter_uuid    <- "ED694AB947564528AA3A799A4FD11117";
    uuids.planid_setter_uuid      <- "A90AB0DC7B5C439A9AB52107E0BD816E";
    uuids.token_setter_uuid       <- "BD107D3E48784F6DAF3DDA3B234FF584";
    uuids.blinkup_trigger_uuid    <- "F299C3428A8A4544AC4208C841737B1B";
    uuids.wifi_getter_uuid        <- "57A9ED95ADD54913849457759B79A46C";
    uuids.wifi_clear_trigger_uuid <- "2BE5DDBA32864D09A652F24FAA514AF5";
    return uuids;
}

// This is a dummy function representing the application code flow.
// In real-world code, this would deliver the product’s day-to-day
// functionality, connection management and error handling code
function startApplication() {
    // Application code starts here
    server.log("Application starting...");
    server.log("Use the agent to restart the device, if required");
}

// This function defines this app's activation flow: preparing the device
// for enrollment into the Electric Imp impCloud and applying the end-user's
// local WiFi network settings.
function startBluetooth() {
    // Instantiate the BTLEBlinkUp library for the imp type
    // NOTE From impOS 42, imp006 doesn't need to be passed firmware
    iType <- imp.info().type;
    bt = (iType == "imp004m" ? BTLEBlinkUp(initUUIDs(), BT_FIRMWARE.CYW_43438) : BTLEBlinkUp(initUUIDs()));

    // Set security level for demo
    bt.setSecurity(1);

    // Register a handler to receive the agent's URL
    agent.on("set.agent.url", function(data) {
        // Agent URL received (from test device only; see below),
        // so run the Bluetooth LE code
        doBluetooth(data);
    }.bindenv(this));

    // Now try and get the agent's URL from the agent
    agent.send("get.agent.url", true);

    // Set up a timer to check if the agent.send() above was un-ACK'd
    // This will be the case with an **unactivated production device**
    // because the agent is not instantiated until after activation
    agentTimer = imp.wakeup(10, function() {
        // Set up a timer to check for an un-ACK'd agent.send(),
        // which will be the case with an unactivated production device
        // (agent not instantiated until after activation)
        agentTimer = null;
        doBluetooth();
    }.bindenv(this));
}

function stopBlinkup() {
    // Turn off BLE so that the device is no longer advertising its presence
    bt.close();
    server.log("BLE BlinkUp no longer available - restart the device to re-enable.");
}

function doBluetooth(agentURL = null) {
    // If we didn't call this from the timer, clear the timer
    if (agentTimer != null) {
        imp.cancelwakeup(agentTimer);
        agentTimer = null;
    }

    // Store the agent URL if present
    if (agentURL != null) bt.agentURL = agentURL;

    // Set the device up to listen for BlinkUp data
    bt.listenForBlinkUp(null, function(data) {
        // This is the callback through which the BLE sub-system communicates
        // with the host app, eg. to inform it activation has taken place
        if ("address" in data) server.log("Device " + data.address + " has " + data.state);
        if ("security" in data) server.log("Connection security mode: " + data.security);

        // FROM 1.4.0
        // Access GATT events and delay the BlinkUp active period timer
        // when credentials are being set
        if ("gatt" in data) {
            server.log(data.gatt.service + ", " + data.gatt.characteristic);

            if (data.gatt.characteristic == "5EBA195632D347C681A6A7E59F18DAC0") {
                // The GATT BlinkUp SSID setter characteristic was accessed
                server.log("WiFi credentials being set -- extending BlinkUp timer by 60 seconds.");
                if (bleTimer != null) imp.cancelwakeup(bleTimer);
                bleTimer = imp.wakeup(60, stopBlinkup);
            }
        }
    }.bindenv(this));

    // FROM 1.4.0
    // Set a post-boot period during which BLE BlinkUp services are available
    if (bleTimer != null) imp.cancelwakeup(bleTimer);
    bleTimer = imp.wakeup(BLE_ACTIVE_TIME_AFTER_BOOT, stopBlinkup);
    server.log("BLE BlinkUp active for " + BLE_ACTIVE_TIME_AFTER_BOOT + " seconds...");
}

/*
 * RUNTIME START
 */

// Register a handler that will restart the device.
// This is triggered via the agent-served UI
agent.on("do.restart", function(data) {
    if ("reset" in imp) {
        imp.reset();
    } else {
        server.restart();
    }
});

// FROM 1.4.0
// To prevent bad credentials from preventing not only the imp from reconnecting
// but also from BLE BlinkUp being made available after boot, we now no longer check
// SPI flash for a BlinkUp signature. Instead we start BLE *and* the application,
// but specify a period (the value of 'BLE_ACTIVE_TIME_AFTER_BOOT', applied in
// 'doBluetooth()') during which BLE BlinkUp is available after a Squirrel restart.
// When this period ends, BLE is closed (see 'doBluetooth()').

// At each Squirrel start, start BLE for BlinkUp
startBluetooth();

// Start the application
startApplication();