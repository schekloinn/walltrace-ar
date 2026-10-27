import ARKit
import AVFoundation
import SceneKit
import UIKit
import UniformTypeIdentifiers
import simd

// All image state and SceneKit mutations are serialized on the main queue.
final class WallTraceViewController: UIViewController, ARSessionDelegate, UIDocumentPickerDelegate {
    private final class Placement {
        let anchor: ARAnchor
        let node: SCNNode
        var stabilizer: AnchorStabilizer
        init(anchor: ARAnchor, node: SCNNode, timestamp: TimeInterval, restoring: Bool = false) {
            self.anchor = anchor
            self.node = node
            stabilizer = AnchorStabilizer(transform: anchor.transform, timestamp: timestamp, requiresRecovery: restoring)
        }
    }

    private let sceneView = ARSCNView(frame: .zero)
    private let trackingLabel = UILabel()
    private let instructionLabel = UILabel()
    private let fileLabel = UILabel()
    private let widthLabel = UILabel()
    private let opacityLabel = UILabel()
    private let safetyLabel = UILabel()
    private let crosshair = UILabel()
    private let slotControl = UISegmentedControl(items: ["1 · +", "2 · +", "3 · +"])
    private let importButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)
    private let placeButton = UIButton(type: .system)
    private let repositionButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let saveButton = UIButton(type: .system)
    private let restoreButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let interfaceButton = UIButton(type: .system)
    private let widthSlider = UISlider()
    private let opacitySlider = UISlider()
    private var header: UIView!
    private var footer: UIView!
    private var images = ImageSlots<UIImage>()
    private var placements: [Placement?] = [nil, nil, nil]
    private var interfaceHidden = false
    private var running = false
    private var needsReset = true
    private var importing = false
    private var storageBusy = false
    private var autoRestorePending = true
    private var sessionRevision = 0
    private var hasSavedProject = false
    private let storageQueue = DispatchQueue(label: "local.walltrace.storage", qos: .userInitiated)
    private var projectURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WallTraceAR", isDirectory: true).appendingPathComponent("project-v1.json")
    }
    private var interrupted = false
    private var lastUIUpdate: TimeInterval = 0
    private var normalTrackingSince: TimeInterval?
    private var previousCamera: simd_float4x4?
    private var previousFrameTime: TimeInterval = 0
    private var recoveryUntil: TimeInterval = 0
    private var protectionMessage: String?

    override var prefersStatusBarHidden: Bool { interfaceHidden }
    override var prefersHomeIndicatorAutoHidden: Bool { interfaceHidden }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        sceneView.scene = SCNScene()
        sceneView.session.delegate = self
        sceneView.session.delegateQueue = .main
        sceneView.preferredFramesPerSecond = 30
        sceneView.automaticallyUpdatesLighting = false
        hasSavedProject = FileManager.default.fileExists(atPath: projectURL.path)
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
        for label in [trackingLabel, instructionLabel, fileLabel, widthLabel, opacityLabel, safetyLabel] {
            label.textColor = .white
            label.font = .systemFont(ofSize: 13)
            label.numberOfLines = 0
        }
        trackingLabel.font = .boldSystemFont(ofSize: 14)
        trackingLabel.text = "Підготовка камери…"
        instructionLabel.text = "Виберіть слот 1–3 та імпортуйте PNG."
        fileLabel.numberOfLines = 1
        fileLabel.lineBreakMode = .byTruncatingMiddle
        configure(importButton, "Імпорт PNG", #selector(importPNG))
        configure(deleteButton, "Видалити", #selector(deleteImage))
        configure(placeButton, "Розмістити на стіні", #selector(placeImage))
        configure(repositionButton, "Перемістити", #selector(reposition))
        configure(resetButton, "Скинути AR", #selector(resetSession))
        configure(saveButton, "Зберегти", #selector(saveProject))
        configure(restoreButton, "Відновити", #selector(restoreProject))
        saveButton.accessibilityHint = "Збережіть сцену перед виходом. Спочатку проскануйте кімнату."
        restoreButton.accessibilityHint = "Завантажити останні збережені PNG, карту кімнати та позиції"
        configure(settingsButton, "Дозволити камеру в Параметрах", #selector(openSettings))
        settingsButton.isHidden = true
        slotControl.selectedSegmentIndex = 0
        slotControl.selectedSegmentTintColor = .systemYellow
        slotControl.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
        slotControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        slotControl.accessibilityLabel = "Вибране зображення, слот від 1 до 3"
        slotControl.addTarget(self, action: #selector(slotChanged), for: .valueChanged)
        slotControl.heightAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        widthSlider.minimumValue = 0.05
        widthSlider.maximumValue = 2
        widthSlider.accessibilityLabel = "Ширина вибраного зображення в метрах"
        widthSlider.addTarget(self, action: #selector(appearanceChanged), for: .valueChanged)
        opacitySlider.minimumValue = 0.05
        opacitySlider.maximumValue = 1
        opacitySlider.accessibilityLabel = "Непрозорість вибраного зображення"
        opacitySlider.addTarget(self, action: #selector(appearanceChanged), for: .valueChanged)
        header = panel([trackingLabel, instructionLabel, settingsButton])
        let buttons = UIStackView(arrangedSubviews: [importButton, deleteButton, repositionButton, resetButton])
        buttons.distribution = .fillEqually
        buttons.spacing = 3
        let storageButtons = UIStackView(arrangedSubviews: [saveButton, restoreButton])
        storageButtons.distribution = .fillEqually
        storageButtons.spacing = 8
        footer = panel([slotControl, fileLabel, buttons, sliderRow(widthLabel, widthSlider),
                        sliderRow(opacityLabel, opacitySlider), storageButtons, placeButton])
        for panelView in [header!, footer!] {
            panelView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(panelView)
        }
        interfaceButton.translatesAutoresizingMaskIntoConstraints = false
        interfaceButton.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        interfaceButton.layer.cornerRadius = 22
        interfaceButton.tintColor = .systemYellow
        interfaceButton.addTarget(self, action: #selector(toggleInterface), for: .touchUpInside)
        view.addSubview(interfaceButton)
        NSLayoutConstraint.activate([
            interfaceButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            interfaceButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            interfaceButton.widthAnchor.constraint(equalToConstant: 44),
            interfaceButton.heightAnchor.constraint(equalToConstant: 44),
            header.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            header.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            header.trailingAnchor.constraint(equalTo: interfaceButton.leadingAnchor, constant: -6),
            footer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            footer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6)
        ])
        let aimArea = UILayoutGuide()
        view.addLayoutGuide(aimArea)
        NSLayoutConstraint.activate([
            aimArea.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            aimArea.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
            aimArea.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            aimArea.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        crosshair.text = "+"
        crosshair.font = .systemFont(ofSize: 34, weight: .light)
        crosshair.textColor = .white
        crosshair.isUserInteractionEnabled = false
        crosshair.isAccessibilityElement = false
        crosshair.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(crosshair)
        NSLayoutConstraint.activate([
            crosshair.centerXAnchor.constraint(equalTo: aimArea.centerXAnchor),
            crosshair.centerYAnchor.constraint(equalTo: aimArea.centerYAnchor)
        ])
        safetyLabel.translatesAutoresizingMaskIntoConstraints = false
        safetyLabel.textAlignment = .center
        safetyLabel.textColor = .systemYellow
        safetyLabel.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        safetyLabel.layer.cornerRadius = 8
        safetyLabel.clipsToBounds = true
        safetyLabel.isHidden = true
        safetyLabel.isUserInteractionEnabled = false
        view.addSubview(safetyLabel)
        NSLayoutConstraint.activate([
            safetyLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 18),
            safetyLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            safetyLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])
        updateSelectedUI()
        setInterfaceHidden(false)
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

    private func sliderRow(_ label: UILabel, _ slider: UISlider) -> UIView {
        label.widthAnchor.constraint(equalToConstant: 135).isActive = true
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        let row = UIStackView(arrangedSubviews: [label, slider])
        row.spacing = 8
        row.alignment = .center
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).isActive = true
        return row
    }

    private func configure(_ button: UIButton, _ title: String, _ action: Selector) {
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.75
        button.tintColor = .systemYellow
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    @objc private func toggleInterface() { setInterfaceHidden(!interfaceHidden) }

    private func setInterfaceHidden(_ hidden: Bool) {
        interfaceHidden = hidden
        header.isHidden = hidden
        footer.isHidden = hidden
        crosshair.isHidden = hidden || placements[images.selectedIndex] != nil
        interfaceButton.setImage(UIImage(systemName: hidden ? "eye" : "eye.slash"), for: .normal)
        interfaceButton.accessibilityLabel = hidden ? "Показати інтерфейс" : "Сховати інтерфейс"
        interfaceButton.accessibilityHint = "Зображення залишаються на стіні"
        safetyLabel.isHidden = !hidden || protectionMessage == nil
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
    }

    @objc private func slotChanged() {
        images.select(slotControl.selectedSegmentIndex)
        updateSelectedUI()
    }

    private func updateSelectedUI() {
        let item = images[images.selectedIndex]
        widthSlider.value = item.width
        opacitySlider.value = item.opacity
        let busy = importing || storageBusy
        fileLabel.text = storageBusy ? "Збереження / відновлення сцени…" : importing ? "Завантаження PNG…" : "\(images.selectedIndex + 1)/3 · \(item.content == nil ? "Порожній слот — імпортуйте PNG" : item.name)"
        for index in 0..<ImageSlots<UIImage>.capacity {
            let state = images[index].content == nil ? "+" : (placements[index] == nil ? "PNG" : "✓")
            slotControl.setTitle("\(index + 1) · \(state)", forSegmentAt: index)
        }
        importButton.isEnabled = !busy
        slotControl.isEnabled = !busy
        resetButton.isEnabled = !busy && ARWorldTrackingConfiguration.isSupported
        deleteButton.isEnabled = !busy && item.content != nil
        repositionButton.isEnabled = !busy && placements[images.selectedIndex] != nil
        widthSlider.isEnabled = !busy && item.content != nil
        opacitySlider.isEnabled = !busy && item.content != nil
        placeButton.isEnabled = !busy && item.content != nil && placements[images.selectedIndex] == nil && wallHit() != nil
        crosshair.isHidden = interfaceHidden || placements[images.selectedIndex] != nil
        saveButton.isEnabled = !busy && canSaveProject()
        restoreButton.isEnabled = !busy && hasSavedProject
        updateAppearance()
    }

    @objc private func appearanceChanged() {
        images.setAppearance(width: widthSlider.value, opacity: opacitySlider.value)
        updateAppearance()
    }

    private func updateAppearance() {
        let index = images.selectedIndex
        let item = images[index]
        widthLabel.text = String(format: "Ширина: %.0f см", item.width * 100)
        opacityLabel.text = String(format: "Непрозорість: %.0f %%", item.opacity * 100)
        widthSlider.accessibilityValue = widthLabel.text
        opacitySlider.accessibilityValue = opacityLabel.text
        if let plane = placements[index]?.node.geometry as? SCNPlane, let image = item.content {
            plane.width = CGFloat(item.width)
            plane.height = CGFloat(item.width) * image.size.height / image.size.width
            placements[index]?.node.opacity = CGFloat(item.opacity)
        }
    }

    private func prepareCamera() {
        guard ARWorldTrackingConfiguration.isSupported else {
            running = false
            setInterfaceHidden(false)
            trackingLabel.text = "ARKit не підтримується на цьому пристрої."
            instructionLabel.text = "Потрібен сумісний фізичний iPhone; симулятор не підтримує AR."
            resetButton.isEnabled = false
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            settingsButton.isHidden = true
            if !running && !storageBusy && UIApplication.shared.applicationState == .active {
                if autoRestorePending && hasSavedProject { restoreProject() }
                else { startSession() }
            }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async { self?.prepareCamera() }
            }
        case .denied, .restricted:
            sceneView.session.pause()
            running = false
            needsReset = true
            clearAllPlacements()
            setInterfaceHidden(false)
            trackingLabel.text = "Немає доступу до камери."
            instructionLabel.text = "Дозвольте камеру для WallTrace AR у Параметрах."
            settingsButton.isHidden = false
        @unknown default:
            trackingLabel.text = "Невідомий стан дозволу камери."
        }
    }

    private func startSession(worldMap: ARWorldMap? = nil) {
        sessionRevision += 1
        autoRestorePending = false
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.vertical]
        configuration.worldAlignment = .gravity
        configuration.initialWorldMap = worldMap
        let options: ARSession.RunOptions = needsReset ? [.resetTracking, .removeExistingAnchors] : []
        if needsReset {
            clearAllPlacements()
            setInterfaceHidden(false)
        }
        sceneView.session.run(configuration, options: options)
        needsReset = false
        interrupted = false
        running = true
        normalTrackingSince = nil
        previousCamera = nil
        previousFrameTime = 0
        recoveryUntil = 0
        lastUIUpdate = 0
        trackingLabel.text = "Трекінг: ініціалізація…"
        instructionLabel.text = worldMap == nil ? "Повільно огляньте добре освітлену стіну з деталями." : "Знайдіть ту саму ділянку кімнати, щоб відновити позиції."
        UIApplication.shared.isIdleTimerDisabled = true
    }

    @objc private func enteredBackground() {
        sessionRevision += 1
        autoRestorePending = hasSavedProject
        sceneView.session.pause()
        running = false
        needsReset = true
        clearAllPlacements()
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
        autoRestorePending = false
        needsReset = true
        running = false
        sceneView.session.pause()
        clearAllPlacements()
        prepareCamera()
    }

    @objc private func reposition() {
        clearPlacement(at: images.selectedIndex)
        updateSelectedUI()
        instructionLabel.text = "Наведіть + на нове місце. Інші зображення залишаються на стінах."
    }

    @objc private func deleteImage() {
        clearPlacement(at: images.selectedIndex)
        images.removeSelected()
        updateSelectedUI()
    }

    private func clearPlacement(at index: Int) {
        guard let placement = placements[index] else { return }
        placements[index] = nil
        placement.node.removeFromParentNode()
        sceneView.session.remove(anchor: placement.anchor)
    }

    private func clearAllPlacements() {
        for index in 0..<placements.count { clearPlacement(at: index) }
        protectionMessage = nil
        safetyLabel.isHidden = true
        updateSelectedUI()
    }

    private func wallHit() -> ARRaycastResult? {
        guard running, !interrupted, let frame = sceneView.session.currentFrame,
              case .normal = frame.camera.trackingState,
              let since = normalTrackingSince, frame.timestamp - since >= 0.6,
              let query = sceneView.raycastQuery(from: crosshair.convert(CGPoint(x: crosshair.bounds.midX, y: crosshair.bounds.midY), to: sceneView),
                                                 allowing: .existingPlaneGeometry, alignment: .vertical) else { return nil }
        let camera = AnchorStabilizer.position(frame.camera.transform)
        return sceneView.session.raycast(query).first { result in
            guard (result.anchor as? ARPlaneAnchor)?.alignment == .vertical else { return false }
            let column = result.worldTransform.columns.1
            let normal = simd_normalize(SIMD3<Float>(column.x, 0, column.z))
            return abs(simd_dot(camera - AnchorStabilizer.position(result.worldTransform), normal)) >= 0.30
        }
    }

    @objc private func placeImage() {
        let index = images.selectedIndex
        guard let image = images[index].content, placements[index] == nil, !importing, !storageBusy,
              let hit = wallHit(), let frame = sceneView.session.currentFrame else { return }
        let point = AnchorStabilizer.position(hit.worldTransform)
        var normal = SIMD3<Float>(hit.worldTransform.columns.1.x, 0, hit.worldTransform.columns.1.z)
        guard simd_length(normal) > 0.001 else { return }
        normal = simd_normalize(normal)
        let camera = AnchorStabilizer.position(frame.camera.transform)
        if simd_dot(normal, camera - point) < 0 { normal = -normal }
        let up = SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(up, normal))
        let position = point + normal * (0.005 + Float(index) * 0.002)
        let transform = simd_float4x4(columns: (SIMD4<Float>(right, 0), SIMD4<Float>(up, 0),
                                               SIMD4<Float>(normal, 0), SIMD4<Float>(position, 1)))
        let anchor = ARAnchor(name: "WallTrace.image.\(index)", transform: transform)
        attachImage(at: index, image: image, anchor: anchor, timestamp: frame.timestamp, restoring: false)
        sceneView.session.add(anchor: anchor)
        updateSelectedUI()
    }

    private func attachImage(at index: Int, image: UIImage, anchor: ARAnchor,
                             timestamp: TimeInterval, restoring: Bool) {
        let item = images[index]
        let plane = SCNPlane(width: CGFloat(item.width), height: CGFloat(item.width) * image.size.height / image.size.width)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.diffuse.contents = image
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        plane.materials = [material]
        let node = SCNNode(geometry: plane)
        node.simdTransform = anchor.transform
        node.renderingOrder = index
        node.opacity = CGFloat(item.opacity)
        node.isHidden = restoring
        // Root content follows the persisted ARAnchor through the presentation filter.
        sceneView.scene.rootNode.addChildNode(node)
        placements[index] = Placement(anchor: anchor, node: node, timestamp: timestamp, restoring: restoring)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard running, !interrupted else { return }
        let cameraNormal: Bool
        if case .normal = frame.camera.trackingState { cameraNormal = true } else { cameraNormal = false }
        let camera = frame.camera.transform
        let dt = frame.timestamp - previousFrameTime
        if let previous = previousCamera, dt > 0, dt < 0.15 {
            let moved = simd_distance(AnchorStabilizer.position(camera), AnchorStabilizer.position(previous))
            let rotated = AnchorStabilizer.rotationDifference(simd_quatf(camera), simd_quatf(previous))
            if moved > 0.15 || rotated > 15 * .pi / 180 { recoveryUntil = frame.timestamp + 0.7 }
        }
        previousCamera = camera
        previousFrameTime = frame.timestamp
        let healthy = cameraNormal && frame.timestamp >= recoveryUntil
        if healthy {
            if normalTrackingSince == nil { normalTrackingSince = frame.timestamp }
        } else { normalTrackingSince = nil }
        var reasons: [AnchorStabilizer.Reason] = []
        for placement in placements.compactMap({ $0 }) {
            guard let anchor = frame.anchors.first(where: { $0.identifier == placement.anchor.identifier }) else {
                _ = placement.stabilizer.update(target: placement.node.simdTransform,
                    camera: AnchorStabilizer.position(camera), trackingNormal: false, timestamp: frame.timestamp)
                placement.node.isHidden = true
                reasons.append(.tracking)
                continue
            }
            let result = placement.stabilizer.update(target: anchor.transform, camera: AnchorStabilizer.position(camera),
                                                       trackingNormal: healthy, timestamp: frame.timestamp)
            placement.node.simdTransform = result.transform
            placement.node.isHidden = !result.visible
            reasons.append(result.reason)
        }
        if reasons.contains(.tooClose) {
            protectionMessage = "Надто близько до стіни — відійдіть щонайменше на 30 см."
        } else if reasons.contains(.correcting) {
            protectionMessage = "Уточнення якоря. Зображення тимчасово приховано; перевірте позицію після відновлення."
        } else if reasons.contains(.tracking) || reasons.contains(.recovering) {
            protectionMessage = "Відновлення трекінгу — повільно огляньте текстуровану стіну."
        } else { protectionMessage = nil }
        safetyLabel.text = protectionMessage
        safetyLabel.isHidden = !interfaceHidden || protectionMessage == nil
        guard frame.timestamp - lastUIUpdate >= 0.25 else { return }
        lastUIUpdate = frame.timestamp
        trackingLabel.text = healthy ? "Трекінг: нормальний · на стіні: \(placements.compactMap { $0 }.count)/3" : trackingDescription(frame.camera.trackingState)
        updateSelectedUI()
        if let protectionMessage = protectionMessage { instructionLabel.text = protectionMessage }
        else if placements[images.selectedIndex] != nil {
            instructionLabel.text = canSaveProject() ? "Зображення \(images.selectedIndex + 1) закріплено. Можна зберегти сцену або сховати UI." : "Зображення закріплено. Огляньте деталі навколо, щоб активувати «Зберегти»."
        } else if images[images.selectedIndex].content == nil {
            instructionLabel.text = "Оберіть слот 1–3 та імпортуйте PNG."
        } else if wallHit() != nil {
            instructionLabel.text = "Стіну під + знайдено. Натисніть «Розмістити на стіні»."
        } else {
            instructionLabel.text = "Наведіть + на знайдену стіну з відстані від 30 см."
        }
        crosshair.textColor = wallHit() == nil ? .white : .systemGreen
    }

    private func trackingDescription(_ state: ARCamera.TrackingState) -> String {
        switch state {
        case .normal: return "Стабілізація після різкого руху…"
        case .notAvailable: return "Трекінг недоступний. Спробуйте «Скинути AR»."
        case .limited(let reason):
            switch reason {
            case .initializing: return "Трекінг: ініціалізація…"
            case .excessiveMotion: return "Рухайте телефон повільніше."
            case .insufficientFeatures: return "Мало деталей — додайте світла або відійдіть від стіни."
            case .relocalizing: return "Відновлення карти. Наведіть на попередню ділянку або скиньте AR."
            @unknown default: return "Трекінг обмежений."
            }
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        interrupted = true
        normalTrackingSince = nil
        for placement in placements.compactMap({ $0 }) { placement.node.isHidden = true }
        placeButton.isEnabled = false
        trackingLabel.text = "AR перервано системою."
        protectionMessage = "AR перервано. Поверніться до оглянутої стіни."
        safetyLabel.text = protectionMessage
        safetyLabel.isHidden = !interfaceHidden
    }

    func sessionShouldAttemptRelocalization(_ session: ARSession) -> Bool {
        placements.contains { $0 != nil }
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        interrupted = false
        normalTrackingSince = nil
        previousCamera = nil
        recoveryUntil = previousFrameTime + 0.7
        // ARKit may relocalize to the existing anchors; do not destroy them here.
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        running = false
        needsReset = true
        clearAllPlacements()
        setInterfaceHidden(false)
        trackingLabel.text = "Помилка AR: \(error.localizedDescription)"
        instructionLabel.text = "Перевірте дозвіл камери та натисніть «Скинути AR»."
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func canSaveProject() -> Bool {
        guard running, !interrupted, protectionMessage == nil,
              let frame = sceneView.session.currentFrame,
              case .normal = frame.camera.trackingState,
              let since = normalTrackingSince, frame.timestamp - since >= 0.6,
              frame.timestamp >= recoveryUntil else { return false }
        switch frame.worldMappingStatus {
        case .extending, .mapped: break
        default: return false
        }
        let ids = Set(frame.anchors.map { $0.identifier })
        let placed = placements.compactMap { $0 }
        return !placed.isEmpty && placed.allSatisfy { ids.contains($0.anchor.identifier) }
    }

    @objc private func saveProject() {
        guard !importing, !storageBusy, canSaveProject() else {
            showMessage("Ще рано зберігати", "Розмістіть зображення та повільно огляньте стіну й деталі навколо, доки карта стане готовою.")
            return
        }
        let revision = sessionRevision
        let selected = images.selectedIndex
        let snapshots = (0..<3).compactMap { index -> (Int, UIImage, String, Float, Float, UUID?)? in
            let item = images[index]
            guard let image = item.content else { return nil }
            return (index, image, item.name, item.width, item.opacity, placements[index]?.anchor.identifier)
        }
        storageBusy = true
        updateSelectedUI()
        sceneView.session.getCurrentWorldMap { [weak self] map, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard revision == self.sessionRevision, self.canSaveProject(), let map = map else {
                    let reason = error ?? NSError(domain: "WallTraceAR", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Стан трекінгу змінився. Огляньте стіну та спробуйте зберегти ще раз."])
                    self.finishStorage(error: reason)
                    return
                }
                let mapIDs = Set(map.anchors.map { $0.identifier })
                guard snapshots.compactMap({ $0.5 }).allSatisfy({ mapIDs.contains($0) }) else {
                    self.finishStorage(error: SavedProject.StorageError.invalid)
                    return
                }
                let destination = self.projectURL
                self.storageQueue.async {
                    let result = Result { () -> Void in
                        let mapData = try NSKeyedArchiver.archivedData(withRootObject: map, requiringSecureCoding: true)
                        let savedImages = try snapshots.map { item -> SavedProject.Image in
                            guard let png = item.1.pngData() else { throw SavedProject.StorageError.invalid }
                            return SavedProject.Image(slot: item.0, name: item.2, png: png,
                                width: item.3, opacity: item.4, anchorID: item.5)
                        }
                        let project = SavedProject(selectedIndex: selected, worldMap: mapData, images: savedImages)
                        try project.write(to: destination)
                    }
                    DispatchQueue.main.async {
                        switch result {
                        case .success:
                            self.hasSavedProject = true
                            self.finishStorage(error: nil)
                            self.showMessage("Сцену збережено", "Тепер можна вийти. Після повернення покажіть камері ту саму ділянку кімнати — позиції відновляться після впізнавання стіни.")
                        case .failure(let error): self.finishStorage(error: error)
                        }
                    }
                }
            }
        }
    }

    @objc private func restoreProject() {
        guard !importing, !storageBusy, hasSavedProject else { return }
        autoRestorePending = false
        storageBusy = true
        sceneView.session.pause()
        running = false
        clearAllPlacements()
        setInterfaceHidden(false)
        trackingLabel.text = "Завантаження збереженої сцени…"
        updateSelectedUI()
        let source = projectURL
        storageQueue.async { [weak self] in
            let result = Result { () -> (SavedProject, ARWorldMap, [Int: UIImage]) in
                let project = try SavedProject.read(from: source)
                guard let map = try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: project.worldMap) else {
                    throw SavedProject.StorageError.invalid
                }
                var decoded: [Int: UIImage] = [:]
                for item in project.images {
                    decoded[item.slot] = try PNGImporter.decode(item.png)
                    if let id = item.anchorID {
                        guard map.anchors.contains(where: { $0.identifier == id && $0.name == "WallTrace.image.\(item.slot)" }) else {
                            throw SavedProject.StorageError.invalid
                        }
                    }
                }
                return (project, map, decoded)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.storageBusy = false
                guard UIApplication.shared.applicationState == .active else {
                    self.autoRestorePending = true
                    self.needsReset = true
                    return
                }
                switch result {
                case .success(let prepared):
                    let project = prepared.0
                    let map = prepared.1
                    self.images = ImageSlots<UIImage>()
                    for item in project.images {
                        if let image = prepared.2[item.slot] {
                            self.images.select(item.slot)
                            self.images.replace(at: item.slot, content: image, name: item.name)
                            self.images.setAppearance(width: item.width, opacity: item.opacity)
                        }
                    }
                    self.images.select(project.selectedIndex)
                    self.needsReset = true
                    self.startSession(worldMap: map)
                    for item in project.images {
                        if let id = item.anchorID, let image = prepared.2[item.slot],
                           let anchor = map.anchors.first(where: { $0.identifier == id }) {
                            self.attachImage(at: item.slot, image: image, anchor: anchor,
                                timestamp: CACurrentMediaTime(), restoring: true)
                        }
                    }
                    self.updateSelectedUI()
                    self.instructionLabel.text = "Знайдіть ту саму стіну. Зображення з’являться після відновлення карти."
                case .failure(let error):
                    self.needsReset = true
                    self.startSession()
                    self.showMessage("Не вдалося відновити сцену", error.localizedDescription)
                }
            }
        }
    }

    private func finishStorage(error: Error?) {
        storageBusy = false
        updateSelectedUI()
        if let error = error { showMessage("Не вдалося зберегти сцену", error.localizedDescription) }
        if !running && UIApplication.shared.applicationState == .active { prepareCamera() }
    }

    private func showMessage(_ title: String, _ message: String) {
        guard UIApplication.shared.applicationState == .active, presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Гаразд", style: .default))
        present(alert, animated: true)
    }

    @objc private func importPNG() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.png], asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let targetIndex = images.selectedIndex
        importing = true
        updateSelectedUI()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try PNGImporter.load(url) }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.importing = false
                switch result {
                case .success(let image):
                    self.clearPlacement(at: targetIndex)
                    self.images.replace(at: targetIndex, content: image, name: url.lastPathComponent)
                case .failure(let error):
                    let alert = UIAlertController(title: "Не вдалося відкрити PNG",
                                                  message: error.localizedDescription, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "Гаразд", style: .default))
                    self.present(alert, animated: true)
                }
                self.updateSelectedUI()
            }
        }
    }
}
