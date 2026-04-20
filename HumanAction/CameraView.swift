import SwiftUI
import AVFoundation
import Vision
import Combine
import CoreML

// 1. 核心视图：App 的主要界面
struct CameraView: View {
    @StateObject private var model = CameraViewModel()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 相机预览层
                CameraPreview(session: model.session)
                    .ignoresSafeArea()
                
                // 2. 调试层：绘制骨骼点和基准线
                Canvas { context, size in
                    // 绘制蓝色基准线 (地面)
                    let baseY = (1 - model.baselineY) * size.height
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: baseY))
                    path.addLine(to: CGPoint(x: size.width, y: baseY))
                    context.stroke(path, with: .color(.blue.opacity(0.5)), lineWidth: 2)
                    
                    // 绘制黄色起跳触发线
                    let triggerY = (1 - (model.baselineY + model.threshold)) * size.height
                    var triggerPath = Path()
                    triggerPath.move(to: CGPoint(x: 0, y: triggerY))
                    triggerPath.addLine(to: CGPoint(x: size.width, y: triggerY))
                    context.stroke(triggerPath, with: .color(.yellow.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                    
                    // 绘制绿色骨骼点
                    for point in model.detectedPoints {
                        let x = point.x * size.width
                        let y = (1 - point.y) * size.height
                        context.fill(Path(ellipseIn: CGRect(x: x-4, y: y-4, width: 8, height: 8)), with: .color(.green))
                    }
                    
                    // 特别标注红色脖子点
                    if let neck = model.neckPoint {
                        let x = neck.x * size.width
                        let y = (1 - neck.y) * size.height
                        context.stroke(Path(ellipseIn: CGRect(x: x-8, y: y-8, width: 16, height: 16)), with: .color(.red), lineWidth: 3)
                    }
                }
                .ignoresSafeArea()
                
                // 3. UI 控制层
                VStack {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("跳绳计数").font(.caption).foregroundColor(.white.opacity(0.8))
                            Text("\(model.jumpCount)").font(.system(size: 60, weight: .black, design: .rounded)).foregroundColor(.white)
                        }
                        .padding().background(Color.black.opacity(0.6)).cornerRadius(20)
                        
                        Spacer()
                        
                        Button(action: { model.jumpCount = 0 }) {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .resizable().frame(width: 44, height: 44).foregroundColor(.white)
                                .padding().background(Color.red.opacity(0.7)).clipShape(Circle())
                        }
                    }
                    .padding(.top, 50).padding(.horizontal)
                    
                    Spacer()
                    
                    // 灵敏度调节
                    VStack(spacing: 10) {
                        HStack {
                            Text("阈值 (灵敏度):").font(.caption).foregroundColor(.white)
                            Spacer()
                            Text(String(format: "%.3f", model.threshold)).foregroundColor(.yellow).bold()
                        }
                        Slider(value: $model.threshold, in: 0.005...0.10, step: 0.001).accentColor(.yellow)
                    }
                    .padding().background(Color.black.opacity(0.6)).cornerRadius(15).padding(.horizontal)
                    
                    // AI 状态
                    VStack(spacing: 4) {
                        HStack {
                            Circle().fill(model.isDetecting ? Color.green : Color.red).frame(width: 12, height: 12)
                            Text("AI 状态: \(model.currentAction)").font(.headline).foregroundColor(.white)
                            Spacer()
                            Text(String(format: "信心度: %.0f%%", model.actionConfidence * 100)).font(.caption).foregroundColor(.white.opacity(0.8))
                        }
                    }
                    .padding(15).background(Color.black.opacity(0.4)).cornerRadius(20).padding(.bottom, 30)
                }
            }
        }
        .onAppear { model.checkPermissions() }
    }
}

// 相机预览实现
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
    class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// 核心逻辑模型
class CameraViewModel: NSObject, ObservableObject {
    @Published var jumpCount = 0
    @Published var isDetecting = false
    @Published var detectedPoints: [CGPoint] = []
    @Published var neckPoint: CGPoint? = nil
    @Published var currentAction = "等待中..."
    @Published var actionConfidence: Double = 0.0
    @Published var threshold: CGFloat = 0.04
    @Published var baselineY: CGFloat = 0
    
    let session = AVCaptureSession()
    let videoOutput = AVCaptureVideoDataOutput()
    var poseObservations: [VNHumanBodyPoseObservation] = []
    let windowSize = 30
    
    private enum JumpState { case standing, jumping }
    private var jumpState: JumpState = .standing
    private var lastStateChangeTime = Date()
    
    override init() {
        super.init()
        setupSession()
    }
    
    func checkPermissions() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            if granted { DispatchQueue.main.async { self.startSession() } }
        }
    }
    
    private func setupSession() {
        session.sessionPreset = .high
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) { session.addInput(input) }
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
    }
    
    private func startSession() {
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
        }
    }
    
    func processJumpLogic(currentY: CGFloat) {
        if baselineY == 0 { baselineY = currentY; return }
        let now = Date()
        
        // 自动重置超时：防止卡在起跳状态
        if jumpState == .jumping && now.timeIntervalSince(lastStateChangeTime) > 1.5 {
            jumpState = .standing
            baselineY = currentY
            lastStateChangeTime = now
            return
        }
        
        switch jumpState {
        case .standing:
            if currentY > baselineY + threshold {
                // 只有当 AI 状态为跳绳时才进入起跳逻辑
                if currentAction == "jumping" || currentAction == "JumpRope" {
                    jumpState = .jumping
                    lastStateChangeTime = now
                }
            } else {
                // 站立时平滑更新基准线
                baselineY = baselineY * 0.8 + currentY * 0.2
            }
        case .jumping:
            if currentY < baselineY + (threshold * 0.5) {
                jumpState = .standing
                jumpCount += 1
                lastStateChangeTime = now
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }
        }
    }
}

// 视频流扩展
extension CameraViewModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cmSampleBuffer: sampleBuffer, orientation: .right, options: [:])
        
        do {
            try handler.perform([request])
            guard let observation = request.results?.first else {
                DispatchQueue.main.async { self.isDetecting = false; self.detectedPoints = [] }
                return
            }
            
            poseObservations.append(observation)
            if poseObservations.count > windowSize {
                poseObservations.removeFirst()
                performActionClassification()
            }
            
            let allJoints = try? observation.recognizedPoints(.all)
            let points = allJoints?.values.filter { $0.confidence > 0.3 }.map { CGPoint(x: $0.location.x, y: $0.location.y) } ?? []
            
            var currentNeck: CGPoint? = nil
            if let neck = try? observation.recognizedPoint(.neck), neck.confidence > 0.3 {
                currentNeck = CGPoint(x: neck.location.x, y: neck.location.y)
            }
            
            DispatchQueue.main.async {
                self.isDetecting = true
                self.detectedPoints = points
                self.neckPoint = currentNeck
                if let neckY = currentNeck?.y {
                    self.processJumpLogic(currentY: neckY)
                }
            }
        } catch { print(error) }
    }
    
    private func performActionClassification() {
        guard let model = try? JumpRopeClassifier(configuration: MLModelConfiguration()) else { return }
        do {
            let input = try poseObservations.makeMultiArray(windowLength: windowSize)
            let prediction = try model.prediction(poses: input)
            DispatchQueue.main.async {
                self.currentAction = prediction.label
                self.actionConfidence = prediction.labelProbabilities[prediction.label] ?? 0.0
            }
        } catch { print(error) }
    }
}

// 数据转换扩展
extension Array where Element == VNHumanBodyPoseObservation {
    func makeMultiArray(windowLength: Int) throws -> MLMultiArray {
        let multiArray = try MLMultiArray(shape: [windowLength as NSNumber, 3, 18], dataType: .float32)
        for (frameIndex, observation) in self.enumerated() {
            let joints = try observation.keypointsMultiArray()
            for i in 0..<joints.count {
                let index = [frameIndex as NSNumber, (i / 18) as NSNumber, (i % 18) as NSNumber]
                multiArray[index] = joints[i]
            }
        }
        return multiArray
    }
}
