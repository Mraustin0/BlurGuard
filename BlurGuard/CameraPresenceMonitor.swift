import AVFoundation
import Vision

final class CameraPresenceMonitor: NSObject {

    var onPeekDetected:     (() -> Void)?
    var onUserAway:         (() -> Void)?
    var onPermissionDenied: (() -> Void)?

    private(set) var isRunning = false

    private var session: AVCaptureSession?
    private let sessionQueue   = DispatchQueue(label: "com.blurguard.camera", qos: .utility)
    private var lastFrameDate  = Date.distantPast
    private let frameInterval: TimeInterval = 1.0
    private var noFaceSince:   Date?

    // MARK: - Start / Stop

    func start() {
        guard !isRunning else { return }
        requestCameraAccessThenStart()
    }

    func stop() {
        isRunning    = false
        noFaceSince  = nil
        sessionQueue.async { [weak self] in
            self?.session?.stopRunning()
            self?.session = nil
        }
    }

    // MARK: - Permission + setup

    private func requestCameraAccessThenStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            sessionQueue.async { self.setupSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    self.sessionQueue.async { self.setupSession() }
                } else {
                    DispatchQueue.main.async { self.onPermissionDenied?() }
                }
            }
        default:
            // .denied or .restricted — surface the failure so UI stays truthful.
            DispatchQueue.main.async { self.onPermissionDenied?() }
        }
    }

    private func setupSession() {
        let capture = AVCaptureSession()
        capture.sessionPreset = .low

        guard
            let device = frontCamera(),
            let input  = try? AVCaptureDeviceInput(device: device),
            capture.canAddInput(input)
        else { return }
        capture.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: sessionQueue)
        output.alwaysDiscardsLateVideoFrames = true

        guard capture.canAddOutput(output) else { return }
        capture.addOutput(output)

        session   = capture
        isRunning = true
        capture.startRunning()
    }

    private func frontCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
    }
}

// MARK: - Frame processing

extension CameraPresenceMonitor: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = Date()
        guard now.timeIntervalSince(lastFrameDate) >= frameInterval else { return }
        lastFrameDate = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let faceCount = countFaces(in: pixelBuffer)
        handleFaceCount(faceCount, at: now)
    }

    private func countFaces(in pixelBuffer: CVPixelBuffer) -> Int {
        let request = VNDetectFaceRectanglesRequest()
        try? VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
            .perform([request])

        // Map sensitivity 0→1 to a confidence threshold 0.7→0.2.
        // Higher sensitivity = lower threshold = more detections at worse angles.
        let sensitivity = SettingsManager.shared.cameraSensitivity
        let threshold   = Float(0.7 - sensitivity * 0.5)

        return request.results?.filter { $0.confidence >= threshold }.count ?? 0
    }

    private func handleFaceCount(_ count: Int, at now: Date) {
        switch count {
        case 2...:
            // Two or more faces means someone is looking over the user's shoulder.
            noFaceSince = nil
            onPeekDetected?()

        case 0:
            // No face — start or continue the away timer.
            if noFaceSince == nil { noFaceSince = now }
            let delay = TimeInterval(SettingsManager.shared.cameraAwayDelay)
            if let since = noFaceSince, now.timeIntervalSince(since) >= delay {
                noFaceSince = nil
                onUserAway?()
            }

        default:
            // Exactly one face — user is present. Reset the away timer.
            noFaceSince = nil
        }
    }
}
