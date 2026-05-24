import SwiftUI

struct ReorderableStackCore<Axis: ReorderableAxis, Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable,
    Data.Index == Int, Data.Element.ID: Hashable
{
    let data: Data
    let coordinateSpaceName: String
    let externalCoordinateSpaceName: String?
    let onMove: (Int, Int) -> Void
    let onDragStateChange: (Bool) -> Void
    let onExternalDragChanged: (Data.Element, DragGesture.Value) -> Void
    let onExternalDragEnded: (Data.Element, DragGesture.Value) -> Void
    let content: (Data.Element, Bool) -> Content

    init(
        data: Data,
        coordinateSpaceName: String,
        externalCoordinateSpaceName: String? = nil,
        onMove: @escaping (Int, Int) -> Void,
        onDragStateChange: @escaping (Bool) -> Void,
        onExternalDragChanged: @escaping (Data.Element, DragGesture.Value) -> Void = { _, _ in },
        onExternalDragEnded: @escaping (Data.Element, DragGesture.Value) -> Void = { _, _ in },
        @ViewBuilder content: @escaping (Data.Element, Bool) -> Content
    ) {
        self.data = data
        self.coordinateSpaceName = coordinateSpaceName
        self.externalCoordinateSpaceName = externalCoordinateSpaceName
        self.onMove = onMove
        self.onDragStateChange = onDragStateChange
        self.onExternalDragChanged = onExternalDragChanged
        self.onExternalDragEnded = onExternalDragEnded
        self.content = content
    }

    @State private var frames: [Data.Element.ID: CGRect] = [:]
    @State private var dragging: Data.Element.ID?
    @State private var displayOffset: CGFloat = 0
    @State private var initialIndex: Int?
    @State private var currentIndex: Int?
    @State private var pendingDrop: Data.Element.ID?
    @State private var grabOffset: CGFloat?
    @State private var draggedSpan: CGFloat?

    var body: some View {
        ForEach(data) { datum in
            content(datum, datum.id == dragging)
                .background(frameReader(for: datum.id))
                .offset(Axis.offset(offsetFor(id: datum.id)))
                .zIndex(datum.id == dragging || datum.id == pendingDrop ? 10 : 0)
                .gesture(dragGesture(for: datum))
        }
        .onPreferenceChange(ReorderableFramePreferenceKey<Data.Element.ID>.self) { frames = $0 }
    }

    private func frameReader(for id: Data.Element.ID) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ReorderableFramePreferenceKey<Data.Element.ID>.self,
                value: [id: proxy.frame(in: .named(coordinateSpaceName))]
            )
        }
    }

    private func dragGesture(for datum: Data.Element) -> some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .named(coordinateSpaceName)),
            DragGesture(minimumDistance: 2, coordinateSpace: .named(externalCoordinateSpaceName ?? coordinateSpaceName))
        )
        .onChanged { value in
            guard let stackValue = value.first, let externalValue = value.second else { return }
            handleDrag(stackValue, datum: datum)
            onExternalDragChanged(datum, externalValue)
        }
        .onEnded { value in
            guard let stackValue = value.first, let externalValue = value.second else { return }
            handleDrag(stackValue, datum: datum)
            onExternalDragChanged(datum, externalValue)
            handleDrop()
            onExternalDragEnded(datum, externalValue)
        }
    }

    private func handleDrag(_ value: DragGesture.Value, datum: Data.Element) {
        displayOffset = Axis.project(size: value.translation)
        if dragging == nil {
            currentIndex = data.firstIndex { $0.id == datum.id }
            initialIndex = currentIndex
            dragging = datum.id
            captureDragStart(for: datum.id, at: value.startLocation)
            onDragStateChange(true)
        }
        updateInsertion(at: value.location, dragged: datum.id)
    }

    private func handleDrop() {
        withAnimation(KajiMotion.fast) {
            pendingDrop = dragging
            dragging = nil
            displayOffset = 0
            currentIndex = nil
            initialIndex = nil
            grabOffset = nil
            draggedSpan = nil
            onDragStateChange(false)
        } completion: {
            pendingDrop = nil
        }
    }

    private func captureDragStart(for id: Data.Element.ID, at location: CGPoint) {
        guard let frame = frames[id] else { return }
        let position = Axis.position(in: frame)
        grabOffset = Axis.project(point: location) - position.min
        draggedSpan = position.span
    }

    private func updateInsertion(at location: CGPoint, dragged: Data.Element.ID) {
        guard let currentIndex else { return }
        let dragPosition = Axis.project(point: location)
        let center = dragPosition - (grabOffset ?? 0) + (draggedSpan ?? 0) / 2
        let ids = data.map(\.id)
        guard let offset = ReorderableInsertionResolver.moveOffset(
            orderedIDs: ids,
            frames: frames,
            draggedID: dragged,
            dragCenter: center,
            position: Axis.position(in:)
        ), offset != currentIndex
        else { return }

        withAnimation(KajiMotion.fast) {
            onMove(currentIndex, offset)
        }
        self.currentIndex = offset > currentIndex ? offset - 1 : offset
    }

    private func offsetFor(id: Data.Element.ID) -> CGFloat {
        guard id == dragging else { return 0 }
        return displayOffset + positionOffset
    }

    private var positionOffset: CGFloat {
        guard let initialIndex,
              let currentIndex,
              data.indices.contains(initialIndex),
              data.indices.contains(currentIndex)
        else { return 0 }

        if currentIndex > initialIndex {
            return data[initialIndex ..< currentIndex]
                .map { frames[$0.id].map { Axis.position(in: $0).span } ?? 0 }
                .reduce(0, -)
        }
        if currentIndex < initialIndex {
            return data[(currentIndex + 1) ... initialIndex]
                .map { frames[$0.id].map { Axis.position(in: $0).span } ?? 0 }
                .reduce(0, +)
        }
        return 0
    }
}
