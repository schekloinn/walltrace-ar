import ARKit
import AVFoundation
import SceneKit
import UIKit
import UniformTypeIdentifiers
import simd

// State and scene mutations use the main queue. Renderer callbacks are forwarded
// there and checked against the current anchor, so late callbacks are harmless.
final class WallTraceViewController: UIViewController, ARSCNViewDelegate,
                                     ARSessionDelegate, UIDocumentPickerDelegate {
    private let sceneView = ARSCNView(frame: .zero)
    private let trackingLabel = UILabel()
    private let instructionLabel = UILabel()
    private let fileLabel = UILabel()
    private let widthLabel = UILabel()
    private let opacityLabel = UILabel()
    private let crosshair = UILabel()
    private let importButton = UIButton(type: .system)
    private let placeButton = UIButton(type: .system)
    private let repositionButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let widthSlider = UISlider()
    private let opacitySlider = UISlider()
    private var image: UIImage?
    private var imageNode: SCNNode?
    private var imageAnchor: ARAnchor?
    private var running = false
    private var needsReset = true
    private var importing = false
    private var interrupted = false
    private var lastUIUpdate: TimeInterval = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        sceneView.scene = SCNScene()
        sceneView.delegate = self
        sceneView.session.delegate = self
        sceneView.session.delegateQueue = .main
        sceneView.preferredFramesPerSecond = 30
        sceneView.automaticallyUpdatesLighting = false
        buildUI()
        NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        prepareCamera()
    }

    private func buildUI() {
        sceneView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sceneView)
        NSLayoutConstraint.activate([
            sceneView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sceneView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            sceneView.topAnchor.constraint(equalTo: view.topAnchor),
            sceneView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        for label in [trackingLabel, instructionLabel, fileLabel, widthLabel, opacityLabel] {
            label.textColor = .white
            label.font = .systemFont(ofSize: 13)
            label.numberOfLines = 0
        }
        trackingLabel.font = .boldSystemFont(ofSize: 14)
        trackingLabel.text = "Підготовка камери…"
        instructionLabel.text = "Імпортуйте PNG і повільно огляньте стіну."
        fileLabel.text = "PNG ще не вибрано"
        fileLabel.numberOfLines = 1
        fileLabel.lineBreakMode = .byTruncatingMiddle
        configure(importButton, "Імпорт PNG", #selector(importPNG))
        configure(placeButton, "Розмістити на стіні", #selector(placeImage))
        configure(repositionButton, "Перемістити", #selector(reposition))
        configure(resetButton, "Скинути AR", #selector(resetSession))
        configure(settingsButton, "Дозволити камеру в Параметрах", #selector(openSettings))
        settingsButton.isHidden = true
        placeButton.isEnabled = false
        repositionButton.isEnabled = false
        widthSlider.minimumValue = 0.05
        widthSlider.maximumValue = 2.0
        widthSlider.value = 0.5
        widthSlider.accessibilityLabel = "Ширина зображення в метрах"
        widthSlider.addTarget(self, action: #selector(appearanceChanged), for: .valueChanged)
        opacitySlider.minimumValue = 0.05
        opacitySlider.maximumValue = 1
        opacitySlider.value = 0.65
        opacitySlider.accessibilityLabel = "Непрозорість зображення"
        opacitySlider.addTarget(self, action: #selector(appearanceChanged), for: .valueChanged)
        let header = panel([trackingLabel, instructionLabel, settingsButton])
        let buttons = UIStackView(arrangedSubviews: [importButton, repositionButton, resetButton])
        buttons.axis = .horizontal
        buttons.distribution = .fillEqually
        buttons.spacing = 4
        let footer = panel([fileLabel, buttons, widthLabel, widthSlider,
                            opacityLabel, opacitySlider, placeButton])
        for panelView in [header, footer] {
            panelView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(panelView)
            NSLayoutConstraint.activate([
                panelView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
                panelView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10)
            ])
        }
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6)
        ])
        crosshair.text = "+"
        crosshair.font = .systemFont(ofSize: 36, weight: .light)
        crosshair.textColor = .white
        crosshair.isUserInteractionEnabled = false
        crosshair.isAccessibilityElement = false
        crosshair.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(crosshair)
        NSLayoutConstraint.activate([
            crosshair.centerXAnchor.constraint(equalTo: sceneView.centerXAnchor),
            crosshair.centerYAnchor.constraint(equalTo: sceneView.centerYAnchor)
        ])
        appearanceChanged()
    }

    private func panel(_ children: [UIView]) -> UIView {
        let stack = UIStackView(arrangedSubviews: children)
        stack.axis = .vertical
        stack.spacing = 5
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(top: 9, left: 10, bottom: 9, right: 10)
        stack.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        stack.layer.cornerRadius = 12
        return stack
    }

    private func configure(_ button: UIButton, _ title: String, _ action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.tintColor = .systemYellow
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func prepareCamera() {
        guard ARWorldTrackingConfiguration.isSupported else {
            running = false
            trackingLabel.text = "ARKit не підтримується на цьому пристрої."
            instructionLabel.text = "Потрібен сумісний фізичний iPhone; симулятор не підтримує AR."
            placeButton.isEnabled = false
            resetButton.isEnabled = false
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            settingsButton.isHidden = true
            if !running && UIApplication.shared.applicationState == .active { startSession() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async { self?.prepareCamera() }
            }
        case .denied, .restricted:
            sceneView.session.pause()
            running = false
            needsReset = true
            clearPlacement()
            trackingLabel.text = "Немає доступу до камери."
            instructionLabel.text = "Дозвольте камеру для WallTrace AR у Параметрах. Обмеження системи може змінити лише власник."
            settingsButton.isHidden = false
        @unknown default:
            trackingLabel.text = "Невідомий стан дозволу камери."
        }
    }

    private func startSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.vertical]
        configuration.worldAlignment = .gravity
        let options: ARSession.RunOptions = needsReset ? [.resetTracking, .removeExistingAnchors] : []
        if needsReset { clearPlacement() }
        sceneView.session.run(configuration, options: options)
        needsReset = false
        interrupted = false
        running = true
        lastUIUpdate = 0
        trackingLabel.text = "Трекінг: ініціалізація…"
        instructionLabel.text = "Повільно огляньте добре освітлену стіну з деталями."
        UIApplication.shared.isIdleTimerDisabled = true
    }

    @objc private func enteredBackground() {
        sceneView.session.pause()
        running = false
        needsReset = true
        clearPlacement()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    @objc private func becameActive() {
        guard isViewLoaded, view.window != nil else { return }
        prepareCamera()
    }

    @objc private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @objc private func resetSession() {
        needsReset = true
        running = false
        sceneView.session.pause()
        clearPlacement()
        prepareCamera()
    }

    @objc private func reposition() {
        clearPlacement()
        instructionLabel.text = "Наведіть + на інше місце стіни й натисніть «Розмістити»."
    }

    private func clearPlacement() {
        if let anchor = imageAnchor { sceneView.session.remove(anchor: anchor) }
        imageAnchor = nil
        imageNode?.removeFromParentNode()
        imageNode = nil
        repositionButton.isEnabled = false
        placeButton.isEnabled = false
        crosshair.isHidden = false
    }

    private func wallHit() -> ARRaycastResult? {
        guard running, !interrupted,
              let frame = sceneView.session.currentFrame,
              case .normal = frame.camera.trackingState,
              let query = sceneView.raycastQuery(from: CGPoint(x: sceneView.bounds.midX, y: sceneView.bounds.midY),
                                                 allowing: .existingPlaneGeometry, alignment: .vertical) else { return nil }
        return sceneView.session.raycast(query).first { result in
            (result.anchor as? ARPlaneAnchor)?.alignment == .vertical
        }
    }

    @objc private func placeImage() {
        guard image != nil, imageAnchor == nil, !importing,
              let hit = wallHit(), let frame = sceneView.session.currentFrame else { return }
        // Raycast local Y is the surface normal. Build an upright XY image plane
        // with +Z facing the camera, using gravity for up (never a billboard).
        let point = SIMD3<Float>(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y,
                                 hit.worldTransform.columns.3.z)
        var normal = SIMD3<Float>(hit.worldTransform.columns.1.x, 0, hit.worldTransform.columns.1.z)
        guard simd_length(normal) > 0.001 else { return }
        normal = simd_normalize(normal)
        let camera = SIMD3<Float>(frame.camera.transform.columns.3.x, frame.camera.transform.columns.3.y,
                                  frame.camera.transform.columns.3.z)
        if simd_dot(normal, camera - point) < 0 { normal = -normal }
        let up = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(up, normal))
        let position = point + normal * 0.005
        let transform = simd_float4x4(columns: (SIMD4<Float>(right, 0), SIMD4<Float>(up, 0),
                                               SIMD4<Float>(normal, 0), SIMD4<Float>(position, 1)))
        let anchor = ARAnchor(name: "WallTrace.image", transform: transform)
        imageAnchor = anchor
        sceneView.session.add(anchor: anchor)
        placeButton.isEnabled = false
        repositionButton.isEnabled = true
        crosshair.isHidden = true
        instructionLabel.text = "Закріплено у світі. Для нового місця натисніть «Перемістити»."
    }

    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, anchor.identifier == self.imageAnchor?.identifier,
                  self.image != nil else { return }
            let plane = SCNPlane(width: 1, height: 1)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.isDoubleSided = true
            material.diffuse.contents = self.image
            material.blendMode = .alpha
            material.writesToDepthBuffer = false
            plane.materials = [material]
            let content = SCNNode(geometry: plane)
            node.addChildNode(content)
            self.imageNode = content
            self.appearanceChanged()
        }
    }

    @objc private func appearanceChanged() {
        let width = CGFloat(widthSlider.value)
        widthLabel.text = String(format: "Ширина: %.0f см (масштаб)", width * 100)
        opacityLabel.text = String(format: "Непрозорість: %.0f %%", opacitySlider.value * 100)
        widthSlider.accessibilityValue = widthLabel.text
        opacitySlider.accessibilityValue = opacityLabel.text
        if let plane = imageNode?.geometry as? SCNPlane, let image = image {
            plane.width = width
            plane.height = width * image.size.height / image.size.width
            imageNode?.opacity = CGFloat(opacitySlider.value)
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running, !interrupted, frame.timestamp - lastUIUpdate >= 0.25 else { return }
        lastUIUpdate = frame.timestamp
        let normal: Bool
        switch frame.camera.trackingState {
        case .normal:
            normal = true
            trackingLabel.text = "Трекінг: нормальний • стін: \(frame.anchors.compactMap { $0 as? ARPlaneAnchor }.filter { $0.alignment == .vertical }.count)"
        case .notAvailable:
            normal = false
            trackingLabel.text = "Трекінг недоступний. Спробуйте «Скинути AR»."
        case .limited(let reason):
            normal = false
            switch reason {
            case .initializing: trackingLabel.text = "Трекінг: ініціалізація — повільно огляньте стіну."
            case .excessiveMotion: trackingLabel.text = "Трекінг обмежений — рухайте телефон повільніше."
            case .insufficientFeatures: trackingLabel.text = "Мало деталей — додайте світла, знайдіть текстуру."
            case .relocalizing: trackingLabel.text = "Відновлення трекінгу — наведіть на попередню ділянку."
            @unknown default: trackingLabel.text = "Трекінг обмежений."
            }
        }
        imageNode?.isHidden = !normal
        guard imageAnchor == nil else { return }
        let hit = normal && wallHit() != nil
        crosshair.textColor = hit ? .systemGreen : .white
        placeButton.isEnabled = hit && image != nil && !importing
        if importing { return }
        if image == nil {
            instructionLabel.text = "Імпортуйте PNG через «Файли»."
        } else if hit {
            instructionLabel.text = "Стіну під + знайдено. Натисніть «Розмістити на стіні»."
        } else {
            instructionLabel.text = "Наведіть + на знайдену стіну. Повільно огляньте її з різних боків."
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        interrupted = true
        placeButton.isEnabled = false
        imageNode?.isHidden = true
        trackingLabel.text = "AR перервано системою."
    }

    func sessionInterruptionEnded(_ session: ARSession) { resetSession() }

    func session(_ session: ARSession, didFailWithError error: Error) {
        running = false
        needsReset = true
        clearPlacement()
        trackingLabel.text = "Помилка AR: \(error.localizedDescription)"
        instructionLabel.text = "Перевірте дозвіл камери та натисніть «Скинути AR»."
        UIApplication.shared.isIdleTimerDisabled = false
    }

    @objc private func importPNG() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.png], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        importing = true
        importButton.isEnabled = false
        placeButton.isEnabled = false
        fileLabel.text = "Завантаження PNG…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try PNGImporter.load(url) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.importing = false
                self.importButton.isEnabled = true
                switch result {
                case .success(let image):
                    self.clearPlacement()
                    self.image = image
                    self.fileLabel.text = url.lastPathComponent
                    self.appearanceChanged()
                case .failure(let error):
                    self.fileLabel.text = self.image == nil ? "PNG ще не вибрано" : "Попередній PNG збережено"
                    let alert = UIAlertController(title: "Не вдалося відкрити PNG",
                                                  message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Гаразд", style: .default))
                    self.present(alert, animated: true)
                }
            }
        }
    }
}
