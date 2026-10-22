import AppKit
import SwiftUI

/// The text field an account's name turns into while `AccountRenameStore` has an edit open for it. It
/// takes focus as it appears. Return, a click anywhere else in the panel, or focus moving away commits
/// the edit; Esc cancels it. `PopoverKeyReader` leaves Return and Esc alone while a text field is
/// editing, so they reach this field instead of navigating the popover.
///
/// The field's background is drawn outside its frame, so swapping it in for the label it replaces
/// doesn't shift anything around it. Callers set the font and text alignment.
struct InlineRenameField: View {
    @Bindable var renaming: AccountRenameStore
    let edit: AccountRenameStore.Edit

    @FocusState private var isFocused: Bool

    private static let outset = CGSize(width: 4, height: 1)

    var body: some View {
        TextField("Account Name", text: $renaming.draft)
            .textFieldStyle(.plain)
            .lineLimit(1)
            .focused($isFocused)
            .onSubmit { renaming.commit(edit) }
            .onExitCommand { renaming.cancel(edit) }
            .onChange(of: isFocused) { _, focused in
                if !focused { renaming.commit(edit) }
            }
            .onAppear { isFocused = true }
            .padding(.horizontal, Self.outset.width)
            .padding(.vertical, Self.outset.height)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(.tint, lineWidth: 1)
                    }
            }
            .background(OutsideClickReader { renaming.commit(edit) })
            .padding(.horizontal, -Self.outset.width)
            .padding(.vertical, -Self.outset.height)
            .accessibilityLabel("Account Name")
    }
}

/// Reports a click anywhere else in this view's window. AppKit keeps a text field editing through
/// clicks on views that don't take focus, which is most of this panel, so focus alone never sees
/// those clicks. It only observes: the click still reaches whatever was clicked.
private struct OutsideClickReader: NSViewRepresentable {
    let onClickOutside: @MainActor () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onClickOutside = onClickOutside
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onClickOutside = onClickOutside
    }

    final class MonitorView: NSView {
        var onClickOutside: (@MainActor () -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                let eventWindowID = event.window.map(ObjectIdentifier.init)
                let location = event.locationInWindow
                MainActor.assumeIsolated {
                    guard let self, let window = self.window,
                          eventWindowID == ObjectIdentifier(window),
                          !self.bounds.contains(self.convert(location, from: nil)) else { return }
                    self.onClickOutside?()
                }
                return event
            }
        }
    }
}
