#ifndef FirebreakNative_h
#define FirebreakNative_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Reads all available hardware temperature sensors via IOKit HID.
NSDictionary<NSString *, NSNumber *> * _Nonnull FBReadHardwareSensors(void);

/// Returns the highest CPU/GPU/SoC die temperature in Celsius, or -1.0 if unavailable.
double FBGetMaxDieTemperatureCelsius(void);

/// Returns the average CPU die core temperature in Celsius, or -1.0 if unavailable.
double FBGetAverageDieTemperatureCelsius(void);

/// Average of the SMC per-core CPU temperature sensors (Tp* keys, falling back to Te*) in Celsius,
/// or -1.0 if unavailable. Matches what Stats / iStat report as "Average CPU" within ~1-2°C.
double FBGetCPUCoreAverageTemperatureCelsius(void);

/// Hottest SMC per-core CPU temperature sensor in Celsius, or -1.0 if unavailable.
double FBGetCPUCoreMaxTemperatureCelsius(void);

#ifdef __cplusplus
}
#endif

#endif /* FirebreakNative_h */
