# Aim of the work

We want to develop two plugins for the [MADS framework](https://github.com/pbosetti/mads), also illustrated [here](https://mads-net.github.io/guides) and, specifically, [here](https://mads-net.github.io/guides/plugins.html).

One plugin implements a source agent that reads data from a serial-port connected measurement device and publishes them to the network of agents in JSON format.

The second plugin implements a filter agent that reads the data published by the source, calculates running statistics, and publishes the results.

# Assumptions

* We work in C++17 using CMake.
* Use CamelCase for class names, snake_case for variables and methods, `_snake_case` with leading `_` for member variables.
* Put private members at the end of class definitions.
* Use LLVM style formatting.
* Put sources and headers in the `src` folder.
* Document results in the `README.md` file.
* Assume that the MADS framework is installed under the prefix directory returned by the command `mads -p`, but remember that MADS plugins do not need the framework nor its headers in order to compile.

# General implementation rules

* Do not add or fetch third-party libraries without explicit approval.
* The only non-standard library already available for this work is `nlohmann/json`, as provided by the existing build system.
* For serial-port access, use the `SerialPort` class provided by the fetched `plugin` library in `serialport.hpp`.
* Keep all test code inside the stub `main()` already present at the end of each source file.
* Tests must be self-checking:
  * use assertions or equivalent explicit checks;
  * print enough context to diagnose failures;
  * return a non-zero exit status on failure.

# Testing

For each target, the stub `main()` at the end of the source file must be turned into a meaningful unit-style test driver.

The test executable must validate behavior deterministically. Random behavior is acceptable in production mode where explicitly requested below, but tests must not rely on randomness.

# The `serial` target

## Purpose

The agent connects to a serial port in `SerialPlugin::set_params()` and publishes received data to the MADS network through `SerialPlugin::get_output()` using a polling scheme.

Each successful call to `get_output()` publishes exactly one decoded frame.

If a read operation obtains more than one complete frame, the plugin must publish the first complete frame and keep the remaining complete frames internally queued for subsequent calls to `get_output()`.

## Input frame format

Serial-port frames follow this grammar:

```text
^<0-2047 unsigned integer>[,[0-2047 unsigned integer]]$
```

That is:

* a frame starts with `^`;
* contains one or more unsigned integer values;
* values are separated by commas;
* each value must be in the inclusive range `[0, 2047]`;
* a frame ends with `$`.

Whitespace is not part of the format and should be treated as invalid payload.

## Output JSON format

Each valid frame must be published as:

```json
{
  "data": [v1, v2, v3]
}
```

No additional fields are required beyond whatever the base plugin infrastructure may already add, such as `agent_id`.

## Parameters

The plugin must support the following JSON/INI parameter names:

* `address`: serial port name on Windows or serial device path on Unix. Default: empty string.
* `baud_rate`: serial line speed. Default: `115200`.

These names are part of the external interface and must be documented in `README.md`.

## Behavior when `address` is empty

If `address` is empty, the plugin does not open a physical serial port and instead generates deterministic test frames.

This mode exists to support unit testing and local demonstration without hardware.

In this mode, the implementation must allow the test `main()` to feed a deterministic sequence of raw serial chunks into the parser without depending on randomness.

Random data generation may still be used outside the tests, but the tests themselves must inject a fixed sequence and verify exact outputs.

## Partial and invalid input handling

The serial-port read may return partial data. The implementation must therefore keep an internal raw-buffer string.

Rules:

* If buffered data starts with bytes before the first `^`, discard bytes until the first `^`.
* If no terminating `$` is available yet for the current frame, keep the partial frame buffered and return `return_type::retry`.
* If a complete candidate frame exists but is malformed, discard that candidate frame and continue scanning buffered data for the next candidate frame.
* A malformed frame is one that:
  * does not match the grammar above;
  * contains an empty field;
  * contains a non-numeric field;
  * contains a value outside `[0, 2047]`.

## Return codes

For `SerialPlugin::get_output()`:

* return `return_type::success` when one valid frame is decoded and written to `out`;
* return `return_type::retry` when no valid complete frame is currently available;
* use `return_type::error` only for actual operational errors, such as failure to initialize the serial port when a non-empty `address` is requested.

The typo `return_value::retry` must be ignored; the correct enum name is `return_type::retry`.

## Libraries

The fetched `plugin` library already provides a `SerialPort` class in `serialport.hpp`. Use that.

Ask for approval before including or fetching any other libraries.

## Tests

The test driver in `src/serial.cpp` must exercise the parser in deterministic no-hardware mode.

It must provide raw serial chunks that collectively produce JSON objects and verify the following cases:

1. one frame containing a single value, starting with `^` and ending with `$`;
2. one frame containing 10 values, starting with `^` and ending with `$`;
3. one valid frame containing 4 values, preceded by an incomplete leading chunk and followed by an incomplete trailing chunk.

For case 3, use a chunk sequence that proves both behaviors:

* bytes before the first `^` are discarded;
* a trailing partial frame is buffered and not published until completed.

Each test must verify both the returned `return_type` and the exact JSON payload.

# The `stats` target

## Purpose

The agent receives in `FilterPlugin::load_data()` the JSON produced by the `serial` agent. It must then calculate mean and standard deviation running statistics over a scalar stream built from the incoming `data` arrays.

The input stream is the flattened sequence of numeric values received over time. For example:

```json
{"data":[1,2]}
{"data":[3]}
{"data":[4,5]}
```

must be treated as the scalar stream:

```text
1, 2, 3, 4, 5
```

## Accepted input schema

`load_data()` expects a JSON object with a `data` field containing an array of numeric values.

Example:

```json
{
  "data": [10, 12, 15]
}
```

If the loaded data lacks a `data` field, return `return_type::error`.

If `data` exists but is not an array of numbers, also return `return_type::error`.

## Parameters

The plugin must support the following JSON/INI parameter names:

* `window`: running-window width in number of scalar values. Default: `100`.
* `stride`: number of newly loaded scalar values required before the next successful `load_data()`. Default: `window / 2`, rounded down, but never less than `1`.

These names are part of the external interface and must be documented in `README.md`.

## Buffering and stride behavior

`FilterPlugin::load_data()` must append incoming scalar values to an internal buffer.

The method returns:

* `return_type::retry` until at least `stride` new scalar values have been appended since the last time `load_data()` returned `success`;
* `return_type::success` once `stride` new scalar values have accumulated since the previous success.

The first successful return therefore happens after `stride` loaded values, not after `window` loaded values.

## Running-window behavior

`process()` must compute statistics over the most recent `min(total_buffered_values, window)` scalar values available at the moment it is called.

This means partial windows are allowed before the buffer reaches full width.

After `process()` is called following a successful `load_data()`, the plugin keeps enough buffered history to support future overlapping windows, up to `window` values.

## Output JSON format

`process()` must publish:

```json
{
  "count": N,
  "mean": M,
  "stddev": S
}
```

where:

* `count` is the number of scalar values used for the current window;
* `mean` is the arithmetic mean of those values;
* `stddev` is the population standard deviation over those same values.

Use population standard deviation, that is:

```text
sqrt(sum((x - mean)^2) / N)
```

Do not use the sample correction `N - 1`.

## Return codes

For `FilterPlugin::load_data()`:

* return `return_type::success` when the stride condition is met;
* return `return_type::retry` when more input is needed;
* return `return_type::error` on schema errors.

For `FilterPlugin::process()`:

* return `return_type::success` when statistics are written to `out`;
* return `return_type::retry` only if called without any buffered values available;
* return `return_type::error` only for unexpected internal errors.

## Libraries

Ask for approval before including or fetching any other libraries.

## Tests

Set `window = 4` and `stride = 2`.

Load one frame at a time using valid input objects of the form:

```json
{
  "data": [value]
}
```

Use a deterministic sequence of 10 scalar values.

Expected behavior:

1. the first valid `load_data()` return is `success` after 2 values have been loaded;
2. the next valid `load_data()` return is `success` after 2 more values have been loaded;
3. continue in the same way through all 10 values;
4. call `process()` only after a successful `load_data()`.

The test must verify exact numeric results for each produced window:

* after values `1, 2`: `count = 2`, `mean = 1.5`, `stddev = 0.5`;
* after values `1, 2, 3, 4`: `count = 4`, `mean = 2.5`, `stddev = sqrt(1.25)`;
* after values `3, 4, 5, 6`: `count = 4`, `mean = 4.5`, `stddev = sqrt(1.25)`;
* after values `5, 6, 7, 8`: `count = 4`, `mean = 6.5`, `stddev = sqrt(1.25)`;
* after values `7, 8, 9, 10`: `count = 4`, `mean = 8.5`, `stddev = sqrt(1.25)`.

The test must also verify that `load_data()` returns `return_type::error` when the input JSON lacks the `data` field.

# CTest

Also adda CMake CTest target.