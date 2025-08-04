//
//  WHIPClient.swift
//  WebRTC-Demo
//
//  Created by Robson Ferreira Jacomini on 21/07/25.
//  Copyright © 2025 Stas Seldin. All rights reserved.
//

import Foundation
import AVFoundation
import WebRTC

struct LiveRtcStat: Codable {
    let timetamp: Int64
    let status: String
    let statusICE: String
}
struct LiveStat: Codable {
    let id: String
    let stats: LiveRtcStat
}

struct InfoStat: Codable {
    let userDisplayName: String
    let app: String
    let os: String
    let liveStatus: String
    let thermalStatus: String
}

struct Statistics: Codable {
    let identity: String

//    let config: DeviceConfig
    let info: InfoStat

    let live: LiveStat
}

protocol WHIPClientDelegate: AnyObject {
    func whipClient(
        _ client: WHIPClient,
        didChangeSignalingState state: RTCSignalingState
    )
    func whipClient(
        _ client: WHIPClient,
        didChangeConnectionState state: RTCPeerConnectionState
    )
    func whipClient(
        _ client: WHIPClient,
        didCreateOffer error: Error?
    )
    func whipClient(
        _ client: WHIPClient,
        didReceiveAnswer error: Error?
    )
}


class WHIPClient: NSObject {
    private var factory: RTCPeerConnectionFactory!
    private var config: RTCConfiguration!
    private var peerConnection: RTCPeerConnection?
    
    var videoSource: RTCVideoSource!
    var audioDevice = AudioDevice()
        
    private let encoder = RTCDefaultVideoEncoderFactory()
    private let decoder = RTCDefaultVideoDecoderFactory()
    private var codec = kRTCVideoCodecH264Name
    
    private var displayName = "Demo_app_iOS"
    private var baseURL = "https://api.souv.dev"
    private var mode = "calls"
    private var bitrate = 10_000_000
    
    private var resourceLocation: String?
    private var liveID: String?
    private var wkID = "wkID"
    private var deviceID = "deviceID"
    private var auth = "auth"
    
    private let timeInterval: TimeInterval = 10
    private var statsTimer: Timer?
    
    weak var delegate: WHIPClientDelegate?
    
    override init() {
        super.init()
        setupWebRTC()
        startSendingStats()
    }
    
    deinit {
        stopSendingStats()
    }
    
    private func setupWebRTC() {
        RTCInitializeSSL()
        
        config = RTCConfiguration()
        config.iceServers = [RTCIceServer(
            urlStrings: ["stun:stun.cloudflare.com:3478"]
        )]
        
        config.sdpSemantics = .unifiedPlan
        config.bundlePolicy = .maxBundle
                
        encoder.preferredCodec = RTCVideoCodecInfo(
            name: codec
        )
        
        factory = RTCPeerConnectionFactory(
            encoderFactory: encoder,
            decoderFactory: decoder, 
            audioDevice: audioDevice
        )
        
        videoSource = factory.videoSource()
        
        
    }
    
    private func applyBitrate() {
        peerConnection?.senders.forEach({ sender in
            let kind = sender.track?.kind
            
            let params = sender.parameters
            if let encoding = params.encodings.first {
                if kind == "video" {
                    encoding.maxBitrateBps = (self.bitrate) as NSNumber
                    encoding.networkPriority = .medium
                    
                } else {
                    encoding.maxBitrateBps = 128_000
                    encoding.networkPriority = .medium
                    
                }
                params.degradationPreference = NSNumber(value: RTCDegradationPreference.balanced.rawValue)
                
                params.encodings[0] = encoding
                sender.parameters = params
            }
        })
    }
    
    private func createPeerConnection() {
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil
        )
        
        peerConnection = factory.peerConnection(
            with: config,
            constraints: constraints,
            delegate: self
            
        )
        
        let audioConstraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "googEchoCancellation": "false",
                "googAutoGainControl": "false",
                "googNoiseSuppression": "false",
                "googHighpassFilter": "false",
                "googTypingNoiseDetection": "false",
                "googAudioMirroring": "false"
            ],
            optionalConstraints: nil
        )
    
        let streamId = "stream"
        
        let videoTrack = factory.videoTrack(with: videoSource, trackId: "video0")
        let audioTrack = factory.audioTrack(with: factory.audioSource(with: audioConstraints), trackId: "audio0")
        
        
        peerConnection?.add(videoTrack, streamIds: [streamId])
        peerConnection?.add(audioTrack, streamIds: [streamId])
        
        self.applyBitrate()
    }
    
    
    func setMode(
        _ mode: String
    ){
        self.mode = mode
    }
    
    func setBitrate(
        _ bitrate: Int
    ){
        self.bitrate = bitrate
        
        self.applyBitrate()
    }
    
    func setCodec(
        _ codec: String
    ){
        self.codec = codec
        encoder.preferredCodec = RTCVideoCodecInfo(
            name: codec
        )
    }
    
    
    func setVideo(
        muted: Bool
    ){
        peerConnection?.senders.forEach({ sender in
            guard let track = sender.track else { return }
            let kind = track.kind
            
            if kind == "video" {
                track.isEnabled = !muted
            }
        })
    }
    
    func setAudio (
        muted: Bool
    ){
        peerConnection?.senders.forEach({ sender in
            guard let track = sender.track else { return }
            let kind = track.kind
            
            if kind == "audio" {
                track.isEnabled = !muted
            }
        })
    }
    
    func start(
        endpoint: String
    ) {
        // Set base url depending on endpoint
        if let url = URL(
            string: endpoint
        ){
            if let scheme = url.scheme, let host = url.host {
                baseURL = "\(scheme)://\(host)"
            }
            
            let path = url.path
            let query = url.query
            
            // get wkID and deviceID
            let split = path.split(
                separator: "/"
            )
            wkID = String(
                split[2]
            )
            deviceID = String(
                split[3]
            )
            
            if let items = query?.split(
                separator: "&"
            ) {
                let split = items[0].split(
                    separator: "="
                )
                auth = String(
                    split[1]
                )
            }
        }
        
        createPeerConnection()
        
        
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "false",
                "OfferToReceiveVideo": "false"
            ],
            optionalConstraints: nil
        )
        
        peerConnection?.offer(
            for: constraints
        ) {
            [weak self] offer,
            error in
            guard let self = self,
                  let offer = offer else {
                print(
                    "Failed to create offer: \(error?.localizedDescription ?? "Unknown")"
                )
                return
            }
            
            peerConnection?.setLocalDescription(
                offer
            ) { error in
                self.delegate?.whipClient(
                    self,
                    didCreateOffer: error
                )
                
                if let error = error {
                    print(
                        "Failed to set local description: \(error)"
                    )
                    return
                }
                
                self.sendOfferToWHIPEndpoint(
                    endpoint: endpoint,
                    sdp: offer.sdp
                )
            }
        }
    }
    
    func stop(){
        self.liveID = nil
        
        if let location = self.resourceLocation {
            var request = URLRequest(
                url: URL(
                    string: location
                )!
            )
            request.httpMethod = "DELETE"
            
            // Stop live
            let task = URLSession.shared.dataTask(
                with: request
            )
            task.resume()
        }
        
        
    }
    
    private func sendOfferToWHIPEndpoint(
        endpoint: String,
        sdp: String
    ) {
        var request = URLRequest(
            url: URL(
                string: endpoint
            )!
        )
        
        request.httpMethod = "POST"
        request.setValue(
            "application/sdp",
            forHTTPHeaderField: "Content-Type"
        )
        request.addValue(
            "rtc",
            forHTTPHeaderField: "liveMode"
        )
        request.addValue(
            "fhd",
            forHTTPHeaderField: "liveQuality"
        )
        request.addValue(
            "1000000",
            forHTTPHeaderField: "liveBitrate"
        )
        request.addValue(
            self.codec.lowercased(),
            forHTTPHeaderField: "liveCodec"
        )
        request.addValue(
            self.mode,
            forHTTPHeaderField: "liveConnMode"
        )
        request.addValue(
            "0",
            forHTTPHeaderField: "livePlayoutDelayMs"
        )
        request.addValue(
            displayName,
            forHTTPHeaderField: "displayName"
        )
        
        request.httpBody = sdp.data(
            using: .utf8
        )
        
        let task = URLSession.shared.dataTask(
            with: request
        ) {
            [weak self] data,
            response,
            error in
            guard let self = self,
                  let data = data,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 201 || httpResponse.statusCode == 200 else {
                print(
                    "WHIP POST failed: \(error?.localizedDescription ?? "Unknown")"
                )
                return
            }
            
            print(
                "/////// Header Response /////////////"
            )
            for (
                key,
                value
            ) in httpResponse.allHeaderFields {
                print(
                    "\(key): \(value)"
                )
            }
            print(
                "//////////////////////////////////////"
            )
            
            
            let locHeader = httpResponse.allHeaderFields["location"] ?? httpResponse.allHeaderFields["Location"]
            if let location = locHeader as? String {
                self.resourceLocation =   location.starts(
                    with: "/"
                ) ?  "\(baseURL)\(location)" : location
            }
            
            let liveIDHeader = httpResponse.allHeaderFields["etag"] ?? httpResponse.allHeaderFields["Etag"]
            if let liveID = liveIDHeader as? String {
                self.liveID = liveID
            }
            
            if let answerSDP = String(
                data: data,
                encoding: .utf8
            ) {
                let sdpAnswer = RTCSessionDescription(
                    type: .answer,
                    sdp: answerSDP
                )
                peerConnection?.setRemoteDescription(sdpAnswer,
                                                     completionHandler: {
                    error in
                    self.delegate?.whipClient(
                        self,
                        didReceiveAnswer: error
                    )
                    
                    if let error = error {
                        print(
                            "Failed to set remote description: \(error)"
                        )
                    } else {
                        print(
                            "Connection established."
                        )
                    }
                })
            }
        }
        task.resume()
    }
    
    private func startSendingStats() {
        statsTimer = Timer.scheduledTimer(
            timeInterval: timeInterval,
            target: self,
            selector: #selector(
                sendStatistics
            ),
            userInfo: nil,
            repeats: true
        )
    }
    
    private func stopSendingStats() {
        statsTimer?.invalidate()
        statsTimer = nil
    }
    
    private func getThermalState() -> String{
        switch ProcessInfo.processInfo.thermalState {
                case .nominal:
                    return "none"
                case .fair:
                    return "light"
                case .serious:
                    return  "severe"
                case .critical:
                    return "critical"
                @unknown default:
                    return "none"
                }
    }
    
    @objc private func sendStatistics() {
        guard let liveID = self.liveID else {
            return
        }
                
        let stats = Statistics(
            identity: deviceID,
            info: InfoStat(
                userDisplayName: self.displayName,
                app: "demo",
                os: "iOS",
                liveStatus: "broadcasting",
                thermalStatus: getThermalState()
            ),
            live: LiveStat(
                id: liveID,
                stats: LiveRtcStat(timetamp: 0, status: "connected", statusICE: "connected")
            )
        )
                
        guard let url = URL(
            string: "\(baseURL)/api/device/stats/\(wkID)/\(deviceID)?auth=\(auth)"
        ) else {
            return
        }
        
        var request = URLRequest(
            url: url
        )
        request.httpMethod = "POST"
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )
        
        do {
            let jsonData = try JSONEncoder().encode(
                stats
            )
            request.httpBody = jsonData
        } catch {
            print(
                "Encoding error: \(error)"
            )
            return
        }
        
        let task = URLSession.shared.dataTask(
            with: request
        ) {
            data,
            response,
            error in
            if let error = error {
                print(
                    "Error sending stats: \(error)"
                )
                return
            }
            if let httpResponse = response as? HTTPURLResponse {
                print(
                    "Sends Stats responded: \(httpResponse.statusCode)"
                )
            }
        }
        task.resume()
    }
    
}

// MARK: - RTCPeerConnectionDelegate

extension WHIPClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        self.delegate?.whipClient(
            self,
            didChangeConnectionState: newState
        )
    }
    func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange stateChanged: RTCSignalingState
    ) {
        self.delegate?.whipClient(
            self,
            didChangeSignalingState: stateChanged
        )
    }
    func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didAdd stream: RTCMediaStream
    ) {
    }
    func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didRemove stream: RTCMediaStream
    ) {
    }
    func peerConnectionShouldNegotiate(
        _ peerConnection: RTCPeerConnection
    ) {
    }
    func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCIceConnectionState
    ) {
        print(
            "ICE state: \(newState)"
        )
    }
    func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didChange newState: RTCIceGatheringState
    ) {
    }
    
    func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didGenerate candidate: RTCIceCandidate
    ) {
    }
    func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didRemove candidates: [RTCIceCandidate]
    ) {
    }
    func peerConnection(
        _ peerConnection: RTCPeerConnection,
        didOpen dataChannel: RTCDataChannel
    ) {
    }
}
