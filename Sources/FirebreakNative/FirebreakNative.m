#import <Foundation/Foundation.h>
#import "include/FirebreakNative.h"

#if MAS_BUILD

// Mac App Store build stub: omits private IOKit HID APIs to comply with Guideline 2.5.1
NSDictionary<NSString *, NSNumber *> *FBReadHardwareSensors(void) {
    return @{};
}

double FBGetMaxDieTemperatureCelsius(void) {
    return -1.0;
}

double FBGetAverageDieTemperatureCelsius(void) {
    return -1.0;
}

double FBGetCPUCoreAverageTemperatureCelsius(void) {
    return -1.0;
}

double FBGetCPUCoreMaxTemperatureCelsius(void) {
    return -1.0;
}

#else

#include <IOKit/hidsystem/IOHIDEventSystemClient.h>
#include <IOKit/IOKitLib.h>

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
    FBInternalHIDSensorSource *source = getSharedSource();
    // The watchdog scan and the menu bar temperature loop read concurrently; the source caches
    // and releases its CFArray of services, so access must be serialized.
    @synchronized (source) {
        return [source readPage:0xff00 usage:5 type:15];
    }
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

// MARK: - SMC per-core CPU sensors
//
// The HID "PMU tdie" sensors above sit away from the CPU cores and read ~10°C cooler than the cores
// under load. The SMC exposes one float ("flt ") key per core sensor: Tp* on Apple Silicon (Te* on
// some chips). Reading them uses the AppleSMC IOKit user client, the same interface Stats and iStat use.

typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } FBSMCVersion;
typedef struct { uint16_t version, length; uint32_t cpuPLimit, gpuPLimit, memPLimit; } FBSMCPLimit;
typedef struct { uint32_t dataSize; uint32_t dataType; uint8_t dataAttributes; } FBSMCKeyInfo;
typedef struct {
    uint32_t key;
    FBSMCVersion vers;
    FBSMCPLimit pLimitData;
    FBSMCKeyInfo keyInfo;
    uint8_t result, status, data8;
    uint32_t data32;
    uint8_t bytes[32];
} FBSMCParam;

enum { kFBSMCHandleYPCEvent = 2, kFBSMCReadBytes = 5, kFBSMCReadIndex = 8, kFBSMCReadKeyInfo = 9 };

static uint32_t FBSMCKey(const char *s) {
    return ((uint32_t)s[0] << 24) | ((uint32_t)s[1] << 16) | ((uint32_t)s[2] << 8) | (uint32_t)s[3];
}

@interface FBInternalSMCReader : NSObject {
    io_connect_t _connection;
    BOOL _openFailed;
    NSArray<NSNumber *> *_cpuKeys;   // packed uint32 keys, discovered once
    NSArray<NSNumber *> *_cpuSizes;  // matching dataSize per key
    NSTimeInterval _lastSample;
    double _lastAverage;
    double _lastMax;
}
- (void)sampleAverage:(double *)average max:(double *)max;
@end

@implementation FBInternalSMCReader

- (void)dealloc {
    if (_connection) { IOServiceClose(_connection); }
}

- (BOOL)call:(FBSMCParam *)input output:(FBSMCParam *)output {
    size_t outSize = sizeof(FBSMCParam);
    kern_return_t kr = IOConnectCallStructMethod(_connection, kFBSMCHandleYPCEvent,
                                                 input, sizeof(FBSMCParam), output, &outSize);
    return kr == KERN_SUCCESS && output->result == 0;
}

- (BOOL)keyInfo:(uint32_t)key into:(FBSMCKeyInfo *)info {
    FBSMCParam in = {0}, out = {0};
    in.key = key;
    in.data8 = kFBSMCReadKeyInfo;
    if (![self call:&in output:&out]) { return NO; }
    *info = out.keyInfo;
    return YES;
}

- (BOOL)read:(uint32_t)key size:(uint32_t)size into:(uint8_t *)bytes {
    FBSMCParam in = {0}, out = {0};
    in.key = key;
    in.keyInfo.dataSize = size;
    in.data8 = kFBSMCReadBytes;
    if (![self call:&in output:&out]) { return NO; }
    memcpy(bytes, out.bytes, sizeof(out.bytes));
    return YES;
}

- (BOOL)open {
    if (_connection) { return YES; }
    if (_openFailed) { return NO; }
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service || IOServiceOpen(service, mach_task_self(), 0, &_connection) != KERN_SUCCESS) {
        _openFailed = YES;
        if (service) { IOObjectRelease(service); }
        return NO;
    }
    IOObjectRelease(service);
    return YES;
}

/// Walks the full key list once (~1-2k keys) and keeps the CPU core float sensors.
- (void)discoverCPUKeys {
    FBSMCKeyInfo info;
    uint8_t bytes[32];
    uint32_t countKey = FBSMCKey("#KEY");
    if (![self keyInfo:countKey into:&info] || ![self read:countKey size:info.dataSize into:bytes]) {
        _cpuKeys = @[];
        _cpuSizes = @[];
        return;
    }
    uint32_t count = ((uint32_t)bytes[0] << 24) | ((uint32_t)bytes[1] << 16) | ((uint32_t)bytes[2] << 8) | bytes[3];
    uint32_t floatType = FBSMCKey("flt ");
    
    NSMutableArray *pKeys = [NSMutableArray array], *pSizes = [NSMutableArray array];
    NSMutableArray *eKeys = [NSMutableArray array], *eSizes = [NSMutableArray array];
    for (uint32_t i = 0; i < count; i++) {
        FBSMCParam in = {0}, out = {0};
        in.data8 = kFBSMCReadIndex;
        in.data32 = i;
        if (![self call:&in output:&out]) { continue; }
        uint32_t key = out.key;
        char c0 = (char)(key >> 24), c1 = (char)(key >> 16);
        if (c0 != 'T' || (c1 != 'p' && c1 != 'e')) { continue; }
        if (![self keyInfo:key into:&info] || info.dataType != floatType || info.dataSize != 4) { continue; }
        if (c1 == 'p') {
            [pKeys addObject:@(key)];
            [pSizes addObject:@(info.dataSize)];
        } else {
            [eKeys addObject:@(key)];
            [eSizes addObject:@(info.dataSize)];
        }
    }
    BOOL usePerformance = pKeys.count > 0;
    _cpuKeys = usePerformance ? pKeys : eKeys;
    _cpuSizes = usePerformance ? pSizes : eSizes;
}

- (void)sampleAverage:(double *)average max:(double *)max {
    NSTimeInterval now = NSProcessInfo.processInfo.systemUptime;
    // Average and max are usually requested back to back; share one hardware read.
    if (_lastSample > 0 && (now - _lastSample) < 0.5) {
        *average = _lastAverage;
        *max = _lastMax;
        return;
    }
    *average = -1.0;
    *max = -1.0;
    if (![self open]) { return; }
    if (!_cpuKeys) { [self discoverCPUKeys]; }
    
    double sum = 0.0, hottest = -1.0;
    int count = 0;
    uint8_t bytes[32];
    for (NSUInteger i = 0; i < _cpuKeys.count; i++) {
        if (![self read:_cpuKeys[i].unsignedIntValue size:_cpuSizes[i].unsignedIntValue into:bytes]) { continue; }
        float value;
        memcpy(&value, bytes, sizeof(value));
        if (value <= 0.0f || value >= 150.0f) { continue; }
        sum += value;
        count++;
        if (value > hottest) { hottest = value; }
    }
    if (count > 0) {
        *average = sum / count;
        *max = hottest;
    }
    _lastSample = now;
    _lastAverage = *average;
    _lastMax = *max;
}

@end

static FBInternalSMCReader *getSharedSMCReader(void) {
    static FBInternalSMCReader *reader = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        reader = [[FBInternalSMCReader alloc] init];
    });
    return reader;
}

static void FBSampleCPUCores(double *average, double *max) {
    FBInternalSMCReader *reader = getSharedSMCReader();
    @synchronized (reader) {
        [reader sampleAverage:average max:max];
    }
}

double FBGetCPUCoreAverageTemperatureCelsius(void) {
    double average, max;
    FBSampleCPUCores(&average, &max);
    return average;
}

double FBGetCPUCoreMaxTemperatureCelsius(void) {
    double average, max;
    FBSampleCPUCores(&average, &max);
    return max;
}

#endif
