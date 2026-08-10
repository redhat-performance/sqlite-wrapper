# SQLite Benchmark Wrapper

## Description

This wrapper facilitates the automated execution of an SQLite database benchmark. The benchmark measures SQLite insert performance under concurrent load by creating multiple database instances, each populated with randomized records in parallel. It stresses the I/O subsystem, filesystem journaling (WAL mode), and process scheduling under varying levels of concurrency.

The wrapper provides:
- Automated SQLite benchmark setup and execution.
- Configurable table sizes and concurrency levels.
- Multi-iteration testing with averaged results.
- Result collection, processing, and verification.
- CSV and JSON output formats.
- System configuration metadata capture.
- Integration with test_tools framework.
- Optional Performance Co-Pilot (PCP) integration.

## Command-Line Options

```
SQLite Options:
  --table_entries <a,b,c...>: Comma-separated list of table sizes to create.
      Each value specifies the number of rows to insert per database. Default: 5000.
  --procs <a,b,c...>: Comma-separated list of process counts to test.
      Each value specifies how many concurrent SQLite database processes to run.
      If not set, automatically generates intervals up to the number of CPU cores (max 8 intervals).

General test_tools options:
  --home_parent <value>: Parent home directory. If not set, defaults to current working directory.
  --host_config <value>: Host configuration name, defaults to current hostname.
  --iterations <value>: Number of times to run the test, defaults to 1.
  --run_user: User that is actually running the test on the test system. Defaults to current user.
  --sys_type: Type of system working with (aws, azure, hostname). Defaults to hostname.
  --sysname: Name of the system running, used in determining config files. Defaults to hostname.
  --tuned_setting: Used in naming the results directory. For RHEL, defaults to current active tuned profile.
      For non-RHEL systems, defaults to 'none'.
  --use_pcp: Enable Performance Co-Pilot monitoring during test execution.
  --tools_git <value>: Git repo to retrieve the required tools from.
      Default: https://github.com/redhat-performance/test_tools-wrappers
  --usage: Display this usage message.
```

## What the Script Does

The `run_sqlite.sh` script performs the following workflow:

1. **Environment Setup**:
   - Clones the test_tools-wrappers repository if not present (default: ~/test_tools).
   - Sources error codes and general setup utilities.
   - Gathers system hardware information.

2. **Package Installation**:
   - Installs required dependencies via package_tool: sqlite, sqlite-devel, gcc, git, bc, time, and others.
   - Dependencies are defined in sqlite.json for RHEL-based systems.

3. **Process List Generation**:
   - If `--procs` is not specified, automatically determines concurrency levels.
   - Detects the number of CPU cores via `nproc`.
   - Generates evenly spaced intervals up to the core count (capped at 8 intervals).

4. **Table Entry Generation**:
   - Generates a file of SQL INSERT statements with randomized data for each requested table size.
   - Each record contains a sequence number, timestamp, a random 4-digit value (F1), and a random 16-digit value (F2).
   - Insertion files are cached and reused if they already exist for a given table size.

5. **Database Creation and Execution**:
   - For each combination of iteration, table size, and process count:
     - Spawns the requested number of concurrent processes.
     - Each process creates its own SQLite database with WAL journaling mode.
     - Creates a table `pts1` with columns: I (SMALLINT), DT (TIMESTAMP), F1 (VARCHAR(4)), F2 (VARCHAR(16)).
     - Each process inserts the full set of records 3 times sequentially.
     - A ready file synchronizes all processes to start simultaneously.
   - Execution time is captured via `/bin/time` for each process.

6. **Data Collection**:
   - Captures elapsed, system, and user time for each process in `sqlite_timeing_*` files.
   - Records start and end timestamps for each process.
   - Optionally records PCP performance data during execution.

7. **Result Processing**:
   - Groups results by table size and process count.
   - Averages elapsed time across iterations and processes.
   - Sums user and system time across processes, then averages across iterations.
   - Generates CSV files with configuration and performance data.
   - Creates JSON output for verification.
   - Validates results against Pydantic schema (results_schema.py).

8. **Verification**:
   - Validates results against Pydantic schema ensuring:
     - Table entries and process counts are positive integers.
     - All time values are positive, finite numbers.
     - Timestamps are valid datetime objects.
   - Uses csv_to_json and verify_results from test_tools.

9. **Output**:
   - Creates results directory in `${HOME}/export_results/sqlite_<YYYY.MM.DD-HH.MM.SS>`.
   - Saves all raw timing files, processed CSV/JSON, and system metadata.
   - Optionally saves PCP performance data.
   - Archives results to configured storage location.

## Dependencies

**General packages required**: sqlite, sqlite-devel, gcc, git, bc, time, wget, tcl, tcl-devel, zip, unzip, perf

**Additional RHEL packages**: lksctp-tools-devel, perl-FindBin, perl-IPC-Cmd, perl-Time-Piece, pcp-zeroconf, pcp-pmda-openmetrics, pcp-pmda-denki

To run:
```bash
git clone <repository-url>
cd sqlite-wrapper/sqlite
./run_sqlite.sh
```

The script will automatically detect your CPU configuration and generate appropriate concurrency levels.

## The SQLite Benchmark

The benchmark tests SQLite insert throughput under concurrent load using WAL (Write-Ahead Logging) journaling mode.

### Database Schema

Each database instance uses a single table:

```sql
CREATE TABLE pts1 (
    'I'  SMALLINT NOT NULL,
    'DT' TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    'F1' VARCHAR(4) NOT NULL,
    'F2' VARCHAR(16) NOT NULL
);
```

- **I**: Sequential record number.
- **DT**: Insertion timestamp.
- **F1**: Random 4-digit value.
- **F2**: Random 16-digit value.

### Execution Model

For each process count N:
1. N independent SQLite databases are created, each with WAL journaling enabled.
2. All N processes wait on a synchronization barrier (ready file).
3. Once released, each process inserts the full record set 3 times sequentially.
4. Timing is average across allprocess.

### Performance Metrics

Each test configuration reports five key metrics:

1. **Real_time**: Average elapsed (wall-clock) time per process across iterations.
2. **User_time**: Total user-space CPU time summed across processes.
3. **System_time**: Total kernel CPU time summed across processes.
4. **Start_Date**: Timestamp when the test run began.
5. **End_Date**: Timestamp when the test run completed.

## Output Files

The results directory contains:

- **results_sqlite_\<entries\>.csv**: CSV file with performance metrics for each table size
- **sqlite_verify.json**: JSON file with validated results data
- **sqlite_timeing_\***: Raw timing files from each process in each iteration
- **sqlite-insertions_\<entries\>**: Cached SQL insertion files for each table size
- **runner_db_\***: Generated execution scripts for each database process
- **meta_data\*.yml**: System metadata (CPU info, memory, kernel version)
- **PCP data** (if --use_pcp option used): Performance Co-Pilot monitoring data

## Examples

### Basic run with defaults
```bash
./run_sqlite.sh
```
This runs with:
- 5000 table entries
- Automatically determined process counts (up to 8 intervals across available cores)
- 1 iteration of the complete test suite

### Run with specific table sizes
```bash
./run_sqlite.sh --table_entries 1000,5000,10000
```
Tests with three different table sizes to measure how insert volume affects performance.

### Run with specific process counts
```bash
./run_sqlite.sh --procs 1,4,8,16
```
Tests with 1, 4, 8, and 16 concurrent database processes.

### Run multiple iterations
```bash
./run_sqlite.sh --iterations 3
```
Runs the complete test suite 3 times and averages the results for consistency.

### Run with PCP monitoring
```bash
./run_sqlite.sh --use_pcp
```
Collects Performance Co-Pilot data during the run for detailed performance analysis.

### Combination example
```bash
./run_sqlite.sh --table_entries 5000,10000 --procs 1,4,8 --iterations 3 --use_pcp
```
Runs 3 iterations with PCP monitoring, testing two table sizes across three concurrency levels.

## How Concurrency Scaling Works

### Default Behavior (Auto-detected)
When `--procs` is not specified:
- The script detects the number of CPU cores via `nproc`.
- If the system has fewer than 8 cores, it uses the core count as the number of intervals.
- Otherwise, it generates 8 evenly spaced intervals up to the core count.
- For example, on a 32-core system: 4, 8, 12, 16, 20, 24, 28, 32.

### With --procs
Specify exact process counts to test:
- Useful for targeting specific concurrency levels.
- Allows testing beyond the core count for oversubscription analysis.

## How Result Averaging Works

When running multiple iterations (--iterations > 1):

1. Each iteration produces a complete set of timing results for all process/table-entry combinations.
2. Raw timing results are saved in separate `sqlite_timeing_*` files.
3. The wrapper extracts metrics from each iteration:
   - Elapsed time is averaged across iterations and processes.
   - User and system time are summed across processes, then averaged across iterations.
4. Summary CSV shows averaged values with 2 decimal places.

This approach:
- Reduces impact of transient system effects.
- Provides more reliable performance measurements.
- Helps identify result variance across runs.

## Return Codes

The script uses standardized error codes from test_tools error_codes:
- **0 (E_SUCCESS)**: Success
- **101**: Git clone failure
- **E_USAGE**: Invalid usage/arguments
- Non-zero exit from csv_to_json or verify_results indicates validation failure.

## Notes

### Supported Platforms
- **Linux**: x86_64 and aarch64 architectures
- **OS Support**: RHEL (primary, with full package definitions in sqlite.json)

### Performance Considerations
- The benchmark is I/O-intensive, particularly with large table sizes and high concurrency.
- WAL journaling mode is used for each database, which allows concurrent reads during writes.
- Each process operates on its own independent database file, so contention is at the filesystem level rather than database lock level.
- Larger table sizes (--table_entries) increase both I/O volume and memory pressure.
- Higher process counts stress the I/O scheduler and filesystem journaling.

### Insertion Data Caching
- The script caches generated SQL insertion files as `sqlite-insertions_<count>`.
- Subsequent runs with the same table size reuse the cached file.
- Delete cached files to regenerate with new random data.

### WAL Journaling Mode
Each database is created with `PRAGMA journal_mode='wal'`:
- Write-Ahead Logging provides better concurrency than the default rollback journal.
- Readers do not block writers, and writers do not block readers.
- This is the recommended mode for concurrent SQLite workloads.

### Performance Tips
- Run multiple iterations (--iterations 3+) to verify consistency.
- Ensure the system is idle (no other workloads) for best results.
- Use a fast storage device (SSD/NVMe) for meaningful I/O benchmarking.
- Consider the filesystem type (ext4, xfs, btrfs) as it affects journaling performance.
- PCP monitoring (--use_pcp) provides detailed I/O and CPU metrics during the test.
- For large table sizes, ensure sufficient disk space for all database files.

### Troubleshooting
- If the script fails to start, verify that sqlite3 is installed and in PATH.
- If timing files are missing, check that `/bin/time` is available (the `time` package).
- If results seem inconsistent, run more iterations and check system I/O load during testing.
- Use --use_pcp to collect detailed performance counters for analysis.
- Check `sqlite_timeing_*` files for detailed timing and error information.

## References

- SQLite Official Site: https://www.sqlite.org/
- SQLite WAL Mode Documentation: https://www.sqlite.org/wal.html
- test_tools Framework: https://github.com/redhat-performance/test_tools-wrappers
