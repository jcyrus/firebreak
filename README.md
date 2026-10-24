# 🔥 Firebreak

> **The proactive thermal circuit-breaker and rogue process-swarm watchdog for macOS.**

Firebreak is a native macOS utility that detects, diagnoses, and neutralizes runaway multi-process swarms and background daemons before they push CPU/GPU temperatures to critical limits (>65°C / 100°C).

Unlike passive monitors that only show a temperature reading in the menu bar, Firebreak is **process-tree aware**: it rolls up nested child processes (e.g. 50+ iOS Simulator poster extensions, container workers, electron tabs), computes cumulative load, and provides 1-click remediation recipes.

---

## Architecture

- **`FirebreakCore` (Framework)**
  - `ThermalMonitor`: Dual-mode kernel telemetry (`ProcessInfo.thermalState` + Mach load statistics).
  - `ProcessEnumerator`: Sub-millisecond process inspection via `libproc.h` (`proc_listpids`, `proc_pidinfo`, `proc_pidpath`).
  - `SwarmAggregator`: Collapses child PIDs, XPC extensions (`.appex`), and container runtimes into high-level root application trees.
  - `AnomalyDetector`: Evaluates thermal velocity, core saturation, and multi-process runaway conditions.
  - `ProcessController`: POSIX signal dispatch (`SIGSTOP` freeze, `SIGCONT` thaw, `SIGKILL` nuke) across entire process swarms.
  - `DomainRecipes`: Domain recovery routines (e.g. `xcrun simctl shutdown all`, container pruning).
- **`firebreak` (CLI)**
  - Fast diagnostic commands: `status`, `scan`, `trip`, `cool`.
- **`FirebreakApp` (Native SwiftUI App — in development)**
  - Menu bar extra with live thermal badge and 1-click circuit breaker actions.

---

## Usage

### Quick Status
```zsh
swift run firebreak status
```

### Process Swarm Scan
```zsh
swift run firebreak scan
```

### Anomaly Check (CI / Cron / Scripted)
```zsh
swift run firebreak trip
# Exits with 0 if nominal, 1 if circuit breaker tripped
```

### Emergency Cool
```zsh
swift run firebreak cool
```

---

## License
MIT
