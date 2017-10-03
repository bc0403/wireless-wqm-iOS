//
//  SerialViewController.swift
//  HM10 Serial
//
//  Created by Alex on 10-08-15.
//  Copyright (c) 2015 Balancing Rock. All rights reserved.
//

import UIKit
import CoreBluetooth
import QuartzCore
import Charts // You need this line to be able to use Charts Library

/// The option to add a \n or \r or \r\n to the end of the send message
enum MessageOption: Int {
    case noLineEnding,
         newline,
         carriageReturn,
         carriageReturnAndNewline
}

/// The option to add a \n to the end of the received message (to make it more readable)
enum ReceivedMessageOption: Int {
    case none,
         newline
}

final class SerialViewController: UIViewController, UITextFieldDelegate, BluetoothSerialDelegate {

//MARK: IBOutlets
    
    @IBOutlet weak var mainTextView: UITextView!
    @IBOutlet weak var messageField: UITextField!
    @IBOutlet weak var bottomView: UIView!
    @IBOutlet weak var bottomConstraint: NSLayoutConstraint! // used to move the textField up when the keyboard is present
    @IBOutlet weak var barButton: UIBarButtonItem!
    @IBOutlet weak var navItem: UINavigationItem!
    @IBOutlet weak var parameter1: UILabel!
    @IBOutlet weak var label1a: UILabel!
    @IBOutlet weak var label1b: UILabel!
    @IBOutlet weak var parameter2: UILabel!
    @IBOutlet weak var label2a: UILabel!
    @IBOutlet weak var label2b: UILabel!
    @IBOutlet weak var parameter3: UILabel!
    @IBOutlet weak var label3a: UILabel!
    @IBOutlet weak var label3b: UILabel!
//    @IBOutlet weak var phPlotView: LineChartView!
    @IBOutlet weak var phPlotView: LineChartView!
    @IBOutlet weak var clPlotView: LineChartView!
    
    
    //MARK: Global variables
    var value1a : Double = 0.0 // Temperature
    var value1b : Double = 0.0 // reserved
    var value2a : Double = 0.0 // pH
    var value2b : Double = 0.0 // pH in Voltage
    var value3a : Double = 0.0 // free Cl in ppm
    var value3b : Double = 0.0 // free Cl in nA
    var fullString = "" // for message received from BLE
    var fullStringFlag = 0 // flag for fullString, 0-partly; 1-full
    var cal_pH7 = -52.02 // offset voltage at pH7, mV
    var cal_pH4 = 129.36 // pH voltage at pH4, mV
    var cal_pH10 = -220.64 // pH voltage at pH10, mV
    var cal_temp = 296.45 // calibration at this temperature, K
    var feedbackResistor = 820.0e3 // feedback resistor of TIA, 320 kohm
    var offsetCurrentCl = 109.6 // offset current when there are no NaOCl, nA
    
    //MARK: plot data
    var numbersPH : [Double] = [] //This is where we are going to store all the numbers. This can be a set of numbers that come from a Realm database, Core data, External API's or where ever else
    var numbersCl : [Double] = []

//MARK: Functions (evaluate values of parameters)

    func evaluateParameters() {
        
    }

//MARK: Functions
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // init serial
        serial = BluetoothSerial(delegate: self)
        
        // UI
        mainTextView.text = ""
        parameter1.text = "Temperature: "
        parameter2.text = "pH: "
        parameter3.text = "free Cl: "
        label1a.text = "" // temperature in ℃
        label1b.text = "" // reserved
        label2a.text = "" // pH
        label2b.text = "" // pH, mV
        label3a.text = "" // free Cl, ppm
        label3b.text = "" // free Cl, nA
        reloadView()
        
        NotificationCenter.default.addObserver(self, selector: #selector(SerialViewController.reloadView), name: NSNotification.Name(rawValue: "reloadStartViewController"), object: nil)
        
        // we want to be notified when the keyboard is shown (so we can move the textField up)
        NotificationCenter.default.addObserver(self, selector: #selector(SerialViewController.keyboardWillShow(_:)), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(SerialViewController.keyboardWillHide(_:)), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
        
        // to dismiss the keyboard if the user taps outside the textField while editing
        let tap = UITapGestureRecognizer(target: self, action: #selector(SerialViewController.dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
        
        // style the bottom UIView
        bottomView.layer.masksToBounds = false
        bottomView.layer.shadowOffset = CGSize(width: 0, height: -1)
        bottomView.layer.shadowRadius = 0
        bottomView.layer.shadowOpacity = 0.5
        bottomView.layer.shadowColor = UIColor.gray.cgColor
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func keyboardWillShow(_ notification: Notification) {
        // animate the text field to stay above the keyboard
        var info = (notification as NSNotification).userInfo!
        let value = info[UIKeyboardFrameEndUserInfoKey] as! NSValue
        let keyboardFrame = value.cgRectValue
        
        //TODO: Not animating properly
        UIView.animate(withDuration: 1, delay: 0, options: UIViewAnimationOptions(), animations: { () -> Void in
            self.bottomConstraint.constant = keyboardFrame.size.height
            }, completion: { Bool -> Void in
            self.textViewScrollToBottom()
        })
    }
    
    func keyboardWillHide(_ notification: Notification) {
        // bring the text field back down..
        UIView.animate(withDuration: 1, delay: 0, options: UIViewAnimationOptions(), animations: { () -> Void in
            self.bottomConstraint.constant = 0
        }, completion: nil)

    }
    
    func reloadView() {
        // in case we're the visible view again
        serial.delegate = self
        
        if serial.isReady {
//            navItem.title = serial.connectedPeripheral!.name
            navItem.title = "Water Quality Monitor"
            barButton.title = "Disconnect"
            barButton.tintColor = UIColor.red
            barButton.isEnabled = true
        } else if serial.centralManager.state == .poweredOn {
            navItem.title = "Water Quality Monitor"
            barButton.title = "Connect"
            barButton.tintColor = view.tintColor
            barButton.isEnabled = true
        } else {
            navItem.title = "Water Quality Monitor"
            barButton.title = "Connect"
            barButton.tintColor = view.tintColor
            barButton.isEnabled = false
        }
    }
    
    func textViewScrollToBottom() {
        let range = NSMakeRange(NSString(string: mainTextView.text).length - 1, 1)
        mainTextView.scrollRangeToVisible(range)
    }
    

//MARK: BluetoothSerialDelegate
    
    func serialDidReceiveString(_ message: String) {
        // add the received text to the textView, optionally with a line break at the end
        mainTextView.text! += message
        
        // update values of parameters, hjin
        if !message.hasSuffix("\n") {
            fullString = message
            fullStringFlag = 0
        } else {
            fullString += message
            fullStringFlag = 1
        }
        print(fullStringFlag)
        print(fullString)
        if fullStringFlag == 1 {
            var fullStringArray = fullString.split(separator: " ")
            if fullStringArray.count == 5 {
                let data0 = (fullStringArray[0] as NSString).doubleValue // temperature in ℃
                let data1 = (fullStringArray[1] as NSString).doubleValue // voltage of RE
                let data2 = (fullStringArray[2] as NSString).doubleValue // voltage of WE (free Cl)
                let data3 = (fullStringArray[3] as NSString).doubleValue // voltage of WE (pH)
                print(data0, data1, data2, data3)
                
                // evaluate temperature
                value1a = data0
                label1a.text = String(value1a) + " ℃"
                label1b.text = ""
                
                // evaluate pH
                value2b = data3 - data1 // voltage of pH (WE_pH - RE), mV
                label2b.text = String(format: "%.1f", value2b) + " mV"
                let delta_mv = value2b - cal_pH7/cal_temp*(value1a+273.15)
                if delta_mv > 0 { //acid
                    value2a = 7 - delta_mv/((cal_pH4 - cal_pH7)/3/cal_temp*(value1a+273.15))
                } else { // alkaline
                    value2a = 7 - delta_mv/((cal_pH7 - cal_pH10)/3/cal_temp*(value1a+273.15))
                }
                if value2a <= 0 {
                    value2a = 0
                } else if value2a >= 14 {
                    value2a = 14
                }
                label2a.text = String(format: "%.2f", value2a)

                // evaluate free Cl
                value3b = (data1 - data2)/feedbackResistor*1.0e6 // current of free Cl, nA
                let cl_ppm_part1 = 0.57*(value3b - offsetCurrentCl)/(342+(value1a-27)*9.3)
                let cl_ppm_part2a = value2a - (3000/(value1a+273.15)-10.0686+0.0253*(value1a+273.15))
                let cl_ppm_part2 = 1 + pow(10, cl_ppm_part2a)
                value3a = cl_ppm_part1*cl_ppm_part2
                if value3a <= 0 {
                    value3a = 0
                }
                label3a.text = String(format: "%.2f", value3a) + " ppm"
                label3b.text = String(format: "%.1f", value3b) + " nA"
                
                // plot
                numbersPH.append(value2b) //here we add the data to the array.
                numbersCl.append(value3b)
                updateGraph()
                
                
            }
        }
        

        
        
        let pref = UserDefaults.standard.integer(forKey: ReceivedMessageOptionKey)
        if pref == ReceivedMessageOption.newline.rawValue { mainTextView.text! += "\n" }
        textViewScrollToBottom()
    }
    
    //MARK: update plots
    func updateGraph(){
        
        var lineChartEntryPH  = [ChartDataEntry]() //this is the Array that will eventually be displayed on the graph.
        var lineChartEntryCl  = [ChartDataEntry]()
        
        //here is the for loop
        for i in 0..<numbersPH.count {
            let value = ChartDataEntry(x: Double(i), y: numbersPH[i]) // here we set the X and Y status in a data chart entry
            lineChartEntryPH.append(value) // here we add it to the data set
        }
        for i in 0..<numbersCl.count {
            let value = ChartDataEntry(x: Double(i), y: numbersCl[i]) // here we set the X and Y status in a data chart entry
            lineChartEntryCl.append(value) // here we add it to the data set
        }
        
        let linePH = LineChartDataSet(values: lineChartEntryPH, label: "pH, mV") //Here we convert lineChartEntry to a LineChartDataSet
        let lineCl = LineChartDataSet(values: lineChartEntryCl, label: "free Cl, nA")
        
        linePH.colors = [NSUIColor.blue] //Sets the colour to blue
        lineCl.colors = [NSUIColor.red]
        
        let dataPH = LineChartData() //This is the object that will be added to the chart
        let dataCl = LineChartData()
        dataPH.addDataSet(linePH) //Adds the line to the dataSet
        dataCl.addDataSet(lineCl)
        
        phPlotView.data = dataPH //finally - it adds the chart data to the chart and causes an update
        clPlotView.data = dataCl
        phPlotView.chartDescription?.text = "" // Here we set the description for the graph
        clPlotView.chartDescription?.text = ""
    }
    
    
    func serialDidDisconnect(_ peripheral: CBPeripheral, error: NSError?) {
        reloadView()
        dismissKeyboard()
        let hud = MBProgressHUD.showAdded(to: view, animated: true)
        hud?.mode = MBProgressHUDMode.text
        hud?.labelText = "Disconnected"
        hud?.hide(true, afterDelay: 1.0)
    }
    
    func serialDidChangeState() {
        reloadView()
        if serial.centralManager.state != .poweredOn {
            dismissKeyboard()
            let hud = MBProgressHUD.showAdded(to: view, animated: true)
            hud?.mode = MBProgressHUDMode.text
            hud?.labelText = "Bluetooth turned off"
            hud?.hide(true, afterDelay: 1.0)
        }
    }
    
    
//MARK: UITextFieldDelegate
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if !serial.isReady {
            let alert = UIAlertController(title: "Not connected", message: "What am I supposed to send this to?", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Dismiss", style: UIAlertActionStyle.default, handler: { action -> Void in self.dismiss(animated: true, completion: nil) }))
            present(alert, animated: true, completion: nil)
            messageField.resignFirstResponder()
            return true
        }
        
        // send the message to the bluetooth device
        // but fist, add optionally a line break or carriage return (or both) to the message
        let pref = UserDefaults.standard.integer(forKey: MessageOptionKey)
        var msg = messageField.text!
        switch pref {
        case MessageOption.newline.rawValue:
            msg += "\n"
        case MessageOption.carriageReturn.rawValue:
            msg += "\r"
        case MessageOption.carriageReturnAndNewline.rawValue:
            msg += "\r\n"
        default:
            msg += ""
        }
        
        // send the message and clear the textfield
        serial.sendMessageToDevice(msg)
        messageField.text = ""
        return true
    }
    
    func dismissKeyboard() {
        messageField.resignFirstResponder()
    }
    
    
//MARK: IBActions
    
    @IBAction func barButtonPressed(_ sender: AnyObject) {
        if serial.connectedPeripheral == nil {
            performSegue(withIdentifier: "ShowScanner", sender: self)
        } else {
            serial.disconnect()
            reloadView()
        }
    }
}
