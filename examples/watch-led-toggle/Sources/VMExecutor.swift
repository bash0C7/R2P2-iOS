import Foundation

final class VMExecutor {
    static let shared = VMExecutor()

    private let queue = DispatchQueue(label: "com.bash0c7.watch.vm")
    private var vm: UnsafeMutableRawPointer?
    private var timer: DispatchSourceTimer?
    var onColorChange: ((String) -> Void)?

    private init() {}

    func start(bootSource: String, onColor: @escaping (String) -> Void) {
        self.onColorChange = onColor
        queue.async {
            guard self.vm == nil else { return }
            guard let handle = bootSource.withCString({ vm_open($0) }) else {
                NSLog("[WatchLEDToggle] vm_open returned NULL")
                return
            }
            self.vm = handle
            NSLog("[WatchLEDToggle] VM opened")
            self.startTick()
        }
    }

    func toggle() {
        queue.async { [weak self] in
            guard let self = self, let vm = self.vm else { return }
            let out = "toggle".withCString { m in
                "".withCString { a in vm_call(vm, m, a) }
            }
            let color = out.map {
                String(cString: $0).trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? ""
            if let o = out { free(o) }
            guard !color.isEmpty else { return }
            DispatchQueue.main.async { self.onColorChange?(color) }
        }
    }

    private func startTick() {
        timer?.cancel()
        timer = nil
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.1, repeating: 0.1)
        t.setEventHandler { [weak self] in
            guard let self = self, let vm = self.vm else { return }
            let out = "tick".withCString { m in
                "".withCString { a in vm_call(vm, m, a) }
            }
            let color = out.map {
                String(cString: $0).trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? ""
            if let o = out { free(o) }
            guard color == "red" || color == "blue" else { return }
            DispatchQueue.main.async { self.onColorChange?(color) }
        }
        t.resume()
        self.timer = t
    }
}
