//
//  AudioCapturer.swift
//  WebRTC-Demo
//
//  Created by Robson Ferreira Jacomini on 01/08/25.
//  Copyright © 2025 Stas Seldin. All rights reserved.
//

import AVFoundation
import WebRTC

class AudioDevice: NSObject, RTCAudioDevice {
    private var audioConverter: AVAudioConverter?
    private let audioSession = AVAudioSession.sharedInstance()
    
    private weak var delegate: RTCAudioDeviceDelegate?
    
    var deviceInputSampleRate: Double = 48000
    var inputIOBufferDuration: TimeInterval = 0.01
    var inputNumberOfChannels: Int = 1
    var inputLatency: TimeInterval = 0
    
    var deviceOutputSampleRate: Double = 48000
    var outputIOBufferDuration: TimeInterval = 0.01
    var outputNumberOfChannels: Int = 1
    var outputLatency: TimeInterval = 0
    
    var isInitialized: Bool = false
    var isPlayoutInitialized: Bool = false
    var isPlaying: Bool = false
    var isRecordingInitialized: Bool = false
    var isRecording: Bool = false
    
    // A ring-buffer to accumulate raw Int16 PCM samples until we reach expectedSamplesPer10ms
    private var pendingSamples = [Int16]()

    // 10-ms frame size at 48 kHz
    private var expectedSamplesPer10ms: Int {
        return 480 * inputNumberOfChannels
    }
    
    func recordingChannels() -> Int32  {
        return Int32(inputNumberOfChannels)
    }

    
    func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
        self.delegate = delegate
        watchAudioSession()
        
        isInitialized = true
        return true
    }
    
    func terminateDevice() -> Bool {
        isInitialized = false
        return true
    }

    
    func initializePlayout() -> Bool {
        updateAudioParameters()
        isPlayoutInitialized = true
        return true
    }

    func startPlayout() -> Bool {
        updateAudioParameters()
        isPlaying = true
        return true
    }

    func stopPlayout() -> Bool {
        isPlaying = false
        return true
    }
    
    func initializeRecording() -> Bool {
        updateAudioParameters()
        isRecordingInitialized = true
        return true
    }
    
    func startRecording() -> Bool {
        updateAudioParameters()
        isRecording = true
        return true
    }
    
    func stopRecording() -> Bool {
        isRecording = false
        return true
    }
    
    // Send frames to WebRTC
    func deliverRecordedData(sampleBuffer: CMSampleBuffer) {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
                 var asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else { return }

//        print("Format: \(asbd.mFormatID) bits: \(asbd.mBitsPerChannel) sampleRate: \(asbd.mSampleRate)")

        
//        let frameCount = UInt32(CMSampleBufferGetNumSamples(sampleBuffer))
//        let samplesPerChannel = Int(frameCount)
//        if samplesPerChannel != expectedSamplesPer10ms {
//            print("⚠️ got \(samplesPerChannel) samples — WebRTC expects exactly \(expectedSamplesPer10ms) at 48 kHz")
//        }
        
        guard isRecording, let delegate = self.delegate else { return }
        
        // Extract Int16 raw samples
        var audioBufferList = AudioBufferList()
        var blockBuffer: CMBlockBuffer?
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: &audioBufferList,
            bufferListSize: MemoryLayout<AudioBufferList>.size,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        if let mBuffer = audioBufferList.mBuffers.mData {
            let count = Int(audioBufferList.mBuffers.mDataByteSize) / MemoryLayout<Int16>.size
            let ptr = mBuffer.assumingMemoryBound(to: Int16.self)
            let incoming = Array(UnsafeBufferPointer(start: ptr, count: count))
            
            // Append into our accumulator
            pendingSamples.append(contentsOf: incoming)
        }
        
        // While we have at least 480 samples, send a frame
        while pendingSamples.count >= expectedSamplesPer10ms {
            let frameSamples = Array(pendingSamples.prefix(expectedSamplesPer10ms))
            pendingSamples.removeFirst(expectedSamplesPer10ms)
            
            // Allocate native buffer for WebRTC
            let byteCount = frameSamples.count * MemoryLayout<Int16>.size
            let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: byteCount, alignment: 2)
            
            // Copy audio samples into it
            rawPointer.copyMemory(from: frameSamples, byteCount: byteCount)
            
            var localBufferList = AudioBufferList(
                mNumberBuffers: 1,
                mBuffers: AudioBuffer(
                    mNumberChannels: UInt32(inputNumberOfChannels),
                    mDataByteSize: UInt32(byteCount),
                    mData: rawPointer
                )
            )

            var flags = AudioUnitRenderActionFlags()
            var timestamp = AudioTimeStamp()
            let frameCount: UInt32 = UInt32(expectedSamplesPer10ms)

            // ✅ Deliver to WebRTC
            let status = delegate.deliverRecordedData(
                &flags,
                &timestamp,
                0,
                frameCount,
                &localBufferList,
                &asbd,
                nil
            )
            
            if status != noErr {
                print("❌ deliverRecordedData failed: \(status)")
            }
            
            // Clean up
            rawPointer.deallocate()
        }
    }
    
    private func watchAudioSession() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange(_:)),
            name: AVAudioSession.routeChangeNotification,
            object: audioSession)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: audioSession)
    }
        
    @objc private func handleRouteChange(_ n: Notification) {
        print("🔁 Audio route changed")
        updateAudioParameters()
    }
    
    @objc private func handleMediaServicesReset(_ n: Notification) {
        print("⚠️ Media services were reset")
        // Re-apply your desired WebRTC / AudioSession settings here…
        updateAudioParameters()
    }
    
    func updateAudioParameters() {
        deviceInputSampleRate = audioSession.sampleRate
        deviceOutputSampleRate = audioSession.sampleRate
        
        inputIOBufferDuration = audioSession.ioBufferDuration
        outputIOBufferDuration = audioSession.ioBufferDuration
        
        inputLatency = audioSession.inputLatency
        outputLatency = audioSession.outputLatency
                
        
        print("📈 Sample rate: \(deviceInputSampleRate)")
        print("⏱️ IO buffer duration: \(inputIOBufferDuration)")
        
        if let input = audioSession.currentRoute.inputs.first {
            inputNumberOfChannels = input.channels?.count ?? 1
            
            print("🎙️ Input: \(input.portName)")
            print("🎚️ Input Channels: \(inputNumberOfChannels)")
            print("⌛️ Input Latency: \(inputLatency)")
        }
        
        
        if let output = audioSession.currentRoute.outputs.first {
            outputNumberOfChannels = output.channels?.count ?? 1
            
            print("🎙️ Output: \(output.portName)")
            print("🎚️ Output Channels: \(outputNumberOfChannels)")
            print("⌛️ Output Latency: \(outputLatency)")
        }
        
        
        print("/////////////////////////////////////////////////////")
        
        delegate?.notifyAudioInputParametersChange()
        delegate?.notifyAudioOutputParametersChange()
    }
    
    
}



