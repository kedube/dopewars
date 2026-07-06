import AppKit

/// A stylized subway-style map of the game's locations, laid out in rough
/// NYC geography. Highlights the current (or destination) station, can show
/// the origin during travel, and optionally accepts clicks on stations.
final class SubwayMapView: NSView {
    var locationNames: [String] = [] { didSet { needsDisplay = true } }
    /// The highlighted "you are here" (or destination) station.
    var current: Int = -1 { didSet { needsDisplay = true; needsLayout = true } }
    /// Secondary highlight for where you travelled from (-1 = none).
    var origin: Int = -1 { didSet { needsDisplay = true } }
    /// When set, stations are clickable.
    var onSelect: ((Int) -> Void)?
    /// Tighter insets and smaller type for the always-on sidebar mini-map.
    var compact = false

    private var pulse: CAShapeLayer?

    // MARK: Geometry

    /// Normalized positions for the default 8 locations (engine order:
    /// Bronx, Ghetto, Central Park, Manhattan, Coney Island, Brooklyn,
    /// Queens, Staten Island). Other counts fall back to a ring.
    private static let nycPositions: [CGPoint] = [
        CGPoint(x: 0.56, y: 0.88),  // Bronx        (north)
        CGPoint(x: 0.48, y: 0.72),  // Ghetto       (Harlem-ish)
        CGPoint(x: 0.40, y: 0.58),  // Central Park
        CGPoint(x: 0.34, y: 0.42),  // Manhattan    (downtown)
        CGPoint(x: 0.56, y: 0.08),  // Coney Island (far south)
        CGPoint(x: 0.58, y: 0.28),  // Brooklyn
        CGPoint(x: 0.76, y: 0.50),  // Queens       (east)
        CGPoint(x: 0.12, y: 0.14),  // Staten Island (southwest)
    ]

    /// Label anchor per station: true = draw label to the right of the dot.
    private static let labelRight: [Bool] = [
        true, true, false, false, true, true, true, true,
    ]

    /// Subway "lines": chains of station indices with a route color.
    private static let nycLines: [([Int], NSColor)] = [
        ([7, 3, 2, 1, 0], .systemGreen),    // ferry + west side line
        ([4, 5, 3], .systemOrange),         // south Brooklyn line
        ([5, 6, 0], .systemBlue),           // crosstown loop
    ]

    private func normalizedPosition(_ i: Int) -> CGPoint {
        if locationNames.count <= Self.nycPositions.count
            && i < Self.nycPositions.count {
            return Self.nycPositions[i]
        }
        // Generic ring for custom configs with more locations.
        let angle = 2 * .pi * CGFloat(i) / CGFloat(max(locationNames.count, 1))
        return CGPoint(x: 0.5 + 0.4 * cos(angle), y: 0.5 + 0.4 * sin(angle))
    }

    private var mapRect: NSRect {
        bounds.insetBy(dx: compact ? 18 : 26, dy: compact ? 12 : 20)
    }

    func stationPoint(_ i: Int) -> NSPoint {
        let n = normalizedPosition(i)
        let r = mapRect
        return NSPoint(x: r.minX + n.x * r.width, y: r.minY + n.y * r.height)
    }

    func station(at point: NSPoint) -> Int? {
        for i in 0..<locationNames.count {
            let p = stationPoint(i)
            if hypot(p.x - point.x, p.y - point.y) <= 16 { return i }
        }
        return nil
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Resolve dynamic colors against this view's appearance even when
        // drawn offscreen or under a forced-dark overlay.
        if #available(macOS 11.0, *) {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                self.drawMap()
            }
        } else {
            drawMap()
        }
    }

    private func drawMap() {
        guard !locationNames.isEmpty else { return }
        let count = locationNames.count

        // Route lines beneath everything.
        if count <= Self.nycPositions.count {
            for (chain, color) in Self.nycLines {
                let usable = chain.filter { $0 < count }
                guard usable.count >= 2 else { continue }
                let path = NSBezierPath()
                path.lineWidth = 5
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                path.move(to: stationPoint(usable[0]))
                for i in usable.dropFirst() { path.line(to: stationPoint(i)) }
                color.withAlphaComponent(0.75).setStroke()
                path.stroke()
            }
        } else {
            let path = NSBezierPath()
            path.lineWidth = 5
            path.lineCapStyle = .round
            path.move(to: stationPoint(0))
            for i in 1..<count { path.line(to: stationPoint(i)) }
            path.line(to: stationPoint(0))
            NSColor.systemGreen.withAlphaComponent(0.75).setStroke()
            path.stroke()
        }

        // Stations + labels.
        for i in 0..<count {
            let p = stationPoint(i)
            let isCurrent = (i == current)
            let isOrigin = (i == origin)
            let radius: CGFloat = isCurrent ? (compact ? 7 : 9)
                                            : (compact ? 4.5 : 6)

            if isCurrent {
                // Halo behind the current station.
                let halo = NSBezierPath(ovalIn: NSRect(x: p.x - 14, y: p.y - 14,
                                                       width: 28, height: 28))
                NSColor.controlAccentColor.withAlphaComponent(0.25).setFill()
                halo.fill()
            }

            let dotRect = NSRect(x: p.x - radius, y: p.y - radius,
                                 width: radius * 2, height: radius * 2)
            let dot = NSBezierPath(ovalIn: dotRect)
            (isCurrent ? NSColor.controlAccentColor
                       : NSColor.windowBackgroundColor).setFill()
            dot.fill()
            dot.lineWidth = isOrigin ? 3 : 2
            (isOrigin ? NSColor.controlAccentColor.withAlphaComponent(0.7)
                      : NSColor.labelColor).setStroke()
            dot.stroke()

            // Label
            let name = locationNames[i]
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: compact ? 9 : 10,
                                         weight: isCurrent ? .bold : .medium),
                .foregroundColor: isCurrent ? NSColor.controlAccentColor
                                            : NSColor.labelColor,
            ]
            let size = name.size(withAttributes: attrs)
            let right = i < Self.labelRight.count ? Self.labelRight[i] : true
            let lx = right ? p.x + radius + 5 : p.x - radius - 5 - size.width
            var ly = p.y - size.height / 2
            // Nudge Coney Island's label below its dot so it clears Brooklyn's.
            if i == 4 && count <= 8 { ly = p.y - radius - 4 - size.height }
            name.draw(at: NSPoint(x: lx, y: ly), withAttributes: attrs)
        }
    }

    // MARK: Interaction

    override func mouseDown(with event: NSEvent) {
        guard let onSelect = onSelect else { return }
        let p = convert(event.locationInWindow, from: nil)
        if let i = station(at: p) { onSelect(i) }
    }

    override func resetCursorRects() {
        guard onSelect != nil else { return }
        for i in 0..<locationNames.count {
            let p = stationPoint(i)
            addCursorRect(NSRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24),
                          cursor: .pointingHand)
        }
    }

    // MARK: Route finding + train animation

    /// Station adjacency along the drawn subway lines.
    private func adjacency() -> [Int: Set<Int>] {
        var adj: [Int: Set<Int>] = [:]
        for (chain, _) in Self.nycLines {
            let usable = chain.filter { $0 < locationNames.count }
            for (a, b) in zip(usable, usable.dropFirst()) {
                adj[a, default: []].insert(b)
                adj[b, default: []].insert(a)
            }
        }
        return adj
    }

    /// Shortest station-to-station route along the lines (BFS); nil when
    /// the endpoints are invalid or the layout is the generic ring.
    func route(from a: Int, to b: Int) -> [Int]? {
        guard a >= 0, b >= 0, a != b,
              a < locationNames.count, b < locationNames.count,
              locationNames.count <= Self.nycPositions.count else { return nil }
        let adj = adjacency()
        var parent: [Int: Int] = [a: a]
        var queue = [a]
        var head = 0
        while head < queue.count {
            let cur = queue[head]
            head += 1
            if cur == b { break }
            for n in adj[cur] ?? [] where parent[n] == nil {
                parent[n] = cur
                queue.append(n)
            }
        }
        guard parent[b] != nil else { return nil }
        var path = [b]
        var cur = b
        while cur != a {
            cur = parent[cur]!
            path.append(cur)
        }
        return path.reversed()
    }

    /// Slide a little "train" dot along the route, then call `completion`
    /// (immediately if there is no route to ride).
    func animateTrain(from a: Int, to b: Int, completion: (() -> Void)? = nil) {
        guard let stations = route(from: a, to: b), stations.count >= 2 else {
            completion?()
            return
        }
        wantsLayer = true
        let path = CGMutablePath()
        path.move(to: stationPoint(stations[0]))
        for s in stations.dropFirst() { path.addLine(to: stationPoint(s)) }

        let train = CALayer()
        train.bounds = CGRect(x: 0, y: 0, width: 11, height: 11)
        train.cornerRadius = 5.5
        train.backgroundColor = NSColor.white.cgColor
        train.borderColor = NSColor.controlAccentColor.cgColor
        train.borderWidth = 2.5
        train.position = stationPoint(stations[0])
        layer?.addSublayer(train)

        let ride = CAKeyframeAnimation(keyPath: "position")
        ride.path = path
        ride.duration = min(1.1, 0.3 * Double(stations.count - 1) + 0.3)
        ride.calculationMode = .paced
        ride.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock {
            train.removeFromSuperlayer()
            completion?()
        }
        train.add(ride, forKey: "ride")
        train.position = stationPoint(stations.last!)
        CATransaction.commit()
    }

    // MARK: Pulse animation (destination emphasis during travel)

    func startPulse() {
        guard current >= 0 else { return }
        wantsLayer = true
        pulse?.removeFromSuperlayer()
        let p = stationPoint(current)
        let ring = CAShapeLayer()
        let r: CGFloat = 10
        ring.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: r * 2, height: r * 2),
                           transform: nil)
        ring.position = p
        ring.fillColor = nil
        ring.strokeColor = NSColor.controlAccentColor.cgColor
        ring.lineWidth = 2.5
        layer?.addSublayer(ring)
        pulse = ring

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.6
        scale.toValue = 2.2
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1.0
        fade.toValue = 0.0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.7
        group.repeatCount = 3
        ring.add(group, forKey: "pulse")
        ring.opacity = 0
    }
}
