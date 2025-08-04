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
    
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    
    
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
        
        setupCaptureSession()
        setupAudioSession()
//        setupAudioEngine()
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
    
    func audioDevices() -> [AVCaptureDevice] {
        var deviceTypes: [AVCaptureDevice.DeviceType] = []
        if #available(
            iOS 17.0,
            *
        ) {
            deviceTypes =  [.microphone]
        } else {
            deviceTypes =  [.builtInMicrophone]
        }
        
        
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .audio,
            position: .unspecified
        ).devices
    }
    
    private func setupCaptureSession(){
        captureSession.beginConfiguration()
        
        captureSession.usesApplicationAudioSession = true
        captureSession.automaticallyConfiguresApplicationAudioSession = false
        
        videoOutput.alwaysDiscardsLateVideoFrames = true
        
        // Add outputs
        if captureSession.canAddOutput(
            videoOutput
        ) && captureSession.canAddOutput(
            audioOutput
        ) {
            captureSession.addOutput(
                videoOutput
            )
            
            captureSession.addOutput(
                audioOutput
            )
        }
        
        //        videoOutput.videoSettings = [
        //            AVVideoCodecKey: AVVideoCodecType.hevc
        //        ]
        
        
        captureSession.commitConfiguration()
        
        
        DispatchQueue.global(
            qos: .userInitiated
        ).async {
            self.captureSession.startRunning()
        }
        
    }
    
    private func setupAudioSession(){
        do {
            try audioSession.setPrefersNoInterruptionsFromSystemAlerts(true)
            
            try audioSession.setPreferredSampleRate(48000)
            try audioSession.setPreferredIOBufferDuration(0.01)
            
            try audioSession.setCategory(
                .playAndRecord,
                mode: .videoRecording,
                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]
            )
        } catch {
            print("Audio session config error")
        }
        
        do {
            try audioSession.setActive(true)
        } catch {
            print(
                "Audio session start error"
            )
        }
        
        for input in audioSession.availableInputs ?? [] {
            print(
                "Port: \(input.portName)"
            )
        }
        
        do {
            try audioSession.setPreferredInputNumberOfChannels(min(audioSession.maximumInputNumberOfChannels, 2))
            print("preferredInputNumberOfChannels \(audioSession.preferredInputNumberOfChannels)")
            
            // Find the built-in microphone input's data sources,
            // and select the one that matches the specified name.
            guard let preferredInput = audioSession.preferredInput,
                  let dataSources = preferredInput.dataSources,
                  let newDataSource = dataSources.first,
                  let supportedPolarPatterns = newDataSource.supportedPolarPatterns else {
                return
            }
            
            // If the data source supports stereo, set it as the preferred polar pattern.
            if supportedPolarPatterns.contains(
                .stereo
            ) {
                // Set the preferred polar pattern to stereo.
                try newDataSource.setPreferredPolarPattern(
                    .stereo
                )
            }
            
            // Set the preferred data source and polar pattern.
            try preferredInput.setPreferredDataSource(
                newDataSource
            )
        } catch {
            print(
                "Audio session prefer stereo error"
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
        
    }
    
    private func setupAudioEngine() {
        
        engine.attach(player)
        
        let format = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                       sampleRate: 48000,
                                       channels: 1,
                                       interleaved: false)!        
        engine.connect(player, to: engine.outputNode, format: format)
        
        do {
            try engine.start()
            player.play()
        } catch {
            print("Audio Engine failed to start: \(error)")
        }
    }
    
    func setupDevice(
        device: AVCaptureDevice,
        height: Int32,
        fps: Int32,
        stabilization: AVCaptureVideoStabilizationMode
    ) {
        
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .high
        
        guard let audioDevice = AVCaptureDevice.default(
            for: .audio
        ) else {
            return
        }
        
        
        for format in audioDevice.formats {
            let desc = format.formatDescription
            let streamDesc = CMAudioFormatDescriptionGetStreamBasicDescription(
                desc
            )?.pointee
            if let s = streamDesc {
                print(
                    "Sample Rate: \(s.mSampleRate), Channels: \(s.mChannelsPerFrame)"
                )
            }
        }
        
        applyVideoSettings(
            device: device,
            height: height,
            fps: fps,
            stabilization: stabilization
        );
        
        updateVideoOrientation()
        
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
        
        
        captureSession.addInput(
            videoInput
        )
        captureSession.addInput(
            audioInput
        )
        
        if let connection = videoOutput.connection(
            with: .video
        ), connection.isVideoStabilizationSupported {
            connection.preferredVideoStabilizationMode = stabilization
        }
        
        
        captureSession.commitConfiguration()
        
        self.audioSource?.updateAudioParameters()
        
        if(
            synchronizer == nil
        ){
            synchronizer = AVCaptureDataOutputSynchronizer(
                dataOutputs: [
                    videoOutput,
                    audioOutput
                ]
            )
            synchronizer?.setDelegate(
                self,
                queue: DispatchQueue(
                    label: "synchronizer.queue"
                )
            )
        }
        
    }
    
    private func applyVideoSettings(
        device: AVCaptureDevice,
        height: Int32,
        fps: Int32,
        stabilization: AVCaptureVideoStabilizationMode
    )  {
        do {
            
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
            
            device.unlockForConfiguration()
            
        } catch {
            print(
                "Error Applying video settings"
            )
        }
    }
    
    func setVideoSource(
        source: RTCVideoSource
    ){
        self.videoSource = source
    }
    
    func setAudioSource(
        device: AudioDevice
    ) {
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
    
    func dataOutputSynchronizer(
        _ synchronizer: AVCaptureDataOutputSynchronizer,
        didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection
    ) {
        // Get synchronized video
        if let syncedVideo = synchronizedDataCollection.synchronizedData(
            for: videoOutput
        ) as? AVCaptureSynchronizedSampleBufferData,
           !syncedVideo.sampleBufferWasDropped {
            
            let videoSampleBuffer = syncedVideo.sampleBuffer
            //              let videoPTS = CMSampleBufferGetPresentationTimeStamp(videoSampleBuffer)
            //              print("Synced Video PTS: \(videoPTS.seconds)")
            
            captureOutputVideo(
                sampleBuffer: videoSampleBuffer
            )
        }
        
        // Get synchronized audio
        if let syncedAudio = synchronizedDataCollection.synchronizedData(
            for: audioOutput
        ) as? AVCaptureSynchronizedSampleBufferData,
           !syncedAudio.sampleBufferWasDropped {
            
            let audioSampleBuffer = syncedAudio.sampleBuffer
            
            //              let audioPTS = CMSampleBufferGetPresentationTimeStamp(audioSampleBuffer)
            //              print("Synced Audio PTS: \(audioPTS.seconds)")
            
            audioSource?.deliverRecordedData(
                sampleBuffer: audioSampleBuffer
            )
            
            if player.isPlaying {
                playAudio(audioSampleBuffer)
            }
        }
    }
    
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        if output == videoOutput {
            captureOutputVideo(
                sampleBuffer: sampleBuffer
            )
        } else if output == audioOutput {
            audioSource?.deliverRecordedData(
                sampleBuffer: sampleBuffer
            )
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
    
    func playAudio(
        _ sampleBuffer: CMSampleBuffer
    ) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }
        
        let inputFormat = AVAudioFormat(streamDescription: asbd)!
        let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat,
                                               frameCapacity: AVAudioFrameCount(numSamples)) else {
            return
        }

        var lengthAtOffset = 0
        var totalLength = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0,
                                    lengthAtOffsetOut: &lengthAtOffset,
                                    totalLengthOut: &totalLength,
                                    dataPointerOut: &dataPointer)

        if let data = dataPointer {
            memcpy(pcmBuffer.int16ChannelData![0], data, totalLength)
            pcmBuffer.frameLength = AVAudioFrameCount(numSamples)
                
            
            // 🔊 Now play it back
            player.scheduleBuffer(pcmBuffer, completionHandler: nil)
        }
    }
}


