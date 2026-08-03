#import "TNExceptionCatcher.h"

NSException * _Nullable TNCatchObjCException(void (NS_NOESCAPE ^ _Nonnull block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return exception;
    }
}
