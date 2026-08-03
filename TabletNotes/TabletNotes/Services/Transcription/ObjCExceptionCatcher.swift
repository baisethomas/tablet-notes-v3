import Foundation

/// Swift-facing wrapper around the Objective-C @try/@catch shim.
///
/// Swift cannot catch NSExceptions; AVAudioEngine raises them for input-format
/// races (route change between the format check and `installTap`/`start`).
/// Call sites run the risky AVAudioEngine calls inside `catching` and convert a
/// non-nil result into a thrown Swift error.
enum ObjCExceptionCatcher {
    /// Runs `block` and returns the NSException it raised, or nil if it
    /// completed normally. The block runs synchronously.
    static func catching(_ block: () -> Void) -> NSException? {
        TNCatchObjCException(block)
    }
}
