#import "ExceptionCatch.h"

BOOL TendederoCatchException(void (^block)(void), NSError **outError) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (outError) {
            *outError = [NSError errorWithDomain:exception.name ?: @"NSException"
                                            code:0
                                        userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @""}];
        }
        return NO;
    }
}
