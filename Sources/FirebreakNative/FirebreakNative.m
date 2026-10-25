#import <Foundation/Foundation.h>
#import "include/FirebreakNative.h"
#include <IOKit/hidsystem/IOHIDEventSystemClient.h>

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
#define IOHIDEventFieldBase(type)   (type << 16)

IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef, int64_t, int32_t, int64_t);
CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

@interface FBInternalHIDSensorSource : NSObject {
    IOHIDEventSystemClientRef _client;
    CFArrayRef _services;
    NSTimeInterval _lastDiscovery;
    BOOL _missingEvents;
}
- (NSDictionary<NSString *, NSNumber *> *)readPage:(int32_t)page usage:(int32_t)usage type:(int32_t)type;
@end

@implementation FBInternalHIDSensorSource

- (void)dealloc {
    if (_services) { CFRelease(_services); _services = NULL; }
    if (_client) { CFRelease(_client); _client = NULL; }
}

- (NSDictionary<NSString *, NSNumber *> *)readPage:(int32_t)page usage:(int32_t)usage type:(int32_t)type {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    if (!_client) {
        _client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!_client) { return @{}; }
        NSDictionary *matching = @{@"PrimaryUsagePage": @(page), @"PrimaryUsage": @(usage)};
        IOHIDEventSystemClientSetMatching(_client, (__bridge CFDictionaryRef)matching);
    }
    
    NSTimeInterval discoveryInterval = _missingEvents ? 5.0 : 60.0;
    if (!_services || (now - _lastDiscovery) >= discoveryInterval) {
        if (_services) { CFRelease(_services); }
        _services = IOHIDEventSystemClientCopyServices(_client);
        _lastDiscovery = now;
        if (!_services || CFArrayGetCount(_services) == 0) {
            return @{};
        }
    }
    
    NSMutableDictionary<NSString *, NSNumber *> *dict = [NSMutableDictionary dictionary];
    _missingEvents = NO;
    CFIndex count = CFArrayGetCount(_services);
    for (CFIndex i = 0; i < count; i++) {
        IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(_services, i);
        NSString *name = CFBridgingRelease(IOHIDServiceClientCopyProperty(service, CFSTR("Product")));
        
        IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, type, 0, 0);
        if (event == nil) {
            _missingEvents = YES;
            continue;
        }
        
        if (name && event) {
            double value = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(type));
            if (value > 0.0 && value < 150.0) {
                dict[name] = @(value);
            }
        }
        CFRelease(event);
    }
    return dict;
}

@end

static FBInternalHIDSensorSource *getSharedSource(void) {
    static FBInternalHIDSensorSource *source = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        source = [[FBInternalHIDSensorSource alloc] init];
    });
    return source;
}

NSDictionary<NSString *, NSNumber *> *FBReadHardwareSensors(void) {
    return [getSharedSource() readPage:0xff00 usage:5 type:15];
}

double FBGetMaxDieTemperatureCelsius(void) {
    NSDictionary<NSString *, NSNumber *> *sensors = FBReadHardwareSensors();
    if (sensors.count == 0) {
        return -1.0;
    }
    
    double maxTemp = -1.0;
    for (NSString *key in sensors) {
        // Prioritize PMU tdie, PMU TP, and Apple Silicon thermal nodes
        if ([key containsString:@"tdie"] || [key containsString:@"TP"] || [key containsString:@"temp"]) {
            double val = [sensors[key] doubleValue];
            if (val > maxTemp) {
                maxTemp = val;
            }
        }
    }
    return maxTemp;
}

double FBGetAverageDieTemperatureCelsius(void) {
    NSDictionary<NSString *, NSNumber *> *sensors = FBReadHardwareSensors();
    if (sensors.count == 0) {
        return -1.0;
    }
    
    double sum = 0.0;
    int count = 0;
    for (NSString *key in sensors) {
        if ([key containsString:@"tdie"]) {
            sum += [sensors[key] doubleValue];
            count++;
        }
    }
    return count > 0 ? (sum / (double)count) : -1.0;
}
