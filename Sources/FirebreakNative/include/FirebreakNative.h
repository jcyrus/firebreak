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

#ifdef __cplusplus
}
#endif

#endif /* FirebreakNative_h */
