// Engine cancellation callback. The context is caller-owned and opaque.
// Polling returns true when the current stage must stop with status 7.
pub fn never_poll(context: usize): bool {
    const ignored = context;
    return false;
}
