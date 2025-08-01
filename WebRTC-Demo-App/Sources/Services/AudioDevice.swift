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
    private var delegate: RTCAudioDeviceDelegate?
    
    var deviceInputSampleRate: Double = 48000
    var inputIOBufferDuration: TimeInterval = 0.02
    var inputNumberOfChannels: Int = 1
    var inputLatency: TimeInterval = 0
    var deviceOutputSampleRate: Double = 48000
    var outputIOBufferDuration: TimeInterval = 0.02
    var outputNumberOfChannels: Int = 1
    var outputLatency: TimeInterval = 0
    
    var isInitialized: Bool = false
    var isPlayoutInitialized: Bool = false
    var isPlaying: Bool = false
    var isRecordingInitialized: Bool = false
    var isRecording: Bool = false
    
    
    func initialize(with delegate: RTCAudioDeviceDelegate) -> Bool {
        self.delegate = delegate
        isInitialized = true
        return true
    }
    
    func terminateDevice() -> Bool {
        isInitialized = false
        return true
    }

    
    func initializePlayout() -> Bool {
        isPlayoutInitialized = true
        return true
    }

    func startPlayout() -> Bool {
        isPlaying = true
        return true
    }

    func stopPlayout() -> Bool {
        isPlaying = false
        return true
    }
    
    func initializeRecording() -> Bool {
        isRecordingInitialized = true
        return true
    }
    
    func startRecording() -> Bool {
        isRecording = true
        return true
    }
    
    func stopRecording() -> Bool {
        isRecording = false
        return true
    }
    
    // Send frames to WebRTC
    func deliverRecordedData(sampleBuffer: CMSampleBuffer) {
        if (!isRecording) { return }
        
        guard let delegate = self.delegate else { return }
        
        var flags = AudioUnitRenderActionFlags()
        var timestamp = AudioTimeStamp()
        let frameCount = UInt32(CMSampleBufferGetNumSamples(sampleBuffer))
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
        
        
        // Chama o bloco para entregar os dados ao WebRTC
        let _ = delegate.deliverRecordedData(
            &flags,
            &timestamp,
            0,
            frameCount,
            &audioBufferList,
            nil,
            nil
        )
    }
}



