#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` inside an Objective-C @try/@catch and returns the caught
/// NSException, or nil if the block completed normally.
///
/// Why this exists: Swift's `try`/`catch` only handles Swift errors — it cannot
/// catch Objective-C NSExceptions, which unwind past Swift frames and terminate
/// the process. AVAudioEngine raises NSExceptions for input-format races
/// (e.g. "Failed to create tap due to format mismatch" when an OS-initiated
/// route change invalidates the input format between the format check and
/// `installTap`/`start`). A Swift-side format guard narrows that window but
/// cannot close it, so the calls are routed through this shim and any caught
/// exception is converted into a throwable Swift error.
///
/// The block is NS_NOESCAPE: it runs synchronously before this function returns.
NSException * _Nullable TNCatchObjCException(void (NS_NOESCAPE ^ _Nonnull block)(void));

NS_ASSUME_NONNULL_END
