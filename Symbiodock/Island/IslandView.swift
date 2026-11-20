import SwiftUI
import SymbiodockCore

struct IslandView: View {
    let state: IslandState
    let geometry: IslandGeometry
    let session: DragSession
    let onCommand: (PlaybackCommand, NowPlayingOrigin) -> Void
    let onVolume: (VolumeRequest) -> Void
    let onOpenSession: (AgentSession) -> Void
    let previews: FilePreviews?
    let onFile: (FileRequest) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                // Below the island, so that they come out from behind it.
                bubble
                filesBubble
                // Behind the island too: only what lies outside it shows.
                workingAurora
                switch state.phase {
                case .collapsed, .expanded:
                    resting
                case .stretching, .detached, .settling:
                    // Body, root and goo all move per frame; the session draws them together.
                    DragLayer(session: session)
                }
            }
        }
        .ignoresSafeArea()
        // Sliders report where a press must not drag the island.
        .environment(geometry)
        // A finish on the collapsed island plays its seal, then lets go: the session settles
        // and the island closes. Opening the island or a question in the meantime cancels
        // the wait, and the seal plays again from the start the next time.
        .task(id: state.sealingID) {
            guard let id = state.sealingID else { return }
            let wait = reduceMotion ? AgentSealTiming.stillDuration : AgentSealTiming.duration
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            state.settleFinished(id)
        }
        // A new track waits a moment for its cover, then its light plays; the state decides
        // when, this only keeps the time. A further track cancels the wait and starts another.
        .task(id: state.awaitedTrackGlow?.serial) {
            guard let serial = state.awaitedTrackGlow?.serial else { return }
            try? await Task.sleep(for: .seconds(TrackGlowMotion.minimumWait))
            guard !Task.isCancelled else { return }
            state.trackGlowSettled(serial)
            try? await Task.sleep(for: .seconds(TrackGlowMotion.maximumWait - TrackGlowMotion.minimumWait))
            guard !Task.isCancelled else { return }
            state.trackGlowWaitElapsed(serial)
        }
        // When the light is over its view goes, so nothing is left at rest.
        .task(id: state.trackGlow?.serial) {
            guard let serial = state.trackGlow?.serial else { return }
            try? await Task.sleep(for: .seconds(TrackGlowMotion.duration + 0.1))
            guard !Task.isCancelled else { return }
            state.trackGlowEnded(serial)
        }
    }

    /// The second face, in a bubble left of the island. It comes out from behind the
    /// island's left edge and goes back the same way.
    private var bubble: some View {
        let frame = IslandLayout.bubbleFrame(notch: geometry.notch, screenSize: geometry.screenSize)
        let slide = AnyTransition.offset(x: frame.width + IslandLayout.bubbleGap)
            .combined(with: .scale(scale: 0.6)).combined(with: .opacity)
        return ZStack {
            if let content = bubbleContent {
                SideBubble(content: content, diameter: frame.width)
                    .overlay {
                        if let glow = state.trackGlow, glow.surface == .bubble {
                            TrackGlowLine(outline: .bubble, tint: tint(of: glow))
                                .clipShape(Circle())
                                .id(glow.serial)
                        }
                    }
                    .transition(reduceMotion ? .opacity : slide)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Self.spring, value: state.bubbleTab)
    }

    private var bubbleContent: SideBubble.Content? {
        switch state.bubbleTab {
        case .media:
            state.nowPlaying.map {
                .media(front: $0, behind: state.mediaSlots.dropFirst().first?.info)
            }
        case .agents:
            state.board.lead.map { .agent($0) }
        case .files, nil:
            // Files never has a face, so it never moves out to the bubble.
            nil
        }
    }

    /// The light of a working agent, in a band just outside the collapsed island's free long
    /// edge. The light shows only while the island is collapsed, so the band is always the
    /// collapsed island's: it fades out in place as the island opens and fades in in place as
    /// it closes. It is not an overlay of the island, which clips what it holds.
    private var workingAurora: some View {
        let frame = IslandLayout.frame(
            anchor: state.anchor, phase: .collapsed, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame, screenSize: geometry.screenSize,
            showsWings: state.showsWings)
        let edge = WorkingAurora.edge(
            dockedEdges: IslandLayout.dockedEdges(anchor: state.anchor),
            isVertical: IslandLayout.isSideDocked(state.anchor))
        let band = WorkingAurora.band(island: frame, edge: edge)
        return ZStack {
            if state.showsWorkingAurora, let tool = state.board.lead?.session.tool {
                // The edge is its identity: if the anchor moves it to another edge, the old
                // light fades out and a new one fades in, not one stretched between bands.
                WorkingAuroraLight(tool: tool, edge: edge)
                    .id(edge)
                    .transition(.opacity)
            }
        }
        .frame(width: band.width, height: band.height)
        .offset(x: band.minX, y: band.minY)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Self.spring, value: state.showsWings)
        .animation(Self.spring, value: state.anchor)
        // Last, so outermost: of animations whose values change in one update the innermost
        // wins, and a hover end changes `showsWorkingAurora` with the island's own state.
        // The fade must win, or the light would slide with a spring while it fades in.
        .animation(.easeInOut(duration: WorkingAurora.fade), value: state.showsWorkingAurora)
    }

    /// The files held, in a bubble right of the island: the left bubble's mirror. It comes out
    /// from behind the island's right edge and goes back the same way, and it follows that
    /// edge with the island's spring when the wings come and go.
    private var filesBubble: some View {
        let frame = IslandLayout.filesBubbleFrame(
            notch: geometry.notch, screenSize: geometry.screenSize, showsWings: state.showsWings)
        let slide = AnyTransition.offset(x: -(frame.width + IslandLayout.bubbleGap))
            .combined(with: .scale(scale: 0.6)).combined(with: .opacity)
        return ZStack {
            if state.filesBubbleShown {
                FilesBubble(
                    count: state.shelf.count, kinds: state.shelf.bubbleKinds, diameter: frame.width)
                    .transition(reduceMotion ? .opacity : slide)
            }
        }
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(Self.spring, value: state.filesBubbleShown)
        .animation(Self.spring, value: state.showsWings)
    }

    private var resting: some View {
        let atNotch = state.anchor == .notch
        let frame = IslandLayout.frame(
            anchor: state.anchor, phase: state.phase, notch: geometry.notch,
            visibleFrame: geometry.visibleFrame, screenSize: geometry.screenSize,
            showsWings: state.showsWings)
        // Wherever it rests, the island sits against its screen edge the way the notch does:
        // square on that edge, rounded on the free side.
        let radii = IslandLayout.cornerRadii(
            anchor: state.anchor,
            radius: state.phase == .expanded
                ? IslandLayout.expandedCornerRadius : IslandLayout.collapsedCornerRadius)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: radii.topLeading, bottomLeadingRadius: radii.bottomLeading,
            bottomTrailingRadius: radii.bottomTrailing, topTrailingRadius: radii.topTrailing,
            style: .continuous)

        return shape
            .fill(.black)
            .overlay { content(atNotch: atNotch, frame: frame) }
            .overlay {
                if state.phase == .collapsed {
                    RimLight(
                        attention: state.board.attention, radii: radii,
                        dockedEdges: IslandLayout.dockedEdges(anchor: state.anchor),
                        isVertical: IslandLayout.isSideDocked(state.anchor))
                }
            }
            .overlay {
                if state.showsCompactingRim {
                    CompactingRim(
                        radii: radii, dockedEdges: IslandLayout.dockedEdges(anchor: state.anchor))
                }
            }
            .overlay {
                if let glow = state.trackGlow, glow.surface == .island {
                    TrackGlowLine(
                        outline: .island(
                            radii: radii, dockedEdges: IslandLayout.dockedEdges(anchor: state.anchor)),
                        tint: tint(of: glow), isVertical: IslandLayout.isSideDocked(state.anchor))
                        .id(glow.serial)
                }
            }
            .frame(width: frame.width, height: frame.height)
            // Content must not draw outside the shape while it springs between sizes.
            .clipShape(shape)
            .offset(x: frame.minX, y: frame.minY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(Self.spring, value: state.phase)
            .animation(Self.spring, value: state.showsWings)
            .animation(Self.spring, value: state.anchor)
            .animation(Self.spring, value: state.face)
    }

    /// The colours of the cover of the track the light greets.
    private func tint(of glow: TrackGlow) -> ArtworkTint? {
        let slot = state.mediaSlots.first { NowPlayingSource($0.info) == glow.source }
        return ArtworkCache.tint(for: slot?.info.artworkData)
    }

    @ViewBuilder
    private func content(atNotch: Bool, frame: CGRect) -> some View {
        switch state.phase {
        case .expanded:
            ExpandedIsland(
                state: state, metrics: headerMetrics(atNotch: atNotch, frame: frame),
                onCommand: onCommand, onVolume: onVolume, onOpenSession: onOpenSession,
                previews: previews, onFile: onFile)
                .transition(.opacity)
        case .collapsed, .stretching, .detached, .settling:
            collapsedFace(atNotch: atNotch)
                .transition(.opacity)
        }
    }

    /// The collapsed island shows one face: the first tab's if it has one, else the other's.
    @ViewBuilder
    private func collapsedFace(atNotch: Bool) -> some View {
        let lead = state.board.lead
        // On the media face an agent that wants attention still gets its mark.
        let attention = state.board.attentionRow?.state
        // A second source heard at the same time peeks out behind the main artwork.
        let behind = state.mediaSlots.dropFirst().first?.info
        // A docked island never hides: with no face it shows the paused track if there is
        // one, otherwise the first tab's idle text. When the agents speak without a lead
        // (all idle or merely running) it shows the first session of the list; the idle
        // text is for an empty list only.
        let agentsSpeak = state.face == .agents
            || (state.face == .none && state.nowPlaying == nil && state.tabOrder.first == .agents)

        if atNotch {
            switch state.face {
            case .agents:
                if let lead {
                    AgentNotchFace(row: lead, notchWidth: geometry.notch.width)
                        // Centred on the notch, not on the strip below it.
                        .padding(.bottom, IslandLayout.notchLip)
                }
            case .media:
                if let info = state.nowPlaying {
                    CollapsedContent(
                        info: info, behind: behind, notchWidth: geometry.notch.width, attention: attention)
                        .padding(.bottom, IslandLayout.notchLip)
                }
            case .none:
                EmptyView()
            }
        } else if IslandLayout.isSideDocked(state.anchor) {
            if agentsSpeak {
                AgentSideFace(row: state.board.spokesperson)
            } else {
                SideCollapsedContent(info: state.nowPlaying, attention: attention)
            }
        } else {
            if agentsSpeak {
                AgentFloatingFace(row: state.board.spokesperson)
            } else {
                FloatingCollapsedContent(info: state.nowPlaying, behind: behind, attention: attention)
            }
        }
    }

    /// At the notch the header shares its band with the camera housing; elsewhere it has
    /// a band of its own, split down the middle.
    private func headerMetrics(atNotch: Bool, frame: CGRect) -> ExpandedHeaderMetrics {
        guard atNotch else {
            return ExpandedHeaderMetrics(
                height: ExpandedIsland.dockedBandHeight,
                leading: frame.width / 2, gap: 0, trailing: frame.width / 2)
        }
        let notch = geometry.notch
        return ExpandedHeaderMetrics(
            height: notch.height,
            leading: max(notch.minX - frame.minX, 0),
            gap: notch.width,
            trailing: max(frame.maxX - notch.maxX, 0))
    }
}
