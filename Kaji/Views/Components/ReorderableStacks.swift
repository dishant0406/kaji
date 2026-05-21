import SwiftUI

struct ReorderableHStack<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable, Data.Index == Int, Data.Element.ID: Hashable {
    let data: Data
    let onMove: (Int, Int) -> Void
    var onDragStateChange: (Bool) -> Void = { _ in }
    var externalCoordinateSpaceName: String?
    var onExternalDragChanged: (Data.Element, DragGesture.Value) -> Void = { _, _ in }
    var onExternalDragEnded: (Data.Element, DragGesture.Value) -> Void = { _, _ in }
    let content: (Data.Element, Bool) -> Content

    @State private var coordinateSpaceName = UUID().uuidString

    init(
        _ data: Data,
        onMove: @escaping (Int, Int) -> Void,
        onDragStateChange: @escaping (Bool) -> Void = { _ in },
        externalCoordinateSpaceName: String? = nil,
        onExternalDragChanged: @escaping (Data.Element, DragGesture.Value) -> Void = { _, _ in },
        onExternalDragEnded: @escaping (Data.Element, DragGesture.Value) -> Void = { _, _ in },
        @ViewBuilder content: @escaping (Data.Element, Bool) -> Content
    ) {
        self.data = data
        self.onMove = onMove
        self.onDragStateChange = onDragStateChange
        self.externalCoordinateSpaceName = externalCoordinateSpaceName
        self.onExternalDragChanged = onExternalDragChanged
        self.onExternalDragEnded = onExternalDragEnded
        self.content = content
    }

    var body: some View {
        HStack(spacing: 0) {
            ReorderableStackCore<ReorderableHorizontalAxis, Data, Content>(
                data: data,
                coordinateSpaceName: coordinateSpaceName,
                externalCoordinateSpaceName: externalCoordinateSpaceName,
                onMove: onMove,
                onDragStateChange: onDragStateChange,
                onExternalDragChanged: onExternalDragChanged,
                onExternalDragEnded: onExternalDragEnded
            ) { datum, isDragged in
                content(datum, isDragged)
            }
        }
        .coordinateSpace(name: coordinateSpaceName)
    }
}

struct ReorderableVStack<Data: RandomAccessCollection, Content: View>: View where Data.Element: Identifiable, Data.Index == Int, Data.Element.ID: Hashable {
    let data: Data
    let onMove: (Int, Int) -> Void
    var onDragStateChange: (Bool) -> Void = { _ in }
    let content: (Data.Element, Bool) -> Content

    @State private var coordinateSpaceName = UUID().uuidString

    init(
        _ data: Data,
        onMove: @escaping (Int, Int) -> Void,
        onDragStateChange: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder content: @escaping (Data.Element, Bool) -> Content
    ) {
        self.data = data
        self.onMove = onMove
        self.onDragStateChange = onDragStateChange
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            ReorderableStackCore<ReorderableVerticalAxis, Data, Content>(
                data: data,
                coordinateSpaceName: coordinateSpaceName,
                onMove: onMove,
                onDragStateChange: onDragStateChange
            ) { datum, isDragged in
                content(datum, isDragged)
            }
        }
        .coordinateSpace(name: coordinateSpaceName)
    }
}
