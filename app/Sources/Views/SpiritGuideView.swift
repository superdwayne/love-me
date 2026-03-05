import SwiftUI

// MARK: - Spirit Guide State

enum SpiritGuideState: Equatable {
    case idle
    case thinking
    case success
    case tinkering(toolCount: Int)
}

enum SpiritGuideSize {
    case small   // 24pt — chat header
    case medium  // 80pt — empty state
    case large   // 120pt — welcome
    case xlarge  // 180pt — welcome hero orb
    case inline  // 20pt — conversation block header

    var dimension: CGFloat {
        switch self {
        case .small: return 24
        case .medium: return 80
        case .large: return 120
        case .xlarge: return 180
        case .inline: return SolaceTheme.inlineGuideSize
        }
    }

    /// Drag sensitivity — no interaction for small/inline sizes
    var dragSensitivity: Double {
        switch self {
        case .small, .inline: return 0
        case .medium: return 0.4
        case .large: return 0.3
        case .xlarge: return 0.25
        }
    }

    var isDraggable: Bool {
        dragSensitivity > 0
    }
}

// MARK: - Particle

private struct Particle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var vx: CGFloat
    var vy: CGFloat
    var life: Double      // 0..1, starts at 1, decays to 0
    var size: CGFloat
    var color: Color
    var shape: ParticleShape

    enum ParticleShape {
        case circle
        case diamond
    }
}

// MARK: - Spirit Guide View

struct SpiritGuideView: View {
    let size: SpiritGuideSize
    var state: SpiritGuideState = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // 3D drag rotation state
    @State private var dragRotationX: Double = 0
    @State private var dragRotationY: Double = 0
    @State private var isDragging: Bool = false

    private var frameRate: Double {
        switch state {
        case .idle: return 30.0
        case .thinking, .success: return 30.0
        case .tinkering: return 60.0
        }
    }

    var body: some View {
        if reduceMotion {
            staticCrystal
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / frameRate)) { timeline in
                animatedCrystal(date: timeline.date)
            }
            .gesture(size.isDraggable ? dragGesture : nil)
        }
    }

    // MARK: - Drag Gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                isDragging = true
                let sensitivity = size.dragSensitivity
                dragRotationY = max(-30, min(30, value.translation.width * sensitivity))
                dragRotationX = max(-30, min(30, -value.translation.height * sensitivity))
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    dragRotationX = 0
                    dragRotationY = 0
                    isDragging = false
                }
            }
    }

    // MARK: - Static (Reduce Motion)

    private var staticCrystal: some View {
        ZStack {
            crystalLayer(rotation: 0, opacity: 0.6, scale: 1.0)
            crystalLayer(rotation: 30, opacity: 0.4, scale: 0.85)
            crystalLayer(rotation: 60, opacity: 0.3, scale: 0.7)
        }
        .frame(width: size.dimension, height: size.dimension)
    }

    // MARK: - Animated

    private func animatedCrystal(date: Date) -> some View {
        let t = date.timeIntervalSinceReferenceDate

        // Animation speeds based on state
        let rotationSpeed: Double
        let floatAmplitude: CGFloat
        let breatheSpeed: Double
        let colorShift: Bool
        let warmGlow: Bool
        let scaleBoost: CGFloat

        switch state {
        case .idle:
            rotationSpeed = 0.08
            floatAmplitude = size.dimension * 0.025
            breatheSpeed = 0.15
            colorShift = false
            warmGlow = false
            scaleBoost = 1.0
        case .thinking:
            rotationSpeed = 0.3
            floatAmplitude = size.dimension * 0.008
            breatheSpeed = 0.5
            colorShift = true
            warmGlow = false
            scaleBoost = 1.0
        case .success:
            rotationSpeed = 0.12
            floatAmplitude = size.dimension * 0.015
            breatheSpeed = 0.25
            colorShift = false
            warmGlow = true
            scaleBoost = 1.05
        case .tinkering:
            rotationSpeed = 0.6
            floatAmplitude = size.dimension * 0.012
            breatheSpeed = 0.6
            colorShift = true
            warmGlow = false
            scaleBoost = 1.08
        }

        let rotation1 = t * rotationSpeed * 360.0
        let rotation2 = t * rotationSpeed * 360.0 * 0.7
        let rotation3 = t * rotationSpeed * 360.0 * 0.5
        let floatY = sin(t * 1.2) * floatAmplitude
        let breathe = 0.85 + sin(t * breatheSpeed * .pi * 2) * 0.15

        let gradient1: [Color] = colorShift
            ? [.coral, .shimmerAccent, .coral]
            : warmGlow
                ? [.skyBlue.opacity(0.5), .success, .skyBlue]
                : [.white.opacity(0.7), .coral.opacity(0.3), .skyBlue.opacity(0.3)]

        // Ambient 3D tilt (gentle sway when not being dragged)
        let ambientTiltX = isDragging ? 0.0 : sin(t * 0.3) * 5.0
        let ambientTiltY = isDragging ? 0.0 : cos(t * 0.4) * 4.0

        // Combined rotation: drag + ambient
        let totalRotX = dragRotationX + ambientTiltX
        let totalRotY = dragRotationY + ambientTiltY

        // Dynamic highlight position based on rotation
        let highlightOffsetX = totalRotY / 30.0 * 0.3
        let highlightOffsetY = totalRotX / 30.0 * 0.3

        return ZStack {
            // Water reflection — flipped crystal below (medium/large/xlarge only)
            if size == .medium || size == .large || size == .xlarge {
                crystalPolygon(sides: 6, rotation: rotation1, gradient: gradient1)
                    .opacity(0.15 * breathe)
                    .scaleEffect(x: 1.0, y: -0.6)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blur(radius: 2)
                    .offset(y: size.dimension * 0.55)
                    .allowsHitTesting(false)
            }

            // Caustic ground shadow — refracting light on the water surface
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.shimmerAccent.opacity(0.08 * breathe),
                            Color.coral.opacity(0.04 * breathe),
                            .clear
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: size.dimension * 0.4
                    )
                )
                .frame(width: size.dimension * 0.7, height: size.dimension * 0.15)
                .offset(
                    x: -totalRotY / 30.0 * size.dimension * 0.1,
                    y: size.dimension * 0.45
                )
                .scaleEffect(x: 1.0 + abs(totalRotY) / 60.0, y: 1.0)
                .blur(radius: 4)

            // Outer glow (subtle pearlescent)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.coral.opacity(0.06 * breathe), Color.white.opacity(0.03 * breathe), .clear],
                        center: .center,
                        startRadius: size.dimension * 0.2,
                        endRadius: size.dimension * 0.6
                    )
                )
                .frame(width: size.dimension * 1.4, height: size.dimension * 1.4)

            // Layer 3 (back) — moves more (1.3x) to appear further away
            crystalPolygon(sides: 6, rotation: rotation3, gradient: gradient1)
                .opacity(0.25 * breathe)
                .scaleEffect(0.75 * scaleBoost)
                .rotation3DEffect(
                    .degrees(totalRotX * 1.3),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.6
                )
                .rotation3DEffect(
                    .degrees(totalRotY * 1.3),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.6
                )

            // Layer 2 (mid) — standard parallax (1.0x)
            crystalPolygon(sides: 6, rotation: rotation2, gradient: gradient1)
                .opacity(0.4 * breathe)
                .scaleEffect(0.88 * scaleBoost)
                .rotation3DEffect(
                    .degrees(totalRotX),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.6
                )
                .rotation3DEffect(
                    .degrees(totalRotY),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.6
                )

            // Layer 1 (front) — moves less (0.7x) to appear closer
            crystalPolygon(sides: 6, rotation: rotation1, gradient: gradient1)
                .opacity(0.6 * breathe)
                .scaleEffect(1.0 * scaleBoost)
                .rotation3DEffect(
                    .degrees(totalRotX * 0.7),
                    axis: (x: 1, y: 0, z: 0),
                    perspective: 0.6
                )
                .rotation3DEffect(
                    .degrees(totalRotY * 0.7),
                    axis: (x: 0, y: 1, z: 0),
                    perspective: 0.6
                )

            // Dynamic highlight — white radial that shifts with rotation
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.12 * breathe),
                            Color.white.opacity(0.03),
                            .clear
                        ],
                        center: UnitPoint(
                            x: 0.5 + highlightOffsetX,
                            y: 0.4 + highlightOffsetY
                        ),
                        startRadius: 0,
                        endRadius: size.dimension * 0.4
                    )
                )
                .frame(width: size.dimension * 0.8, height: size.dimension * 0.8)
                .allowsHitTesting(false)
        }
        .frame(width: size.dimension, height: size.dimension)
        .offset(y: floatY)
    }

    // MARK: - Crystal Layers

    private func crystalLayer(rotation: Double, opacity: Double, scale: CGFloat) -> some View {
        crystalPolygon(sides: 6, rotation: rotation, gradient: [.white.opacity(0.7), .coral.opacity(0.3), .skyBlue.opacity(0.3)])
            .opacity(opacity)
            .scaleEffect(scale)
    }

    private func crystalPolygon(sides: Int, rotation: Double, gradient: [Color]) -> some View {
        PolygonShape(sides: sides)
            .fill(
                LinearGradient(
                    colors: gradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .rotationEffect(.degrees(rotation))
            .frame(width: size.dimension * 0.65, height: size.dimension * 0.65)
    }
}

// MARK: - Spirit Guide with Particles

/// Wraps SpiritGuideView and adds a Canvas-based particle system for tinkering state.
struct SpiritGuideWithParticles: View {
    let size: SpiritGuideSize
    var state: SpiritGuideState = .idle

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var particles: [Particle] = []
    @State private var lastSpawnTime: Double = 0
    @State private var previousToolCount: Int = 0

    private var isTinkering: Bool {
        if case .tinkering = state { return true }
        return false
    }

    private var toolCount: Int {
        if case .tinkering(let count) = state { return count }
        return 0
    }

    var body: some View {
        ZStack {
            if !reduceMotion && !particles.isEmpty {
                particleCanvas
            }

            SpiritGuideView(size: size, state: state)
        }
        .frame(width: size.dimension * 2, height: size.dimension * 2)
        .onChange(of: state) { oldState, newState in
            // Completion burst: tools just finished
            if case .tinkering(let oldCount) = oldState, !isTinkering, !reduceMotion {
                spawnBurst(count: min(6, oldCount * 2 + 4))
            }
            // Track tool count changes for burst on individual tool completion
            if case .tinkering(let newCount) = newState {
                if newCount < previousToolCount && !reduceMotion {
                    spawnBurst(count: 3)
                }
                previousToolCount = newCount
            }
        }
    }

    // MARK: - Particle Canvas

    private var particleCanvas: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, canvasSize in
                let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

                for particle in particles {
                    guard particle.life > 0 else { continue }

                    let px = center.x + particle.x
                    let py = center.y + particle.y
                    let alpha = particle.life
                    let pSize = particle.size * CGFloat(0.5 + particle.life * 0.5)

                    context.drawLayer { ctx in
                        ctx.opacity = alpha
                        let rect = CGRect(x: px - pSize / 2, y: py - pSize / 2, width: pSize, height: pSize)

                        switch particle.shape {
                        case .circle:
                            ctx.fill(Circle().path(in: rect), with: .color(particle.color))
                        case .diamond:
                            let diamondPath = Path { p in
                                p.move(to: CGPoint(x: rect.midX, y: rect.minY))
                                p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
                                p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
                                p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
                                p.closeSubpath()
                            }
                            ctx.fill(diamondPath, with: .color(particle.color))
                        }
                    }
                }
            }
            .drawingGroup()
            .allowsHitTesting(false)
            .onChange(of: t) { _, newT in
                updateParticles(t: newT)
            }
        }
    }

    // MARK: - Particle Logic

    private func updateParticles(t: Double) {
        let dt: Double = 1.0 / 60.0
        let lifetime = SolaceTheme.particleLifetime

        // Update existing particles
        particles = particles.compactMap { p in
            var p = p
            p.life -= dt / lifetime
            guard p.life > 0 else { return nil }
            p.x += p.vx * CGFloat(dt)
            p.y += p.vy * CGFloat(dt)
            // Slight gravity pull down
            p.vy += 5 * CGFloat(dt)
            return p
        }

        // Spawn new particles when tinkering
        if isTinkering {
            let spawnInterval = max(0.05, 0.3 / Double(max(1, toolCount)))
            if t - lastSpawnTime > spawnInterval && particles.count < SolaceTheme.particleMaxCount {
                spawnParticle()
                lastSpawnTime = t
            }
        }
    }

    private func spawnParticle() {
        let dim = size.dimension
        let angle = Double.random(in: 0...(2 * .pi))
        let radius = dim * 0.35
        let startX = cos(angle) * radius
        let startY = sin(angle) * radius
        let speed: CGFloat = CGFloat.random(in: 15...35)

        let colors: [Color] = [.coral, .skyBlue, .glow]
        let particle = Particle(
            x: startX,
            y: startY,
            vx: cos(angle) * speed,
            vy: sin(angle) * speed,
            life: 1.0,
            size: CGFloat.random(in: 2...5),
            color: colors.randomElement()!,
            shape: Bool.random() ? .circle : .diamond
        )
        particles.append(particle)
    }

    private func spawnBurst(count: Int) {
        let dim = size.dimension
        for _ in 0..<count {
            let angle = Double.random(in: 0...(2 * .pi))
            let radius = dim * 0.3
            let speed: CGFloat = CGFloat.random(in: 25...55)
            let colors: [Color] = [.coral, .skyBlue, .glow]

            let particle = Particle(
                x: cos(angle) * radius * 0.5,
                y: sin(angle) * radius * 0.5,
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                life: 1.0,
                size: CGFloat.random(in: 3...6),
                color: colors.randomElement()!,
                shape: Bool.random() ? .circle : .diamond
            )
            particles.append(particle)
        }
        // Cap
        if particles.count > SolaceTheme.particleMaxCount {
            particles = Array(particles.suffix(SolaceTheme.particleMaxCount))
        }
    }
}

// MARK: - Polygon Shape

private struct PolygonShape: Shape {
    let sides: Int

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()

        for i in 0..<sides {
            let angle = (Double(i) / Double(sides)) * 2 * .pi - .pi / 2
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
