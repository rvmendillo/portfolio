#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface RYRuntimeBridge : NSObject
+ (NSString *)pythonRequest:(NSString *)json;
+ (void)cancelPython;
@end
@interface RYLocalModel : NSObject
- (BOOL)loadPath:(NSString *)path error:(NSError **)error;
- (NSString * _Nullable)generate:(NSArray<NSDictionary<NSString *, NSString *> *> *)messages
                         limit:(NSInteger)limit
                         token:(void (^)(NSString *))token
                         error:(NSError **)error;
- (void)cancel;
- (void)unload;
@end
NS_ASSUME_NONNULL_END
