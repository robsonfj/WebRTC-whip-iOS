//
//  ViewController.swift
//  WebRTC
//
//  Created by Stasel on 20/05/2018.
//  Copyright © 2018 Stasel. All rights reserved.
//

import UIKit
import AVFoundation
import WebRTC

class MainViewController: UIViewController {
    private let whipClient = WHIPClient()
    
    private let videoCapturer = VideoCapturer()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    private let defaultEndpoint = "https://api.souv.dev/live/whip/00om5yyz8lhf40rhnsbjih797q/0qgnz7w10uyc50mmxokqssw9kl?auth=31tnz92fb1tg00puwxpa3297gx2un4fpii0sfat2po3k9tvwof2b"
    
    private let bitrates = [
        "20Mbps":20_000_000,
        "16Mbps":16_000_000,
        "14Mbps":14_000_000,
        "12Mbps":12_000_000,
        "10Mbps":10_000_000,
        "8Mbps":8_000_000,
        "6Mbps":6_000_000,
        "4Mbps":4_000_000,
        "2Mbps":2_000_000,
        "1Mbps":1_000_000,
        "400Kbps":400_000,
    ]
    
    @IBOutlet weak var cameraButton: UIButton!
    @IBOutlet weak var codecButton: UIButton!
    @IBOutlet weak var modeButton: UIButton!
    @IBOutlet weak var bitrateButton: UIButton!
    @IBOutlet weak var urlInput: UITextField!
    @IBOutlet weak var qualitySegment: UISegmentedControl!
    @IBOutlet weak var fpsSegment: UISegmentedControl!
    @IBOutlet private weak var stabilizationButton: UIButton?
    @IBOutlet private weak var signalingStatusLabel: UILabel?
    @IBOutlet private weak var localSdpStatusLabel: UILabel?
    @IBOutlet private weak var remoteSdpStatusLabel: UILabel?
    @IBOutlet weak var startButton: UIButton!
    @IBOutlet private weak var muteButton: UIButton?
    @IBOutlet private weak var webRTCStatusLabel: UILabel?
    
    private var videoDevice: AVCaptureDevice? {
        didSet {
            if let device = videoDevice {
                DispatchQueue.main.async {
                    self.cameraButton.setTitle(
                        device.localizedName,
                        for: .normal
                    )
                }
            }
        }
    }
    
    private var videoCodec: String = kRTCVideoCodecH264Name {
        didSet {
            DispatchQueue.main.async {
                self.codecButton.setTitle(
                    self.videoCodec,
                    for: .normal
                )
            }
            
        }
    }
    
    private var liveMode: String = "calls" {
        didSet {
            DispatchQueue.main.async {
                self.modeButton.setTitle(
                    self.liveMode,
                    for: .normal
                )
            }
        }
    }
    
    private var liveBitrate: Int = 10_000_000 {
        didSet {
            guard let label = bitrates.first(where: { (key: String, value: Int) in
                return value == liveBitrate
            })?.key else { return }
            
            DispatchQueue.main.async {
                self.bitrateButton.setTitle(label,
                    for: .normal
                )
            }
        }
    }
    
    private var started: Bool = false {
        didSet {
            // Stop screen auto lock
            UIApplication.shared.isIdleTimerDisabled = self.started
            
            DispatchQueue.main.async {
                let title = self.started ? "Stop": "Start"
                let color: UIColor = self.started ? .systemRed : .systemBlue
                self.startButton.setTitle(
                    title,
                    for: .normal
                )
                self.startButton.backgroundColor = color
            }
        }
    }
    
    
    
    private var framerate: Int32 = 30 {
        didSet {
            var idx = 0
            switch self.framerate {
                case 24:
                    idx = 0
                case 30:
                    idx = 1
                case 60:
                    idx = 2
                case 120:
                    idx = 3
                default:
                    idx = 0
            }
            DispatchQueue.main.async {
                self.fpsSegment?.selectedSegmentIndex = idx
            }
        }
    }
    
    private var quality: Int32 = 1080 {
        didSet {
            var idx = 0
            switch self.quality {
                case 720:
                    idx = 0
                case 1080:
                    idx = 1
                case 2160:
                    idx = 2
                default:
                    idx = 0
            }
            
            DispatchQueue.main.async {
                self.qualitySegment?.selectedSegmentIndex = idx
            }
        }
    }
    
    
    private var hasLocalSdp: Bool = false {
        didSet {
            DispatchQueue.main.async {                
                self.localSdpStatusLabel?.text = self.hasLocalSdp ? "✅" : "❌"
            }
        }
    }
    
    private var hasRemoteSdp: Bool = false {
        didSet {
            DispatchQueue.main.async {
                self.remoteSdpStatusLabel?.text = self.hasRemoteSdp ? "✅" : "❌"
            }
        }
    }
    
    private var connectionState: RTCPeerConnectionState = .new {
        didSet {
            var text = ""
            
            switch connectionState {
            case .new:
                text = "New"
            case .connected:
                text = "Connected"
            case .connecting:
                text = "Connecting"
            case .closed:
                text = "Closed"
            case .disconnected:
                text = "Disconnected"
            case .failed:
                text = "Failed"
            default:
                break
            }
            
            
           DispatchQueue.main.async {
               self.webRTCStatusLabel?.text = text
           }
        }
    }
    
    private var stabilization: AVCaptureVideoStabilizationMode = .off {
        didSet {
            var label = "off"
            
            switch self.stabilization {
            case .off:
                label = "Off"
            case .standard:
                label = "Normal"
            case .cinematic:
                label = "Cinematico"
            case .cinematicExtended:
                label = "Cinematico Ext"
            case .auto:
                label = "Auto"
            case .previewOptimized:
                label = "Preview"
            @unknown default:
                label = "Off"
            }
            
            let title = "Stabilization: \(label)"
            
            DispatchQueue.main.async {
                self.stabilizationButton?.setTitle(
                    title,
                    for: .normal
                )
            }
        }
    }
    
    private var mute: Bool = false {
        didSet {
            let title = "Mute: \(self.mute ? "on" : "off")"
            
            DispatchQueue.main.async {
                self.muteButton?.setTitle(
                    title,
                    for: .normal
                )
            }
        }
    }
    
    init() {
        super.init(
            nibName: String(
                describing: MainViewController.self
            ),
            bundle: Bundle.main
        )
        
        self.whipClient.delegate = self
    }
    
    @available(
        *,
         unavailable
    )
    required init?(
        coder aDecoder: NSCoder
    ) {
        fatalError(
            "init(coder:) has not been implemented"
        )
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationController?.setNavigationBarHidden(
            true,
            animated: false
        )
        
        self.hasLocalSdp = false
        self.hasRemoteSdp = false
        self.connectionState = .new
        self.signalingStatusLabel?.text = "new"
        self.urlInput.text = self.defaultEndpoint
        self.liveMode = "calls"
        self.videoCodec = kRTCVideoCodecH264Name
        self.quality = 1080
        self.framerate = 30
        self.stabilization = .cinematicExtended
        
        self.videoDevice = AVCaptureDevice.default(
            for: .video
        )
        
        updateCamera()
        
        // Set webrtc video source
        self.videoCapturer.setVideoSource(
            source: self.whipClient.videoSource
        )
        //
        
        // Add preview layer
        let session = self.videoCapturer.captureSession
        let preview = AVCaptureVideoPreviewLayer(
            session: session
        )
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.insertSublayer(
            preview,
            at: 0
        ) // Set as background
        
        previewLayer = preview
        //
        
        let tapGesture = UITapGestureRecognizer(
            target: self,
            action: #selector(
                dismissKeyboard
            )
        )
        view.addGestureRecognizer(
            tapGesture
        )
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Ensure previewLayer adjusts on rotation
        previewLayer?.frame = view.bounds
    }
    
    @objc func dismissKeyboard() {
        view.endEditing(
            true
        )
    }
    
    private func updateCamera(){
        if let device = self.videoDevice {
            self.videoCapturer.setupAndCapture(
                device: device,
                height: self.quality,
                fps: self.framerate,
                stabilization: self.stabilization
            )
        }    }
    
    @IBAction func cameraTap(
        _ sender: UIButton
    ) {
        let devices = self.videoCapturer.videoDevices()
        
        let alert = UIAlertController(
            title: "Select Camera",
            message: nil,
            preferredStyle: .actionSheet
        )
        
        
        for device in devices {
            alert.addAction(
                UIAlertAction(title: device.localizedName,
                              style: .default,
                              handler: {
                                  _ in
                                  self.videoDevice = device
                                  self.updateCamera()
                              })
            )
        }
        
        
        alert.addAction(
            UIAlertAction(
                title: "Cancel",
                style: .cancel,
                handler: nil
            )
        )
        
        // For iPad support
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        
        present(
            alert,
            animated: true
        )
    }
    
    
    @IBAction func codecTap(
        _ sender: UIButton
    ) {
        let alert = UIAlertController(
            title: "Select Codec",
            message: nil,
            preferredStyle: .actionSheet
        )
        
        let codecs = [
            kRTCVideoCodecH264Name,
            kRTCVideoCodecVp8Name,
            kRTCVideoCodecVp9Name,
            kRTCVideoCodecAv1Name
        ]
        for codec in codecs {
            alert.addAction(
                UIAlertAction(title: codec,
                              style: .default,
                              handler: {
                                  _ in
                                  self.videoCodec = codec
                                  self.whipClient.setCodec(codec)
                              })
            )
        }
        
        
        alert.addAction(
            UIAlertAction(
                title: "Cancel",
                style: .cancel,
                handler: nil
            )
        )
        
        // For iPad support
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        
        present(
            alert,
            animated: true
        )
    }
    
    @IBAction func modeTap(
        _ sender: UIButton
    ) {
        let alert = UIAlertController(
            title: "Select Mode",
            message: nil,
            preferredStyle: .actionSheet
        )
        
        let modes = [
            "p2p",
            "calls"
        ]
        
        for mode in modes {
            alert.addAction(
                UIAlertAction(title: mode,
                              style: .default,
                              handler: {
                                  _ in
                                  self.liveMode = mode
                                  self.whipClient.setMode(mode)
                              })
            )
        }
        
        
        alert.addAction(
            UIAlertAction(
                title: "Cancel",
                style: .cancel,
                handler: nil
            )
        )
        
        // For iPad support
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        
        present(
            alert,
            animated: true
        )
    }
    
    @IBAction func bitrateTap(
        _ sender: UIButton
    ) {
        let alert = UIAlertController(
            title: "Select Bitrate",
            message: nil,
            preferredStyle: .actionSheet
        )
        
        let sorted = bitrates.sorted { a, b in
            return a.value > b.value
        }
        
        for bitrate in sorted {
            alert.addAction(
                UIAlertAction(title: bitrate.key,
                              style: .default,
                              handler: {
                                  _ in
                                  self.liveBitrate = bitrate.value
                                  self.whipClient.setBitrate(bitrate.value)
                              })
            )
        }
        
        
        alert.addAction(
            UIAlertAction(
                title: "Cancel",
                style: .cancel,
                handler: nil
            )
        )
        
        // For iPad support
        if let popover = alert.popoverPresentationController {
            popover.sourceView = sender
            popover.sourceRect = sender.bounds
        }
        
        present(
            alert,
            animated: true
        )
    }
    
    @IBAction func qualityChanged(
        _ sender: UISegmentedControl
    ) {
        let idx = sender.selectedSegmentIndex
        
        switch idx {
            case 0:
                self.quality = 720
            case 1:
                self.quality = 1080
            case 2:
                self.quality = 2160
            default:
                self.quality = 1080
        }
        
        updateCamera()
    }
    
    @IBAction func fpsChanged(
        _ sender: UISegmentedControl
    ) {
        let idx = sender.selectedSegmentIndex
        
        switch idx {
            case 0:
                self.framerate = 24
            case 1:
                self.framerate = 30
            case 2:
                self.framerate = 60
            case 3:
                self.framerate = 120
            default:
                self.framerate = 30
        }
        
        updateCamera()
    }
    
    @IBAction func textUnfocus(
        _ sender: UITextField
    ) {
        sender.resignFirstResponder()
    }
    
    @IBAction private func startDidTap(
        _ sender: UIButton
    ) {
        self.hasRemoteSdp = false
        self.signalingStatusLabel?.text = "new"
        self.webRTCStatusLabel?.text = "new"
        
        if(
            self.started
        ){
            self.whipClient.stop()
            
            
            self.started = false
        } else{
            self.hasLocalSdp = false
            
            let endpoint = self.urlInput.text ?? String()
            
            self.whipClient.start(
                endpoint: endpoint
            )
            self.started = true
        }
    }
    
    @IBAction private func stabilizationDidTap(
        _ sender: UIButton
    ) {
        var newValue = self.stabilization
        
        switch self.stabilization {
        case .off:
            newValue = .standard
        case .standard:
            newValue = .cinematic
        case .cinematic:
            if #available(
                iOS 13.0,
                *
            ) {
                newValue = .cinematicExtended
            } else {
                newValue = .off
            }
        case .cinematicExtended, .auto, .previewOptimized:
            newValue = .off
        @unknown default:
            newValue = .off
        }
        
        
        self.stabilization = newValue
        
        updateCamera()
    }
    
    @IBAction private func muteDidTap(
        _ sender: UIButton
    ) {
        self.mute = !self.mute
        self.whipClient.setAudio(
            muted: self.mute
        )
    }
    
}

extension MainViewController: WHIPClientDelegate {
    func whipClient(
        _ client: WHIPClient,
        didChangeSignalingState state: RTCSignalingState
    ) {
        DispatchQueue.main.async {
            self.signalingStatusLabel?.text = state.stringValue
        }
    }
    
    func whipClient(
        _ client: WHIPClient,
        didCreateOffer error: Error?
    ) {
        self.hasLocalSdp = true
    }
    
    func whipClient(
        _ client: WHIPClient,
        didReceiveAnswer error: Error?
    ) {
        self.hasRemoteSdp = true
    }
    
    func whipClient(
        _ client: WHIPClient,
        didChangeConnectionState state: RTCPeerConnectionState
    ) {
        self.connectionState = state
    }
    
}

