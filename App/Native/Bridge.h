#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import "worse_query.h"
#import "bad_query.h"
#include "posterbridge.h"
typedef struct CF_BRIDGED_TYPE(id) __SecTask *SecTaskRef;
SecTaskRef _Nullable SecTaskCreateFromSelf(CFAllocatorRef _Nullable) CF_RETURNS_RETAINED;
CFTypeRef _Nullable SecTaskCopyValueForEntitlement(SecTaskRef _Nonnull, CFStringRef _Nonnull, CFErrorRef _Nullable *) CF_RETURNS_RETAINED;
