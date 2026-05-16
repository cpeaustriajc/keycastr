import XCTest
@testable import Visualizer

/// 1:1 Swift port of `_legacy/KCVisualizerTests/KCMouseEventVisualizerTests.m`.
@MainActor
final class MouseEventVisualizerTests: XCTestCase {

    private var visualizer: MouseEventVisualizer!
    private var delegate: MouseEventDelegateSpy!

    override func setUp() {
        super.setUp()
        visualizer = MouseEventVisualizer()
        delegate = MouseEventDelegateSpy()
        visualizer.delegate = delegate
    }

    override func tearDown() {
        visualizer = nil
        delegate = nil
        super.tearDown()
    }

    func test_forwardingMouseEvents() {
        let fakeMouseEvent = MouseEvent(nsEvent: nil)

        // .none
        visualizer.selectedMouseDisplayOptionIndex = 0
        visualizer.noteMouseEvent(fakeMouseEvent)
        XCTAssertEqual(0, delegate.eventsReceived.count)

        // .withPointer
        visualizer.selectedMouseDisplayOptionIndex = 1
        visualizer.noteMouseEvent(fakeMouseEvent)
        XCTAssertEqual(0, delegate.eventsReceived.count)

        // .withVisualizer
        visualizer.selectedMouseDisplayOptionIndex = 2
        visualizer.noteMouseEvent(fakeMouseEvent)
        XCTAssertEqual(1, delegate.eventsReceived.count)
        delegate.eventsReceived.removeAll()

        // .withPointerAndVisualizer
        visualizer.selectedMouseDisplayOptionIndex = 3
        visualizer.noteMouseEvent(fakeMouseEvent)
        XCTAssertEqual(1, delegate.eventsReceived.count)
    }
}

@MainActor
private final class MouseEventDelegateSpy: MouseEventVisualizerDelegate {
    var eventsReceived: [MouseEvent] = []

    func mouseEventVisualizer(_ visualizer: MouseEventVisualizer, didNote event: MouseEvent) {
        eventsReceived.append(event)
    }
}
