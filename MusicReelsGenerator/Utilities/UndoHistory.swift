import Foundation
import Combine

/// Snapshot-based undo/redo stack for `Project`.
///
/// Holds JSON-encoded snapshots of project state taken *before* each mutation.
/// Consecutive mutations sharing a `coalesceKey` within `coalesceWindow` merge
/// into a single undo step — so dragging a slider produces one waypoint, not
/// one per tick.
@MainActor
final class UndoHistory: ObservableObject {
    struct Snapshot {
        let data: Data
        let label: String
        let coalesceKey: String?
        var timestamp: Date
    }

    @Published private(set) var canUndo: Bool = false
    @Published private(set) var canRedo: Bool = false
    @Published private(set) var lastActionLabel: String = ""

    private var past: [Snapshot] = []
    private var future: [Snapshot] = []

    private let limit: Int
    private let coalesceWindow: TimeInterval

    init(limit: Int = 50, coalesceWindow: TimeInterval = 0.6) {
        self.limit = limit
        self.coalesceWindow = coalesceWindow
    }

    /// Record a snapshot captured *before* applying a mutation.
    /// When `coalesceKey` matches the most-recent entry within the window,
    /// the new snapshot is dropped (the original pre-action state is kept).
    func record(_ data: Data, label: String, coalesceKey: String? = nil) {
        if let key = coalesceKey,
           let last = past.last,
           last.coalesceKey == key,
           Date().timeIntervalSince(last.timestamp) < coalesceWindow {
            past[past.count - 1].timestamp = Date()
            future.removeAll()
            refresh()
            return
        }

        past.append(Snapshot(data: data, label: label, coalesceKey: coalesceKey, timestamp: Date()))
        if past.count > limit { past.removeFirst(past.count - limit) }
        future.removeAll()
        refresh()
    }

    func undo(current: Data) -> (data: Data, label: String)? {
        guard let snap = past.popLast() else { return nil }
        future.append(Snapshot(data: current, label: snap.label, coalesceKey: nil, timestamp: Date()))
        lastActionLabel = snap.label
        refresh()
        return (snap.data, snap.label)
    }

    func redo(current: Data) -> (data: Data, label: String)? {
        guard let snap = future.popLast() else { return nil }
        past.append(Snapshot(data: current, label: snap.label, coalesceKey: nil, timestamp: Date()))
        lastActionLabel = snap.label
        refresh()
        return (snap.data, snap.label)
    }

    func clear() {
        past.removeAll()
        future.removeAll()
        lastActionLabel = ""
        refresh()
    }

    private func refresh() {
        canUndo = !past.isEmpty
        canRedo = !future.isEmpty
    }
}
