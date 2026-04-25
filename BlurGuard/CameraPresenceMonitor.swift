import AVFoundation
import Vision

final class CameraPresenceMonitor: NSObject {

    var onPeekDetected: (() -> Void)?
    var onUserAway: (() -> Void)?

    private var session: AVCaptureSession?
    private let sessionQueue = DispatchQueue(label: "com.blurguard.camera", qos: .utility)
    private var lastProcessedTime: Date = .distantPast
    private let frameInterval: TimeInterval = 1.0

    private var noFaceSince: Date?
    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }
        requestPermissionAndStart()
    }

    func stop() {
        isRunning = false
        noFaceSince = nil
        sessionQueue.async { [weak self] in
            self?.session?.stopRunning()
            self?.session = nil
        }
    }

    private func requestPermissionAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { self.setupSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted { self.sessionQueue.async { self.setupSession() } }
            }
        default:
            break
        }
    }

    private func setupSession() {
        let s = AVCaptureSession()
        s.sessionPreset = .low

        guard let device = findCamera(),
              let input = try? AVCaptureDeviceInput(device: device),
              s.canAddInput(input) else { return }
        s.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        output.alwaysDiscardsLateVideoFrames = true
        guard s.canAddOutput(output) else { return }
        s.addOutput(output)

        session = s
        isRunning = true
        s.startRunning()
    }

    private func findCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
    }
}

extension CameraPresenceMonitor: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessedTime) >= frameInterval else { return }
        lastProcessedTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            .perform([request])

        let count = request.results?
            .filter { $0.confidence >= 0.5 }
            .count ?? 0

        handleFaceCount(count, at: now)
    }

    private func handleFaceCount(_ count: Int, at time: Date) {
        if count >= 2 {
            // Someone peeking — blur immediately
            noFaceSince = nil
            onPeekDetected?()
        } else if count == 0 {
            // No face — start away timer
            if noFaceSince == nil { noFaceSince = time }
            let awayDelay = TimeInterval(SettingsManager.shared.cameraAwayDelay)
            if let since = noFaceSince, time.timeIntervalSince(since) >= awayDelay {
                noFaceSince = nil
                onUserAway?()
            }
        } else {
            // Exactly 1 face — user is present, reset away timer
            noFaceSince = nil
        }
    }
}
