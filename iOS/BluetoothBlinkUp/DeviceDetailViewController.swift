
//  ViewController.swift
//  BluetoothBlinkUp
//
//  Created by Tony Smith on 12/14/17.
//
//  MIT License
//
//  Copyright 2017-19 Electric Imp
//
//  Version 1.3.1
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



import UIKit
import CoreBluetooth
import BlinkUp


class DeviceDetailViewController: UIViewController, CBCentralManagerDelegate, CBPeripheralDelegate, UIPickerViewDelegate, UIPickerViewDataSource, UITextFieldDelegate {

    // UI Outlets
    @IBOutlet weak var sendLabel: UILabel!
    @IBOutlet weak var blinkUpProgressBar: UIActivityIndicatorView!
    @IBOutlet weak var wifiPicker: UIPickerView!
    @IBOutlet weak var passwordField: UITextField!

    // Properties
    var bluetoothManager: CBCentralManager!
    var device: Device? = nil
    var availableNetworks: [ [String] ] = []
    var config: BUConfigId? = nil
    var connected: Bool = false
    var clearList: Bool = false
    var isSending: Bool = false
    var isClearing: Bool = false
    var isShowingWebview: Bool = false
    var harvey: String!
    var agentURL: String!
    var scanTimer: Timer!
    var cheatTimer: Timer!
    
    // Constants
    let DEVICE_SCAN_TIMEOUT = 5.0
    let CANCEL_TIME = 3.0
    let BLINKUP_SERVICE_UUID = "FADA47BE-C455-48C9-A5F2-AF7CF368D719"
    let SSID_SETTER_UUID = "5EBA1956-32D3-47C6-81A6-A7E59F18DAC0"
    let PASSWORD_SETTER_UUID = "ED694AB9-4756-4528-AA3A-799A4FD11117"
    let PLANID_SETTER_UUID = "A90AB0DC-7B5C-439A-9AB5-2107E0BD816E"
    let TOKEN_SETTER_UUID = "BD107D3E-4878-4F6D-AF3D-DA3B234FF584"
    let BLINKUP_TRIGGER_UUID = "F299C342-8A8A-4544-AC42-08C841737B1B"
    let WIFI_GETTER_UUID = "57A9ED95-ADD5-4913-8494-57759B79A46C"
    let WIFI_CLEAR_TRIGGER_UUID = "2BE5DDBA-3286-4D09-A652-F24FAA514AF5"
    

    // MARK: - View Lifecycle Functions

    override func viewDidLoad() {

        super.viewDidLoad()

        // Set up the 'show password' button within the password entry field
        let overlayButton: UIButton = UIButton.init(type: UIButton.ButtonType.custom)
        overlayButton.setImage(UIImage.init(named: "button_eye"), for: UIControl.State.normal)
        overlayButton.addTarget(self, action: #selector(self.showPassword(_:)), for: UIControl.Event.touchUpInside)
        overlayButton.frame = CGRect.init(x: 0, y: 6, width: 20, height: 16)

        // Assign the overlay button to a stored text field
        self.passwordField.leftView = overlayButton
        self.passwordField.leftViewMode = UITextField.ViewMode.always

        // Watch for app returning to foreground from the ImpDetailViewController
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.connectToDevice),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
    }

    
    override func viewWillAppear(_ animated: Bool) {

        super.viewWillAppear(animated)
        
        // FROM 1.2.1
        // If we're returning from the web view, go direct to the device list
        if self.isShowingWebview {
            self.isShowingWebview = false
            goBack()
            return
        }
        
        initNetworks()
        connectToDevice()
    }
    
    
    @objc func connectToDevice() {
        
        // App is about to come back into view after the user previously
        // switched to a different app, so reset the UI - unless we're sending
        if !self.isSending {
            initUI()
        
            // Get the networks from the device
            if let aDevice: Device = device {
                // NOTE We need to set the objects' delegates to 'self' so that the correct delegate functions are called
                aDevice.peripheral.delegate = self
                self.bluetoothManager.delegate = self

                if !self.connected {
                    self.wifiPicker.isUserInteractionEnabled = false
                    self.bluetoothManager.connect(aDevice.peripheral, options: nil)
                    self.blinkUpProgressBar.startAnimating()
                    self.scanTimer = Timer.scheduledTimer(timeInterval: DEVICE_SCAN_TIMEOUT,
                                                          target: self,
                                                          selector: #selector(self.endConnectWithAlert),
                                                          userInfo: nil,
                                                          repeats: false)
                }
            }
        }
    }

    
    override func viewDidAppear(_ animated: Bool) {

        super.viewDidAppear(animated)
    }
    
    
    @objc func endConnectWithAlert() {
        
        // This function is called when 'scanTimer' fires. This event indicates that
        // the device failed to connect for some reason - so report it to the user
        if let aDevice: Device = device {
            self.bluetoothManager.cancelPeripheralConnection(aDevice.peripheral)
            self.connected = false
            showDisconnectAlert("Could not connect to \"\(aDevice.name)\"", "Please go back to the devices list and re-select \"\(aDevice.name)\", if necessary performing a new scan, or clear its SPI flash signature using the Web UI to re-enable Bluetooth BlinkUp")
        }
        
        self.isClearing = false
        self.isSending = false
        self.blinkUpProgressBar.stopAnimating()
    }
    
    
    func initUI() {

        // Initialise the UI
        self.blinkUpProgressBar.stopAnimating()
        self.passwordField.text = ""
        self.sendLabel.text = ""
    }

    
    func initNetworks() {

        // Initialize the UIPickerView which presents the network list
        // NOTE The actual network data is gathered in the background
        // ( see viewDidAppear() )
        // Add a placeholder network name
        self.availableNetworks.removeAll()
        self.availableNetworks.append(["None", "unlocked"])

        // Set the UI - disabling the picker
        self.wifiPicker.reloadAllComponents()
        self.wifiPicker.isUserInteractionEnabled = false
        self.wifiPicker.alpha = 0.5
        self.wifiPicker.isUserInteractionEnabled = true
    }

    
    @objc func goBack() {

        // Return to the device list - unless we are sending data ('isSending' is true),
        // in which case notify the user
        if self.isSending {
            showAlert("BlinkUp in Progress", "Please wait until all the Blinkup information has been sent to the device")
            return
        }

        // If a device is connected, disconnect from it
        if self.connected {
            if let aDevice: Device = self.device {
                self.bluetoothManager.cancelPeripheralConnection(aDevice.peripheral)
                self.connected = false
            }
        }

        // Stop listening for 'will enter foreground' notifications
        NotificationCenter.default.removeObserver(self)

        // Jump back to the list of devices
        self.navigationController!.popViewController(animated: true)
    }


    // MARK: - Action Functions

    @IBAction func doBlinkup(_ sender: Any) {

        // Already sending or connecting in order to clear? Then bail
        if self.isSending || self.isClearing { return }

        // Trigger the disconnection timer (for slow users)
        if self.cheatTimer != nil && self.cheatTimer.isValid { self.cheatTimer.fire() }

        // Do we have the data we need from the UI, ie. a password for a locked network?
        let index = self.wifiPicker.selectedRow(inComponent: 0)
        let network = self.availableNetworks[index]

        // If the network is locked, the user must enter a password
        if network[1] == "locked" && self.passwordField.text!.isEmpty {
            self.showAlert("This network requires a password", "You need to enter a password for a locked network.")
            return
        }

        // If there are no compatible networks around the device, we can't proceed
        if network[0] == "None" {
            self.showAlert("There are no networks to connect to", "")
            return
        }
        
        // Check whether the user has entered a BlinkUp API Key
        if self.harvey.count == 0 {
            // No API key has been entered so post a warning, and give the user
            // the opportunity to go back and enter one
            let alert = UIAlertController.init(title: "Device Activation Requires A BlinkUp™ API key",
                                               message: "Without entering a BlinkUp API Key, you will only be able to send WiFi credentials to an already activated device. To activate devices, please tap ‘Cancel’, go back to the device list, tap ‘Actions’ and select ‘Enter Your BlinkUp API Key’",
                                               preferredStyle: UIAlertController.Style.alert)
            
            alert.addAction(UIAlertAction(title: "OK",
                                          style: UIAlertAction.Style.default,
                                          handler: { (action) in
                                            // User has clicked OK, so go to step two
                                            self.blinkupStageTwo()
            }))
            
            alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""),
                                          style: UIAlertAction.Style.cancel,
                                          handler: nil))
            
            self.present(alert,
                         animated: true,
                         completion: nil)
        } else {
            // Go direct to step two
            blinkupStageTwo()
        }
    }
    
    
    func blinkupStageTwo() {
        
        // Step two of the pre-BlinkUp process
        // NOTE This is a separate function because it may be called from multple code paths
        
        // Start the indicator
        self.blinkUpProgressBar.startAnimating()
        
        // Are we already connected to the device?
        if !self.connected {
            // App is not connected to the device, so connect now
            if let aDevice = self.device {
                self.isSending = true
                self.bluetoothManager.connect(aDevice.peripheral,
                                              options: nil)
                // Pick up the action at didConnect(), which is called when the
                // iDevice has connected to the imp004m
                
                // Set up a timeout
                self.scanTimer = Timer.scheduledTimer(timeInterval: DEVICE_SCAN_TIMEOUT,
                                                      target: self,
                                                      selector: #selector(self.endConnectWithAlert),
                                                      userInfo: nil,
                                                      repeats: false)
            }
        } else {
            // App is already connected to the peripheral so go direct
            // to step three to do the BlinkUp
            blinkupStageThree()
        }
    }
    
    
    func blinkupStageThree() {

        // Use the BlinkUp SDK to retrieve an enrollment token and a plan ID from the user's API Key
        // You will need to be an Electric Imp customer with a BlinkUp API Key to make this work
        // If no API key is known to the app, it will just transmit WiFi data
        // NOTE This is a separate function because it may be called from multple code paths

        self.isSending = true
        if self.scanTimer.isValid { self.scanTimer.invalidate() }
        
        // NOTE The progress indicator is already active at this point
        if self.connected {
            // We're good to proceed so begin BlinkUp
            sendLabel.text = "Sending WiFi data"

            if self.harvey.count == 0 {
                // The user HAS NOT input a BlinkUp API key, so just send across WiFi credentials,
                // ie. do not perform a device enrolment too
                if let aDevice = self.device {
                    // Transmit the WiFi data
                    sendWiFiData(aDevice)

                    // Since we can't poll the server for this instance (we have no API key), we
                    // just warn the user via an alert to expect the device to connect
                    // Close the connection in CANCEL_TIME seconds' time
                    self.cheatTimer = Timer.scheduledTimer(withTimeInterval: self.CANCEL_TIME,
                                                           repeats: false,
                                                           block: { (_) in
                        if let aDevice = self.device {
                            self.bluetoothManager.cancelPeripheralConnection(aDevice.peripheral)
                            self.connected = false
                            self.isSending = false

                            // Clean up the UI
                            self.sendLabel.text = ""
                            self.blinkUpProgressBar.stopAnimating()
                            
                            // Instantiate and show a webview containing the agent-served UI
                            // TODO Incorporate a check to load the agent-served string and check that
                            //      it is valid HTML before loading
                            if (aDevice.agent.count > 0) {
                                self.showWebview(aDevice.agent)
                            } else {
                                self.showAlert("Device Connecting", "Your device has received WiFi credentials and is connecting to the Electric Imp impCloud™.")
                            }
                        }
                    })
                }
            } else {
                // The user HAS input a BlinkUp API key, so perform a full activation
                // (enrol the deviceand transmit WiFi credentials).
                // First, get a BUConfigID — this REQUIRES a BlinkUp API key
                let _ = BUConfigId.init(apiKey: self.harvey) { (_ config: BUConfigId.ConfigIdResponse) -> Void in
                    // 'config' is the response to the creation of the BUConfigID
                    // It has two possible values:
                    //    .activated (passes in the active BUConfigID)
                    //    .error     (passes in an NSError)
                    switch config {
                    case .activated(let activeConfig):
                        self.config = activeConfig

                        if let aDevice = self.device {
                            // Send the Enrolment Data
                            self.sendEnrolData(aDevice, activeConfig)

                            // Transmit the WiFi data
                            self.sendWiFiData(aDevice)

                            // Update the UI
                            self.sendLabel.text = "Waiting for device to enrol"

                            // Begin polling the server for an indication that the device
                            // has connected and been enrolled
                            let poller = BUDevicePoller.init(configId: activeConfig)
                            poller.startPollingWithHandler({ (response) in
                                self.sendLabel.text = ""
                                self.blinkUpProgressBar.stopAnimating()
                                
                                switch(response) {
                                case .responded(let info):
                                    // The server indicates that the device has enrolled successfully, so we're done
                                    if let us = info.agentURL?.absoluteString {
                                        self.showWebview(us)
                                    } else {
                                        self.showAlert("Device Enrolled", "Your device has connected to the Electric Imp impCloud™.")
                                    }
                                case .error(let error):
                                    // Something went wrong, so dump the error and perform the timed out flow
                                    NSLog(error.description)
                                    fallthrough
                                case .timedOut:
                                    // The server took too long to respond, so assume enrollment did not take place
                                    self.showAlert("Device Failed to Connect", "Your device has not enrolled in the impCloud")
                                }

                                // Done isSending, so cancel the connection (best practice to save battery power)
                                if let aDevice = self.device {
                                    self.bluetoothManager.cancelPeripheralConnection(aDevice.peripheral)
                                    self.connected = false
                                }

                                self.isSending = false
                            })
                        }

                        // We exit here, but will pick up writing in blinkupStageThree() called from within
                        // the above delegate function in respomse to a successful pairing and write

                    case .error(let error):
                        // Could not create the BUConfigID - maybe the API is wroing/invalid?
                        NSLog("\(error.localizedDescription)")

                        self.showAlert("BlinkUp Could Not Proceed", "Your BlinkUp API Key is not correct.\nPlease re-enter or clear it via the main Devices list on the previous screen (Actions > Enter API Key). An API key is only required for new device enrollment — updating WiFi details on an enrolled device does not require a BlinkUp API key.")

                        self.blinkUpProgressBar.stopAnimating()
                        self.isSending = false
                    }
                }
            }
        } else {
            // Should be connected at this point, but for some reason we're not
            // Post a warning to the user
            showAlert("Please connect to a Device", "You must be connected to an imp-enabled device with Bluetooth in order to perform BlinkUp. Return to the Device List and re-select the device")
        }
    }

    
    func sendEnrolData(_ device: Device, _ config: BUConfigId) {

        // Package up the enrolment data and send it to the device
        // NOTE This function only sends the data, it does not tell the device
        // to update its setttings — use sendWiFiData() for that
        let tokenData:Data? = config.token.data(using: String.Encoding.utf8)
        let planData:Data? = config.planId!.data(using: String.Encoding.utf8)
        NSLog("Sending token (\(config.token)) and plan ID (\(config.planId!))")

        // Work through the characteristic list for the service, to match them
        // to known UUIDs so we send the correct data to the device

        // First the enrolment token
        for i in 0..<device.characteristics.count {
            let ch:CBCharacteristic? = device.characteristics[i];
            if ch != nil {
                if ch!.uuid.uuidString == TOKEN_SETTER_UUID {
                    if let td = tokenData {
                        // At the first GATT write (or read) iOS will handle pairing.
                        // If the user hits cancel, we will not be allowed to write, but if pairing succeeds,
                        // the following write will be made, and 'peripheral(_, didWriteValueFor, error)' called
                        device.peripheral.writeValue(td,
                                                     for:ch!,
                                                     type:CBCharacteristicWriteType.withResponse)
                        NSLog("Writing enrol token characteristic \(ch!.uuid.uuidString)")
                    }
                    break
                }
            }
        }

        // Now the plan ID
        for i in 0..<device.characteristics.count {
            let ch:CBCharacteristic? = device.characteristics[i];
            if ch != nil {
                if ch!.uuid.uuidString == PLANID_SETTER_UUID {
                    if let pd = planData {
                        device.peripheral.writeValue(pd,
                                                     for:ch!,
                                                     type:CBCharacteristicWriteType.withResponse)
                        NSLog("Writing plan ID characteristic \(ch!.uuid.uuidString)")
                    }
                    break
                }
            }
        }
    }

    
    func sendWiFiData(_ device: Device) {

        // Package up the WiFi configuration information and send it to the device
        // Get the data for the current network and prep for sending
        // NOTE This function also tells the device to update its setttings
        let index = self.wifiPicker.selectedRow(inComponent: 0)
        let network = self.availableNetworks[index]
        let ssidData:Data? = network[0].data(using: String.Encoding.utf8)
        let pwdData:Data? = self.passwordField.text!.data(using: String.Encoding.utf8)
        NSLog("Sending SSID (\(network[0])) and password (\(self.passwordField.text!))")
        
        // Work through the characteristic list for the service, to match them
        //  to known UUIDs so we send the correct data to the device
        for i in 0..<device.characteristics.count {
            // First the SSID
            let ch:CBCharacteristic? = device.characteristics[i]
            if ch != nil {
                // Write the SSID to the SSID_SETTER characteristic
                if ch!.uuid.uuidString == SSID_SETTER_UUID {
                    if let sd = ssidData {
                        // At the first GATT write (or read) iOS will handle pairing.
                        // If the user hits cancel, we will not be allowed to write, but if pairing succeeds,
                        // the following write will be made, and 'peripheral(_, didWriteValueFor, error)' called
                        device.peripheral.writeValue(sd,
                                                     for:ch!,
                                                     type:CBCharacteristicWriteType.withResponse)
                        NSLog("Writing SSID characteristic \(ch!.uuid.uuidString)")
                    }
                }

                // Write the password to the PASSWORD_SETTER characteristic
                if ch!.uuid.uuidString == PASSWORD_SETTER_UUID {
                    if let pd = pwdData {
                        device.peripheral.writeValue(pd,
                                                     for:ch!,
                                                     type:CBCharacteristicWriteType.withResponse)
                        NSLog("Writing password characteristic \(ch!.uuid.uuidString)")
                    }
                }
            }
        }

        // And finally the characteristic that triggers the WiFi refresh on the device
        // NOTE we do this in its own loop to avoid it being sent before the SSID and
        //      password values have been written
        for i in 0..<device.characteristics.count {
            let ch:CBCharacteristic? = device.characteristics[i];
            if ch != nil {
                if ch!.uuid.uuidString == BLINKUP_TRIGGER_UUID {
                    if let sd = ssidData {
                        device.peripheral.writeValue(sd,
                                                     for:ch!,
                                                     type:CBCharacteristicWriteType.withResponse)
                        NSLog("Writing 'set network' trigger characteristic \(ch!.uuid.uuidString)")
                    }
                }
            }
        }
    }

    
    @IBAction func clearWiFi(_ sender: Any) {

        // Already sending or connecting in order to clear? Then bail
        if self.isSending || self.isClearing { return }

        if self.cheatTimer != nil && self.cheatTimer.isValid { self.cheatTimer.fire() }

        self.blinkUpProgressBar.startAnimating()

        // Are we already connected to the device?
        if !self.connected {
            // App is not connected to the device, so connect now
            if let aDevice = self.device {
                self.isClearing = true

                self.bluetoothManager.connect(aDevice.peripheral,
                                              options: nil)
                // Pick up the action at didConnect(), which is called when the
                // iDevice has connected to the imp
                
                // Set up a timeout
                self.scanTimer = Timer.scheduledTimer(timeInterval: DEVICE_SCAN_TIMEOUT,
                                                      target: self,
                                                      selector: #selector(self.endConnectWithAlert),
                                                      userInfo: nil,
                                                      repeats: false)
            }
        } else {
            // App is already connected to the peripheral so send the clear WiFi signal
            clearWiFiStageTwo()
        }
    }

    
    func clearWiFiStageTwo() {

        self.isClearing = false
        self.isSending = true
        if self.scanTimer.isValid { self.scanTimer.invalidate() }

        if let aDevice = self.device {
            // Work through the characteristic list for the service, to match them
            //  to known UUIDs so we send the correct data to the device
            for i in 0..<aDevice.characteristics.count {
                let ch:CBCharacteristic? = aDevice.characteristics[i]
                if ch != nil {
                    if ch!.uuid.uuidString == WIFI_CLEAR_TRIGGER_UUID {
                        if let cd = "clear".data(using: String.Encoding.utf8) {
                            // At the first GATT write (or read) iOS will handle pairing.
                            // If the user hits cancel, we will not be allowed to write, but if pairing succeeds,
                            // the following write will be made, and 'peripheral(_, didWriteValueFor, error)' called
                            aDevice.peripheral.writeValue(cd,
                                                          for:ch!,
                                                          type:CBCharacteristicWriteType.withResponse)
                            NSLog("Writing 'Clear WiFi' trigger")

                            // Since we can't poll the server for this instance (we have no API key), we
                            // just warn the user via an alert to expect the device to connect
                            showAlert("imp WiFi Cleared", "Your imp’s WiFi credentials have been cleared")
                            
                            // Close the connection in CANCEL_TIME seconds' time
                            self.cheatTimer = Timer.scheduledTimer(withTimeInterval: self.CANCEL_TIME,
                                                                   repeats: false,
                                                                   block: { (_) in
                                if let aDevice = self.device {
                                    self.bluetoothManager.cancelPeripheralConnection(aDevice.peripheral)
                                    self.connected = false
                                }
                            })
                        }
                    }
                }
            }
        }

        // Clean up the UI
        self.sendLabel.text = ""
        self.isSending = false
        self.blinkUpProgressBar.stopAnimating()
    }

    
    func showWebview(_ agentURL: String) {
        
        // FROM 1.2.1
        // Refactor this code into a function
        let storyboard = UIStoryboard.init(name:"Main",
                                           bundle:nil)
        let awvc = storyboard.instantiateViewController(withIdentifier:"thewebview") as! AgentWebViewController
        awvc.agentURL = agentURL
        self.device!.agent = agentURL

        // Set up the left-hand nav bar button with an icon and text
        let button = UIButton(type: UIButton.ButtonType.system)
        button.setImage(UIImage(named: "icon_back"),
                        for: UIControl.State.normal)
        button.setTitle("Back", for: UIControl.State.normal)
        button.tintColor = UIColor.init(red: 1.0,
                                        green: 1.0,
                                        blue: 1.0,
                                        alpha: 1.0)
        button.sizeToFit()
        button.addTarget(awvc,
                         action: #selector(awvc.goBack),
                         for: UIControl.Event.touchUpInside)
        awvc.navigationItem.leftBarButtonItem = UIBarButtonItem(customView: button)
        
        // Show the web view
        self.isShowingWebview = true
        self.navigationController!.pushViewController(awvc,
                                                      animated: true)
    }
    
    
    // MARK: - Utility Functions

    func showAlert(_ title: String, _ message: String) {
        let alert = UIAlertController.init(title: title,
                                           message: message,
                                           preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"),
                                      style: .`default`,
                                      handler: nil))
        self.present(alert,
                     animated: true,
                     completion: nil)
    }
    
    
    func showDisconnectAlert(_ title: String, _ message: String) {
        let alert = UIAlertController.init(title: title,
                                           message: message,
                                           preferredStyle: UIAlertController.Style.alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Default action"),
                                      style: .`default`,
                                      handler: nil))
        self.present(alert,
                     animated: true) {
                        self.initUI()
                        self.initNetworks()
                        self.clearList = true }
    }

    
    @objc @IBAction func showPassword(_ sender: Any) {

        // Show or hide the password characters by flipping this flag
        passwordField.isSecureTextEntry = !passwordField.isSecureTextEntry
    }


    // MARK: - CBManagerDelegate Functions

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {

        // The app has connected to the peripheral (eg. imp004m)
        // This is the result of calling bluetoothManager.connect()
        // Cancel timeout timer
        if self.scanTimer != nil && self.scanTimer.isValid { self.scanTimer.invalidate() }

        // Update app state
        self.connected = true

        // We may have connected mid-operation, so take a path relevant to
        // that operation
        if self.isSending {
            // We are are connecting after calling doBlinkUp()
            // so proceed to the next step
            blinkupStageThree()
        } else if self.isClearing {
            // We are are connecting after calling clearWiFi()
            // so proceed to the next step
            clearWiFiStageTwo()
        } else {
            // Making an initial connection to get the WLAN list
            peripheral.discoverServices(nil)
            // Pick up the action at 'peripheral.didDiscoverServices()'
        }
    }

    
    func centralManager(_ central: CBCentralManager, didFailToConnect: CBPeripheral, error: Error?) {

        self.connected = false
        var deviceName: String = "Unknown"
        if let d = didFailToConnect.name { deviceName = d }

        if (error != nil) {
            NSLog("\(error!.localizedDescription) for device \(deviceName)")
            showDisconnectAlert("Could not connect to \"\(deviceName)\"", "Please go back to the devices list and re-select \"\(deviceName)\", if necessary performing a new scan")
        } else {
            NSLog("didFailToConnect() called for device \(deviceName)")
        }
    }

    
    func centralManager(_ central: CBCentralManager, didDisconnect: CBPeripheral, error: Error?) {

        self.connected = false
        var deviceName: String = "Unknown"
        if let d = didDisconnect.name { deviceName = d }

        if (error != nil) {
            NSLog("\(error!.localizedDescription) for device \(deviceName)")
        } else {
            NSLog("didDisconnect() called for device \(deviceName)")
        }
    }

    
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        // NOP
    }


    // MARK: - CBPeripheral Delegate functions

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {

        // The app has discovered services offered by the peripheral (ie. the imp)
        // This is the result of calling 'peripheral.discoverServices()'
        if error == nil {
            var got: Bool = false
            if let services = peripheral.services {
                for i in 0..<services.count {
                    let service: CBService = services[i]
                    if service.uuid.uuidString == BLINKUP_SERVICE_UUID {
                        // Ask the peripheral for a list of the all (hence 'nil') of the service's characteristics.
                        // This asynchronous call will be picked up by 'peripheral.didDiscoverCharacteristicsFor()'
                        peripheral.discoverCharacteristics(nil,
                                                           for: service)
                        got = true
                        break
                    }
                }

                if !got {
                    // Device is not serving corrrectly, so cancel the connection and warn the user
                    self.bluetoothManager.cancelPeripheralConnection(peripheral)
                    self.connected = false

                    // Update the UI to inform the user
                    self.blinkUpProgressBar.stopAnimating()
                    showAlert("Cannot Configure This Device", "This devices is not offering a BlinkUp service")
                }
            }
        } else {
            self.bluetoothManager.cancelPeripheralConnection(peripheral)
            self.connected = false
            
            var deviceName: String = "Unknown"
            if let d = peripheral.name { deviceName = d }

            // Log the error
            NSLog("\(error!.localizedDescription) for device \(deviceName)")

            // Update the UI to inform the user
            self.blinkUpProgressBar.stopAnimating()
        }
    }

    
    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,  error: Error?) {

        // The app has discovered the characteristics offered by the peripheral (ie. the imp004m) for
        // specific service. This is the result of calling 'peripheral.discoverCharacteristics()'
        if error == nil {
            // Save the list of characteristics
            if let list = service.characteristics {
                if let aDevice: Device = self.device {
                    aDevice.characteristics = list
                    // Run through the list of peripheral characteristics to see if it contains
                    // the imp application's networks list characteristic by looking for the
                    // characteristics's known UUID
                    for i in 0..<aDevice.characteristics.count {
                        let ch:CBCharacteristic? = aDevice.characteristics[i]
                        if ch != nil {
                            if ch!.uuid.uuidString == WIFI_GETTER_UUID {
                                // The peripheral DOES contain the expected characteristic,
                                // so read the characteristics value. When it has been read,
                                // 'peripheral.didUpdateValueFor()' will be called
                                aDevice.peripheral.readValue(for: ch!)
                                break
                            }
                        }
                    }
                }
            }
        } else {
            self.bluetoothManager.cancelPeripheralConnection(peripheral)
            self.connected = false

            // Log the error
            NSLog("\(error!.localizedDescription)")

            // Update the UI to inform the user
            self.blinkUpProgressBar.stopAnimating()
        }
    }

    
    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {

        // We have successfully read the imp application's networks list characteristic, so use
        // the value of the characteristic (a comma-separated string of network names) to populate
        // the 'availableNetworks' array and thus the UI's UIPickerView
        if characteristic.uuid.uuidString == WIFI_GETTER_UUID {
            if let data = characteristic.value {
                if data.count > 0 {
                    let networkList:String? = String.init(data: data,
                                                          encoding: String.Encoding.utf8)
                    if networkList != nil {
                        // Convert to NSString from Swift's String so we can create an
                        // array from the comma-separated network names in the string
                        var nl: NSString = networkList! as NSString
                        let networks = nl.components(separatedBy: "\n\n")

                        // Is there only one nearby network? Then check that it is not the
                        // imp004m application signalling NO nearby networks
                        if networks.count == 1 {
                            if networks[0] == "!no_local_networks!" || networks[0] == "" {
                                // Reset 'availableNetworks' and the UIPickerView
                                initNetworks()

                                // Hide the progress indicator
                                self.bluetoothManager.cancelPeripheralConnection(peripheral)
                                self.connected = false
                                self.sendLabel.text = "No nearby networks to connect to"
                                self.blinkUpProgressBar.stopAnimating()
                                return
                            }
                        }

                        // We have at least one valid network name, so populate the picker
                        self.availableNetworks.removeAll()

                        for i in 0..<networks.count {
                            nl = networks[i] as NSString
                            let parts = nl.components(separatedBy: "\n")
                            var network: [String] = []
                            network.append(parts[0].isEmpty ? "[Hidden]" : parts[0])
                            network.append(parts[1])
                            self.availableNetworks.append(network)
                        }

                        // Update the UIPickerView
                        self.wifiPicker.reloadAllComponents()
                        self.wifiPicker.isUserInteractionEnabled = true
                        wifiPicker.alpha = 1
                    }
                } else {
                    peripheral.readValue(for: characteristic)
                }
            }
            
            // Hide the progress indicator
            self.bluetoothManager.cancelPeripheralConnection(peripheral)
            self.connected = false
            self.blinkUpProgressBar.stopAnimating()

        } else {
            NSLog("didUpdateValueFor() called for characteristic \(characteristic.uuid.uuidString)")
        }
    }

    
    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {

        // This will be called when a value is written to the peripheral via GATT
        // The first time a write is made, iOS will manage the pairing. Only if the pairing
        // succeeds will this delegate method be called (because if pairing fails, no value
        // will be written the delegate will not be called).
        if error != nil {
            NSLog("Could not write characteristic \(characteristic.uuid.uuidString)")
        } else {
            NSLog("didDisconnect() called for characteristic \(characteristic.uuid.uuidString)")
        }
    }


    // MARK: - UIPickerView Delegate and Data Source Functions

    func numberOfComponents(in pickerView: UIPickerView) -> Int {

        // There is only one component in this picker
        return 1;
    }

    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {

        // Return the number of entries in the 'availableNetworks' array
        return self.availableNetworks.count;
    }

    
    func pickerView(_ pickerView: UIPickerView, rowHeightForComponent component: Int) -> CGFloat {

        return 28
    }

    
    func pickerView(_ pickerView: UIPickerView, viewForRow row: Int, forComponent component: Int, reusing view: UIView?) -> UIView {

        // Return the element from 'availableNetworks' whose index matches 'row'
        let network = self.availableNetworks[row]

        let rowView = UIView(frame: CGRect.init(x: 0,
                                                y: 0,
                                                width: pickerView.bounds.width,
                                                height: 28))

        let rowLabel = UILabel(frame: CGRect.init(x: 20,
                                                  y: 2,
                                                  width: pickerView.bounds.width - 60,
                                                  height: 26))
        rowLabel.lineBreakMode = NSLineBreakMode.byTruncatingTail
        rowLabel.text = network[0]

        let rowImageView = UIImageView(frame: CGRect.init(x: pickerView.bounds.width - 40,
                                                          y: 4,
                                                          width: 20,
                                                          height: 20))
        if network[1] == "locked" { rowImageView.image = UIImage(named:"lock") }

        rowView.addSubview(rowLabel)
        rowView.addSubview(rowImageView)

        return rowView
    }


    // MARK: - UITextField Delegate Functions

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {

        for item in self.view.subviews {
            let view = item as UIView
            if view.isKind(of: UITextField.self) { view.resignFirstResponder() }
        }
    }

    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {

        textField.resignFirstResponder()
        return true
    }

}
