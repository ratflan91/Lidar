import UIKit
import ARKit
import Metal
import MetalKit

class ViewController: UIViewController {

    private var session: ARSession!
    private var mtkView: MTKView!
    private var renderer: DepthMapRenderer!

    private var modeButton: UIButton!
    private var freezeButton: UIButton!
    private var depthLabel: UILabel!
    private var isFrozen = false

    private let modeNames  = ["Gradient", "Contour", "Combined", "Camera Only"]
    private let modeIcons  = ["paintpalette", "waveform.path", "square.3.layers.3d", "camera"]

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupMetal()
        setupSession()
        setupUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !isFrozen else { return }
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.pause()
    }

    // MARK: - Setup

    private func setupMetal() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            showAlert(title: "Metal Unavailable",
                      message: "This device does not support Metal rendering.")
            return
        }
        mtkView = MTKView(frame: view.bounds, device: device)
        mtkView.autoresizingMask    = [.flexibleWidth, .flexibleHeight]
        mtkView.framebufferOnly     = false
        mtkView.colorPixelFormat    = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 60
        view.addSubview(mtkView)

        renderer      = DepthMapRenderer(device: device, mtkView: mtkView)
        mtkView.delegate = renderer
    }

    private func setupSession() {
        session          = ARSession()
        session.delegate = self
    }

    private func startSession() {
        guard ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) else {
            showAlert(
                title: "LiDAR Not Available",
                message: "A LiDAR-equipped device is required (iPhone 12 Pro or later / iPad Pro)."
            )
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    // MARK: - UI

    private func setupUI() {
        // Depth readout banner
        depthLabel = UILabel()
        depthLabel.text          = "  Depth: ---  "
        depthLabel.textColor     = .white
        depthLabel.font          = .monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
        depthLabel.backgroundColor      = UIColor.black.withAlphaComponent(0.65)
        depthLabel.textAlignment        = .center
        depthLabel.layer.cornerRadius   = 12
        depthLabel.clipsToBounds        = true
        depthLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(depthLabel)

        // Mode cycle button
        modeButton = makeButton(title: modeNames[0], systemImage: modeIcons[0])
        modeButton.addTarget(self, action: #selector(cycleModePressed), for: .touchUpInside)
        view.addSubview(modeButton)

        // Freeze / unfreeze button
        freezeButton = makeButton(title: "Freeze", systemImage: "pause.circle")
        freezeButton.addTarget(self, action: #selector(toggleFreezePressed), for: .touchUpInside)
        view.addSubview(freezeButton)

        // Crosshair overlay
        let crosshair = CrosshairView()
        crosshair.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(crosshair)

        NSLayoutConstraint.activate([
            depthLabel.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            depthLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            depthLabel.heightAnchor.constraint(equalToConstant: 48),
            depthLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 190),

            modeButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            modeButton.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: 24),

            freezeButton.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            freezeButton.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -24),

            crosshair.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            crosshair.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            crosshair.widthAnchor.constraint(equalToConstant: 48),
            crosshair.heightAnchor.constraint(equalToConstant: 48),
        ])
    }

    private func makeButton(title: String, systemImage: String) -> UIButton {
        var cfg = UIButton.Configuration.filled()
        cfg.title               = title
        cfg.image               = UIImage(systemName: systemImage)
        cfg.imagePlacement      = .leading
        cfg.imagePadding        = 6
        cfg.baseBackgroundColor = UIColor.black.withAlphaComponent(0.7)
        cfg.baseForegroundColor = .white
        cfg.cornerStyle         = .medium
        cfg.contentInsets       = NSDirectionalEdgeInsets(
            top: 11, leading: 16, bottom: 11, trailing: 16)
        let btn = UIButton(configuration: cfg)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }

    // MARK: - Actions

    @objc private func cycleModePressed() {
        renderer.cycleMode()
        let i = renderer.mode.rawValue
        var cfg = modeButton.configuration
        cfg?.title = modeNames[i]
        cfg?.image = UIImage(systemName: modeIcons[i])
        modeButton.configuration = cfg
    }

    @objc private func toggleFreezePressed() {
        isFrozen.toggle()
        var cfg = freezeButton.configuration
        if isFrozen {
            session.pause()
            cfg?.title               = "Unfreeze"
            cfg?.image               = UIImage(systemName: "play.circle")
            cfg?.baseBackgroundColor = UIColor.systemRed.withAlphaComponent(0.85)
        } else {
            startSession()
            cfg?.title               = "Freeze"
            cfg?.image               = UIImage(systemName: "pause.circle")
            cfg?.baseBackgroundColor = UIColor.black.withAlphaComponent(0.7)
        }
        freezeButton.configuration = cfg
    }

    private func showAlert(title: String, message: String) {
        DispatchQueue.main.async {
            let alert = UIAlertController(
                title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }
}

// MARK: - ARSessionDelegate

extension ViewController: ARSessionDelegate {

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        renderer.update(frame: frame)

        let depthMap = frame.smoothedSceneDepth?.depthMap ?? frame.sceneDepth?.depthMap
        guard let depthMap else { return }

        let centerDepth = sampleCenterDepth(from: depthMap)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if centerDepth > 0.05 && centerDepth < 15 {
                self.depthLabel.text      = String(format: "  %.2f m  ", centerDepth)
                self.depthLabel.textColor = self.colorForDepth(centerDepth)
            } else {
                self.depthLabel.text      = "  Depth: ---  "
                self.depthLabel.textColor = .white
            }
        }
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        showAlert(title: "ARSession Error", message: error.localizedDescription)
    }

    private func sampleCenterDepth(from pixelBuffer: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return 0 }
        let w = CVPixelBufferGetWidth(pixelBuffer)
        let h = CVPixelBufferGetHeight(pixelBuffer)
        let floats = base.assumingMemoryBound(to: Float32.self)
        let val = floats[(h / 2) * w + (w / 2)]
        return val.isFinite ? val : 0
    }

    private func colorForDepth(_ d: Float) -> UIColor {
        switch d {
        case ..<0.5:  return .systemRed
        case ..<1.0:  return .systemOrange
        case ..<2.0:  return .systemYellow
        case ..<4.0:  return .systemGreen
        default:      return .systemCyan
        }
    }
}

// MARK: - CrosshairView

private final class CrosshairView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor            = .clear
        isUserInteractionEnabled   = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }

        let cx = rect.midX, cy = rect.midY
        let arm: CGFloat = 14, gap: CGFloat = 5

        ctx.setShadow(offset: .zero, blur: 4, color: UIColor.black.cgColor)
        ctx.setStrokeColor(UIColor.white.cgColor)
        ctx.setLineWidth(2)

        // Horizontal arms
        ctx.move(to: CGPoint(x: cx - arm, y: cy))
        ctx.addLine(to: CGPoint(x: cx - gap, y: cy))
        ctx.move(to: CGPoint(x: cx + gap, y: cy))
        ctx.addLine(to: CGPoint(x: cx + arm, y: cy))

        // Vertical arms
        ctx.move(to: CGPoint(x: cx, y: cy - arm))
        ctx.addLine(to: CGPoint(x: cx, y: cy - gap))
        ctx.move(to: CGPoint(x: cx, y: cy + gap))
        ctx.addLine(to: CGPoint(x: cx, y: cy + arm))

        ctx.strokePath()

        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fillEllipse(in: CGRect(x: cx - 2.5, y: cy - 2.5, width: 5, height: 5))
    }
}
