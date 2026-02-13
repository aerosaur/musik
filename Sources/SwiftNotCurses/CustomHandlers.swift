import Foundation
import notcurses

@MainActor fileprivate var _sigwinch_handler: (() async -> Void) = {}
@MainActor fileprivate var _sigint_handler: (() async -> Void) = {}

// Raw notcurses pointer for emergency cleanup in crash signal handlers.
// Signal handlers cannot use Swift async or MainActor, so we store the
// raw pointer for direct C-level cleanup.
nonisolated(unsafe) private var _notcurses_crash_pointer: OpaquePointer? = nil

@_cdecl("crash_handler")
private func crash_handler(_ sig: Int32) -> Void {
    // Reset terminal state so the shell is usable after crash
    if let pointer = _notcurses_crash_pointer {
        notcurses_stop(pointer)
        _notcurses_crash_pointer = nil
    }
    // Re-raise with default handler so the OS can produce a crash report
    signal(sig, SIG_DFL)
    raise(sig)
}

/// Register signal handlers that reset the terminal on fatal crashes.
/// Call this after notcurses is initialized.
public func setupCrashHandlers(notcurses: NotCurses) {
    _notcurses_crash_pointer = notcurses.pointer

    let signals: [Int32] = [SIGSEGV, SIGABRT, SIGBUS, SIGFPE, SIGILL]
    for sig in signals {
        var action = sigaction()
        action.__sigaction_u = unsafeBitCast(
            crash_handler as @convention(c) (Int32) -> Void,
            to: __sigaction_u.self
        )
        action.sa_flags = 0
        sigemptyset(&action.sa_mask)
        sigaction(sig, &action, nil)
    }
}

@_cdecl("sigwinch_handler")
private func sigwinch_handler(_ signal: Int32) -> Void {
    Task { @MainActor in
        await _sigwinch_handler()
    }
}

@_cdecl("sigint_handler")
private func sigint_handler(_ signal: Int32) -> Void {
    Task { @MainActor in
        await _sigint_handler()
    }
}

@MainActor
public func setupSigwinchHandler(onResize: @escaping @MainActor () async -> Void) {
    _sigwinch_handler = onResize
    var action = sigaction()
    action.__sigaction_u = unsafeBitCast(
        sigwinch_handler as @convention(c) (Int32) -> Void,
        to: __sigaction_u.self
    )
    action.sa_flags = 0
    sigemptyset(&action.sa_mask)

    if sigaction(SIGWINCH, &action, nil) != 0 {
        perror("sigaction")
        exit(1)
    }
}

@MainActor
public func setupSigintHandler(onStop: @escaping @MainActor () async -> Void) {
    _sigint_handler = onStop
    var action = sigaction()
    action.__sigaction_u = unsafeBitCast(
        sigint_handler as @convention(c) (Int32) -> Void,
        to: __sigaction_u.self
    )
    action.sa_flags = 0
    sigemptyset(&action.sa_mask)

    if sigaction(SIGINT, &action, nil) != 0 {
        perror("sigaction")
        exit(1)
    }
}
