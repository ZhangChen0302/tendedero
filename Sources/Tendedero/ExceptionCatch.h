#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
/// Runs the block and returns YES. On an Objective-C exception, fills outError and returns NO.
BOOL TendederoCatchException(void (^block)(void), NSError * _Nullable * _Nullable outError);
NS_ASSUME_NONNULL_END
