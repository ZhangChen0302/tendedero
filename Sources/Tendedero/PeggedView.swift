import AppKit
import SwiftUI

/// One photo with its clothespin. All the charm lives here: it drops onto
/// the line, swings, sways with the breeze and falls when you pull it off.
struct PeggedView: View {
    let item: Pegged
    @ObservedObject var line: Line
    /// Panel width, so the clip can write a normalized free place (0…1).
    var width: CGFloat = 0

    @State private var swing: Double = 0
    @State private var arrived = false
    @State private var hovering = false
    /// Pointer over the clip (not the photo body).
    @State private var clipHovering = false

    private var copied: Bool { line.copiedID == item.id }
    private var dragging: Bool { line.draggingID == item.id }
    private var placing: Bool { line.placingID == item.id }

    private var cornerSymbol: String {
        switch line.corner(of: item.id) {
        case .trash: "xmark"
        case .hide: "eye.slash"
        case .unpin: "pin.slash"
        }
    }
    private var pressed: Bool { line.pressedID == item.id }

    var body: some View {
        VStack(spacing: -12) {
            Clothespin(pinned: item.kept, color: item.clipColor)
                // Wider than the metal so the clip is easy to grab and hover.
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onHover { inside in
                    clipHovering = inside
                    updateClipCursor()
                }
                .gesture(placeGesture)
                .contextMenu { clipColorMenu }
                .zIndex(1)
            // Held in your hand: a faded trace of it waits on its clip.
            card
                .saturation(item.held ? 0 : 1)
                .opacity(item.held ? 0.3 : 1)
                .animation(.easeOut(duration: 0.25), value: item.held)
        }
        .rotationEffect(.degrees(swing + item.tilt), anchor: .top)
        .offset(y: arrived ? 0 : -46)
        // The fall itself is drawn over the whole screen by CaptureFlight, so
        // the card here just steps aside at once.
        .opacity(item.falling || item.flying ? 0 : (arrived ? 1 : 0))
        .transaction { t in if item.falling || placing { t.animation = nil } }
        .animation(.easeOut(duration: 0.16), value: item.flying)
        .onAppear(perform: arrive)
        .onChange(of: item.flying) { was, now in if was && !now { land() } }
        .onChange(of: line.gust) { _, _ in breeze() }
        .onChange(of: copied) { _, isCopied in if isCopied { nudge(3) } }
        .onChange(of: placing) { _, _ in updateClipCursor() }
        .onDisappear {
            clipHovering = false
            if !placing { NSCursor.arrow.set() }
        }
    }

    /// Drag the clip to free-place the photo along the rope. The photo body
    /// keeps GrabArea's file drag; only the pin slides it.
    private var placeGesture: some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("line"))
            .onChanged { value in
                guard width > 0, !item.falling, !item.held else { return }
                if line.placingID != item.id {
                    line.beginPlace(item.id)
                    updateClipCursor()
                }
                let margin = max(Layout.cardWidth / 2 + 16, 80)
                let x = min(max(value.location.x, margin), max(margin, width - margin))
                line.setPlace(item.id, fraction: x / width)
            }
            .onEnded { _ in
                line.endPlace(item.id)
                updateClipCursor()
            }
    }

    /// Open hand over the clip, closed hand while sliding it. Photo body keeps
    /// the default arrow (GrabArea does not change the cursor).
    private func updateClipCursor() {
        if placing {
            NSCursor.closedHand.set()
        } else if clipHovering && !item.held && !item.falling {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    /// Right-click the clip only — photo-body menus stay in GrabArea.
    @ViewBuilder
    private var clipColorMenu: some View {
        Section(L("Clip color")) {
            Button {
                line.setClipColor(item.id, nil)
            } label: {
                if item.clipColor == nil {
                    Label(L("Default"), systemImage: "checkmark")
                } else {
                    Text(L("Default"))
                }
            }
            Divider()
            ForEach(ClipColor.allCases) { color in
                Button {
                    line.setClipColor(item.id, color)
                } label: {
                    Label {
                        Text(color.title)
                    } icon: {
                        if item.clipColor == color {
                            Image(systemName: "checkmark")
                        } else {
                            Circle().fill(color.swatch).frame(width: 10, height: 10)
                        }
                    }
                }
            }
        }
    }

    /// The photo fits inside the card area keeping its proportions, so the
    /// white border hugs it whether the screenshot is wide or tall.
    static func photoSize(for size: CGSize) -> CGSize {
        let maxW = Layout.cardWidth - 14, maxH = Layout.photoMaxHeight
        guard size.width > 0, size.height > 0 else { return CGSize(width: maxW, height: maxH) }
        let scale = min(maxW / size.width, maxH / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    /// The card around the photo: the photo plus the glass inset.
    static func cardSize(for size: CGSize) -> CGSize {
        let p = photoSize(for: size)
        return CGSize(width: p.width + Frame.inset * 2, height: p.height + Frame.inset * 2)
    }

    /// Distance from the top of the hanging view (the clip) to the card.
    static let cardOffsetBelowTop: CGFloat = 26 - 12

    private var photoSize: CGSize { Self.photoSize(for: item.thumb.size) }

    private var card: some View {
        Image(nsImage: item.thumb)
            .resizable()
            .interpolation(.high)
            .frame(width: photoSize.width, height: photoSize.height)
            // Concentric corners: the photo's radius is the frame's minus the
            // inset, the way macOS rounds nested shapes.
            .clipShape(RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Frame.radius - Frame.inset, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            )
            .overlay {
                // A recording says so with a play button over its first frame.
                if item.isRecording {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                        .glassFrame(circle: true)
                        .allowsHitTesting(false)
                }
            }
            .padding(Frame.inset)
            .glassFrame(cornerRadius: Frame.radius)
            .shadow(color: .black.opacity(hovering ? 0.26 : 0.18), radius: hovering ? 14 : 10, y: hovering ? 8 : 5)
            // Holding presses the photo in slowly, so a long press feels like
            // it is building up to something.
            .scaleEffect(pressed ? 0.95 : (hovering ? 1.035 : 1), anchor: .top)
            .animation(pressed ? .easeInOut(duration: 0.45) : .spring(response: 0.3, dampingFraction: 0.6), value: pressed)
            .opacity(dragging ? 0.45 : 1)
            .overlay(alignment: .topLeading) {
                // Drawn here, clicked through GrabView, which sits on top. A
                // cross sends a file in Tendedero's folder to the Trash; for a
                // file anywhere else, or one hung by hand, it only hides it
                // from the line. A pinned photo is unpinned instead.
                Image(systemName: cornerSymbol)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)
                    .glassFrame(circle: true)
                    .padding(3)
                    .opacity(hovering && !dragging && !item.held ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.6)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topTrailing) {
                // Quick Look — same action as force-click / the photo menu.
                // Hit-tested in GrabView's top-right corner.
                Image(systemName: "eye")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 20, height: 20)
                    .glassFrame(circle: true)
                    .padding(3)
                    .opacity(hovering && !dragging && !item.held ? 1 : 0)
                    .scaleEffect(hovering ? 1 : 0.6)
                    .allowsHitTesting(false)
            }
            .overlay(GrabArea(item: item, line: line))
            .overlay(alignment: .bottom) {
                if copied {
                    Label(L("Copied"), systemImage: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary)
                        // Wider than a narrow card rather than broken over several lines.
                        .fixedSize()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .glassFrame(capsule: true)
                        .offset(y: 16)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                }
            }
            .animation(.easeOut(duration: 0.18), value: hovering)
            .animation(.easeOut(duration: 0.2), value: copied)
            .onHover { hovering = $0 }
            .background(
                GeometryReader { g in
                    Color.clear.preference(key: HitRectsKey.self,
                                           value: item.falling ? [:] : [item.id: g.frame(in: .global)])
                }
            )
    }

    private func arrive() {
        // A capture that flew in is already in place; the flight did the arriving.
        if item.flying {
            arrived = true
            return
        }
        swing = 16
        withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { arrived = true }
        withAnimation(.interpolatingSpring(stiffness: 46, damping: 2.6)) { swing = 0 }
    }

    /// Landing after the flight: no jump, just a small sway from rest.
    private func land() {
        nudge(2.2)
    }

    private func breeze() {
        let delay = Double.random(in: 0...0.35)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            nudge(Double.random(in: 1.6...3.4))
        }
    }

    private func nudge(_ degrees: Double) {
        withAnimation(.easeOut(duration: 0.3)) { swing = degrees }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.interpolatingSpring(stiffness: 38, damping: 2.4)) { swing = 0 }
        }
    }
}

enum Frame {
    static let radius: CGFloat = 16
    static let inset: CGFloat = 4
}

extension View {
    /// A crisp glass: the system's blurred material with a thin specular
    /// edge, lit from above. No refraction, so the background stays sharp
    /// around the frame instead of bending like gel.
    func glassFrame(cornerRadius: CGFloat = 0, circle: Bool = false, capsule: Bool = false) -> some View {
        let shape: AnyShape = circle ? AnyShape(Circle())
            : capsule ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        return background(.ultraThinMaterial, in: shape)
            .overlay(
                shape.stroke(
                    LinearGradient(colors: [Color.white.opacity(0.55), Color.white.opacity(0.12)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 0.75)
            )
            .overlay(shape.stroke(Color.black.opacity(0.10), lineWidth: 0.5).padding(-0.5))
    }
}

/// Colors you can paint a clothespin, stored by `rawValue` in UserDefaults.
enum ClipColor: String, CaseIterable, Identifiable, Equatable {
    case red, orange, yellow, green, blue, purple, pink, grey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red: L("Red")
        case .orange: L("Orange")
        case .yellow: L("Yellow")
        case .green: L("Green")
        case .blue: L("Blue")
        case .purple: L("Purple")
        case .pink: L("Pink")
        case .grey: L("Space Grey")
        }
    }

    /// Solid chip for the context menu.
    var swatch: Color {
        switch self {
        case .red: Color(red: 0.86, green: 0.28, blue: 0.28)
        case .orange: Color(red: 0.92, green: 0.52, blue: 0.18)
        case .yellow: Color(red: 0.92, green: 0.78, blue: 0.22)
        case .green: Color(red: 0.32, green: 0.72, blue: 0.38)
        case .blue: Color(red: 0.28, green: 0.52, blue: 0.92)
        case .purple: Color(red: 0.58, green: 0.36, blue: 0.86)
        case .pink: Color(red: 0.90, green: 0.40, blue: 0.62)
        case .grey: Color(white: 0.38)
        }
    }

    /// Brushed fill for the metal clip body.
    var gradient: LinearGradient {
        let c = swatch
        return LinearGradient(
            stops: [
                .init(color: c.opacity(0.75), location: 0),
                .init(color: c, location: 0.35),
                .init(color: c.opacity(0.88), location: 0.65),
                .init(color: c.opacity(0.65), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing)
    }
}

/// A minimal aluminium clip: a brushed metal pill with a slot where it
/// grips the line, and a soft shadow so it reads on any background.
struct Clothespin: View {
    /// Silver for what comes and goes, space grey for what you pinned, the
    /// way Macs come in both — unless a custom `color` overrides both.
    var pinned = false
    var color: ClipColor? = nil

    private let metal = LinearGradient(
        stops: [
            .init(color: Color(white: 0.70), location: 0),
            .init(color: Color(white: 0.93), location: 0.35),
            .init(color: Color(white: 0.82), location: 0.65),
            .init(color: Color(white: 0.62), location: 1),
        ],
        startPoint: .leading, endPoint: .trailing)

    private let spaceGrey = LinearGradient(
        stops: [
            .init(color: Color(white: 0.30), location: 0),
            .init(color: Color(white: 0.47), location: 0.35),
            .init(color: Color(white: 0.38), location: 0.65),
            .init(color: Color(white: 0.24), location: 1),
        ],
        startPoint: .leading, endPoint: .trailing)

    private var fill: LinearGradient {
        if let color { return color.gradient }
        return pinned ? spaceGrey : metal
    }

    private var darkSlot: Bool { color != nil || pinned }

    var body: some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(fill)
            .frame(width: 9, height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .stroke(LinearGradient(colors: [Color.white.opacity(darkSlot ? 0.45 : 0.9), Color.black.opacity(0.18)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 0.6)
            )
            .overlay(alignment: .top) {
                // The slot the line passes through.
                Capsule()
                    .fill(Color.black.opacity(darkSlot ? 0.55 : 0.32))
                    .frame(width: 5, height: 1.4)
                    .padding(.top, 8.5)
            }
            .shadow(color: .black.opacity(0.30), radius: 2, y: 1.5)
    }
}
