//
//  VideoCapturer.swift
//  WebRTC-Demo
//
//  Created by Robson Ferreira Jacomini on 21/07/25.
//  Copyright © 2025 Stas Seldin. All rights reserved.
//

import AVFoundation
import WebRTC

class AVCapturer: NSObject, AVCaptureDataOutputSynchronizerDelegate {
        
    private let videoCapturer = RTCVideoCapturer()
    
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    
    private var videoSource: RTCVideoSource?
    private var audioSource: AudioDevice?
    
    private var videoOutput = AVCaptureVideoDataOutput()
    private var audioOutput = AVCaptureAudioDataOutput()
    
    private let audioSession = AVAudioSession.sharedInstance()
    
    let captureSession = AVCaptureSession()
    
    
    override init() {
        super.init()
        
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) {
            _ in
            self.updateVideoOrientation()
        }
        
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { notification in
            print(
                "🎧 Audio route changed:"
            )
            if let inputs = AVAudioSession.sharedInstance().availableInputs {
                for input in inputs {
                    print(
                        "Updated input: \(input.portName) - \(input.portType.rawValue)"
                    )
                }
            }
        }
    }
    
    
    private func applySettings(
        device: AVCaptureDevice,
        height: Int32,
        fps: Int32,
        stabilization: AVCaptureVideoStabilizationMode
    ) throws {
        let sortedFormats = device.formats.sorted {
            a,
            b in
            let aDims = CMVideoFormatDescriptionGetDimensions(
                a.formatDescription
            )
            let bDims = CMVideoFormatDescriptionGetDimensions(
                b.formatDescription
            )
            return aDims.height > bDims.height
        }
        
        guard let format = sortedFormats.first(where: {
            format in
            let dims = CMVideoFormatDescriptionGetDimensions(
                format.formatDescription
            )
            
            let fpsSupported = format.videoSupportedFrameRateRanges.contains {
                Int32(
                    $0.maxFrameRate
                ) >= fps
            }
            
            var stabilizationSupport = true
            if (
                stabilization != .off
            ){
                stabilizationSupport = format.isVideoStabilizationModeSupported(
                    stabilization
                )
            }
            
            
            return dims.height == height && fpsSupported && stabilizationSupport
        }) else {
            return
        }
        
        
        let duration = CMTime(
            value: 1,
            timescale: fps
        )
        
        try device.lockForConfiguration()
        
        device.activeFormat = format
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        
        device.focusMode = .continuousAutoFocus
        device.exposureMode = .continuousAutoExposure
        
        print(
            "Duration",
            device.exposureDuration
        )
        print(
            "Aperture",
            device.lensAperture
        )
        
        device.unlockForConfiguration()
        
    }
    
    func videoDevices() -> [AVCaptureDevice] {
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInWideAngleCamera,
                .builtInTelephotoCamera,
                .builtInUltraWideCamera,
                .builtInDualCamera,
                .builtInTripleCamera,
                .builtInDualWideCamera,
                .builtInTrueDepthCamera,
            ],
            mediaType: .video,
            position: .unspecified
        ).devices
    }
    
    func audioInputs() -> [AVAudioSessionPortDescription] {
       return audioSession.availableInputs ?? []
   }
    
    func setVideoSource(
        source: RTCVideoSource
    ){
        self.videoSource = source
    }
    
    func setAudioDevice(device: AudioDevice) {
        self.audioSource = device
    }
    
    func updateVideoOrientation() {
        guard let connection = videoOutput.connection(
            with: .video
        ) else {
            return
        }
        
        let orientation = UIDevice.current.orientation
        
        if #available(
            iOS 17.0,
            *
        ) {
            switch orientation {
            case .portrait:
                connection.videoRotationAngle = 90
            case .portraitUpsideDown:
                connection.videoRotationAngle = 270
            case .landscapeLeft:
                connection.videoRotationAngle = 0
            case .landscapeRight:
                connection.videoRotationAngle = 180
            default:
                connection.videoRotationAngle = 90
            }
            
        } else {
            switch orientation {
            case .portrait:
                connection.videoOrientation = .portrait
            case .portraitUpsideDown:
                connection.videoOrientation = .portraitUpsideDown
            case .landscapeLeft:
                connection.videoOrientation = .landscapeLeft
            case .landscapeRight:
                connection.videoOrientation = .landscapeRight
            default:
                connection.videoOrientation = .portrait
            }
            
        }
    }
    
    func setAudioInputToBluetoothOrUSB() {
            
            do {
                // 1. Set category
                try audioSession.setCategory(
                    .playAndRecord,
                    mode: .videoChat,
                    options: [.defaultToSpeaker]
                )
                
                // 3. List available audio inputs
                let availableInputs = audioInputs()
                let availableModes = audioSession.outputDataSources ?? []
                
                for inpt in availableModes {
                    print(
                        "out \(inpt.dataSourceName)"
                    )
                }
                for inpt in availableInputs {
                    print(
                        "Input \(inpt.portName)"
                    )
                }
                
                //            try audioSession.setAggregatedIOPreference(.aggregated)
                //            // 4. Select desired input (Bluetooth HFP, USB, etc.)
                //            if let preferredInput = availableInputs.first(where: { $0.portType == .bluetoothHFP }) {
                //                try audioSession.setPreferredInput(preferredInput)
                //                print("Bluetooth input selected: \(preferredInput.portName)")
                //            } else if let usbInput = availableInputs.first(where: { $0.portType == .usbAudio }) {
                //                try audioSession.setPreferredInput(usbInput)
                //                print("USB input selected: \(usbInput.portName)")
                //            } else if let builtInMic = availableInputs.first(where: { $0.portType == .builtInSpeaker }) {
                //                try audioSession.setPreferredInput(builtInMic)
                //                print("Defaulting to built-in mic")
                //            }
                
                let route = audioSession.currentRoute
                
                for input in route.inputs {
                    print(
                        "🎤 Current input: \(input.portName) - \(input.portType.rawValue)"
                    )
                }
                
                for output in route.outputs {
                    print(
                        "🔊 Current output: \(output.portName) - \(output.portType.rawValue)"
                    )
                }
                
                try self.audioSession.setActive(
                    true
                )
                
            } catch {
                print(
                    "Error configuring audio session: \(error)"
                )
            }
        }
    
    
    func setupAndCapture(
        device: AVCaptureDevice,
        height: Int32,
        fps: Int32,
        stabilization: AVCaptureVideoStabilizationMode
    ) {
        
        guard let audioDevice = AVCaptureDevice.default(
           for: .audio
       ) else {
           return
       }
        
        
        if(captureSession.isRunning){
            captureSession.stopRunning()
        }
        
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        
        // Remove old inputs
        if !captureSession.inputs.isEmpty {
            captureSession.inputs.forEach { input in
                captureSession.removeInput(
                    input
                )
            }
        }
        
        guard let videoInput = try? AVCaptureDeviceInput(
            device: device
        ) else {
            return
        }
        guard let audioInput = try? AVCaptureDeviceInput(
            device: audioDevice
        ) else {
            return
        }
        
        captureSession.usesApplicationAudioSession = true
        captureSession.automaticallyConfiguresApplicationAudioSession = true
        
        captureSession.addInput(
            videoInput
        )
        captureSession.addInput(
            audioInput
        )
        
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        // Add outputs
        if captureSession.canAddOutput(videoOutput) && captureSession.canAddOutput(audioOutput) {
            captureSession.addOutput(
                videoOutput
            )
            captureSession.addOutput(
                audioOutput
            )
            
            synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, audioOutput])
            synchronizer?.setDelegate(self, queue: DispatchQueue(label: "synchronizer.queue"))
        }
        
        //        videoOutput.videoSettings = [
        //            AVVideoCodecKey: AVVideoCodecType.hevc
        //        ]
        
        
        try? applySettings(
            device: device,
            height: height,
            fps: fps,
            stabilization: stabilization
        );
        
        if let connection = videoOutput.connection(
            with: .video
        ), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = stabilization
        }
        
        self.updateVideoOrientation()
        
        
        self.setAudioInputToBluetoothOrUSB()
        
        captureSession.commitConfiguration()
        
        DispatchQueue.global(
            qos: .userInitiated
        ).async {
            self.captureSession.startRunning()
        }
        
    }
    
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer, didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        // Get synchronized video
          if let syncedVideo = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVCaptureSynchronizedSampleBufferData,
             !syncedVideo.sampleBufferWasDropped {
              
              let videoSampleBuffer = syncedVideo.sampleBuffer
//              let videoPTS = CMSampleBufferGetPresentationTimeStamp(videoSampleBuffer)
//              print("Synced Video PTS: \(videoPTS.seconds)")
              
              captureOutputVideo(sampleBuffer: videoSampleBuffer)
          }

          // Get synchronized audio
          if let syncedAudio = synchronizedDataCollection.synchronizedData(for: audioOutput) as? AVCaptureSynchronizedSampleBufferData,
             !syncedAudio.sampleBufferWasDropped {
              
              let audioSampleBuffer = syncedAudio.sampleBuffer
//              let audioPTS = CMSampleBufferGetPresentationTimeStamp(audioSampleBuffer)
//              print("Synced Audio PTS: \(audioPTS.seconds)")

              audioSource?.deliverRecordedData(sampleBuffer: audioSampleBuffer)
          }
    }
    
    private func captureOutputVideo(
        sampleBuffer: CMSampleBuffer
    ) {
        if let source = videoSource {
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(
                sampleBuffer
            ) else {
                return
            }
            
            let rtcPixelBuffer = RTCCVPixelBuffer(
                pixelBuffer: pixelBuffer
            )
            let timeStampNs = CMTimeGetSeconds(
                CMSampleBufferGetPresentationTimeStamp(
                    sampleBuffer
                )
            ) * 1_000_000_000
            let videoFrame = RTCVideoFrame(
                buffer: rtcPixelBuffer,
                rotation: ._0,
                timeStampNs: Int64(
                    timeStampNs
                )
            )
            
            source.capturer(
                videoCapturer,
                didCapture: videoFrame
            )
        }
    }
}


