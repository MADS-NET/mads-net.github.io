#ifndef TEST_HELPERS_HPP
#define TEST_HELPERS_HPP

#include <cmath>
#include <iostream>
#include <string>

#include <nlohmann/json.hpp>

#include <common.hpp>

using nlohmann::json;
using std::cerr;
using std::endl;
using std::size_t;
using std::string;
using std::to_string;

/*!
 * @brief Utilities used by the executable self-tests for both plugins.
 */
namespace test_helpers {

/*!
 * @brief Assert that a boolean condition is true.
 * @param condition Condition to evaluate.
 * @param message Failure message emitted when the condition is false.
 * @return `true` when the condition holds, otherwise `false`.
 */
inline bool check(bool condition, const string &message) {
  if (!condition) {
    cerr << "FAIL: " << message << endl;
    return false;
  }
  return true;
}

/*!
 * @brief Compare two plugin API return codes.
 * @param actual Value produced by the code under test.
 * @param expected Expected return value.
 * @param label Context label shown on failure.
 * @return `true` when the return codes match, otherwise `false`.
 */
inline bool check_equal(return_type actual, return_type expected,
                        const string &label) {
  if (actual != expected) {
    cerr << "FAIL: " << label << " expected return "
         << static_cast<int>(expected) << " got " << static_cast<int>(actual)
         << endl;
    return false;
  }
  return true;
}

/*!
 * @brief Compare two JSON values for exact equality.
 * @param actual Value produced by the code under test.
 * @param expected Expected JSON value.
 * @param label Context label shown on failure.
 * @return `true` when the values match, otherwise `false`.
 */
inline bool check_json(const json &actual, const json &expected,
                       const string &label) {
  if (actual != expected) {
    cerr << "FAIL: " << label << " expected " << expected.dump()
         << " got " << actual.dump() << endl;
    return false;
  }
  return true;
}

/*!
 * @brief Compare two floating-point values within a tolerance.
 * @param actual Value produced by the code under test.
 * @param expected Expected floating-point value.
 * @param label Context label shown on failure.
 * @param tolerance Maximum accepted absolute difference.
 * @return `true` when the values are close enough, otherwise `false`.
 */
inline bool check_close(double actual, double expected, const string &label,
                        double tolerance = 1e-9) {
  if (std::fabs(actual - expected) > tolerance) {
    cerr << "FAIL: " << label << " expected " << expected << " got " << actual
         << endl;
    return false;
  }
  return true;
}

/*!
 * @brief Validate the schema and numeric content of a stats output JSON object.
 * @param output JSON object produced by the stats plugin.
 * @param expected_count Expected sample count.
 * @param expected_mean Expected arithmetic mean.
 * @param expected_stddev Expected population standard deviation.
 * @param label Context label shown on failure.
 * @return `true` when all fields match expectation, otherwise `false`.
 */
inline bool check_output(const json &output, size_t expected_count,
                         double expected_mean, double expected_stddev,
                         const string &label) {
  if (!check(output.contains("count"), label + " missing count")) {
    return false;
  }
  if (!check(output.contains("mean"), label + " missing mean")) {
    return false;
  }
  if (!check(output.contains("stddev"), label + " missing stddev")) {
    return false;
  }

  return check(output["count"].get<size_t>() == expected_count,
               label + " count mismatch") &&
         check_close(output["mean"].get<double>(), expected_mean,
                     label + " mean mismatch") &&
         check_close(output["stddev"].get<double>(), expected_stddev,
                     label + " stddev mismatch");
}

/*!
 * @brief Verify that the serial plugin decodes a single-value frame.
 * @tparam SerialPluginType Concrete serial plugin type under test.
 * @return `true` on success, otherwise `false`.
 */
template <typename SerialPluginType>
inline bool test_single_value_frame() {
  SerialPluginType plugin;
  plugin.set_params({{"address", ""}});
  plugin.push_test_chunk("^42$");

  json output;
  const return_type status = plugin.get_output(output);
  return check_equal(status, return_type::success, "single frame status") &&
         check_json(output, json{{"data", json::array({42})}},
                    "single frame payload");
}

/*!
 * @brief Verify that the serial plugin decodes a 10-value frame.
 * @tparam SerialPluginType Concrete serial plugin type under test.
 * @return `true` on success, otherwise `false`.
 */
template <typename SerialPluginType>
inline bool test_ten_value_frame() {
  SerialPluginType plugin;
  plugin.set_params({{"address", ""}});
  plugin.push_test_chunk("^0,1,2,3,4,5,6,7,8,9$");

  json output;
  const return_type status = plugin.get_output(output);
  return check_equal(status, return_type::success, "ten-value status") &&
         check_json(output,
                    json{{"data", json::array({0, 1, 2, 3, 4, 5, 6, 7, 8, 9})}},
                    "ten-value payload");
}

/*!
 * @brief Verify junk skipping, partial-frame buffering, and delayed completion.
 * @tparam SerialPluginType Concrete serial plugin type under test.
 * @return `true` on success, otherwise `false`.
 */
template <typename SerialPluginType>
inline bool test_partial_and_junk_handling() {
  SerialPluginType plugin;
  plugin.set_params({{"address", ""}});
  plugin.push_test_chunk("junk-without-start");
  plugin.push_test_chunk("^10,20");
  plugin.push_test_chunk(",30,40$^99");

  json output;

  if (!check_equal(plugin.get_output(output), return_type::retry,
                   "junk-only chunk status")) {
    return false;
  }

  if (!check_equal(plugin.get_output(output), return_type::retry,
                   "leading partial chunk status")) {
    return false;
  }

  if (!check_equal(plugin.get_output(output), return_type::success,
                   "completed four-value frame status")) {
    return false;
  }

  if (!check_json(output, json{{"data", json::array({10, 20, 30, 40})}},
                  "completed four-value payload")) {
    return false;
  }

  if (!check_equal(plugin.get_output(output), return_type::retry,
                   "trailing partial frame status")) {
    return false;
  }

  plugin.push_test_chunk(",100$");

  if (!check_equal(plugin.get_output(output), return_type::success,
                   "completed trailing frame status")) {
    return false;
  }

  return check_json(output, json{{"data", json::array({99, 100})}},
                    "completed trailing frame payload");
}

/*!
 * @brief Execute the full serial plugin self-test suite.
 * @tparam SerialPluginType Concrete serial plugin type under test.
 * @return `true` when every serial test passes, otherwise `false`.
 */
template <typename SerialPluginType>
inline bool run_serial_tests() {
  return test_single_value_frame<SerialPluginType>() &&
         test_ten_value_frame<SerialPluginType>() &&
         test_partial_and_junk_handling<SerialPluginType>();
}

/*!
 * @brief Verify stride-triggered processing and sliding-window statistics.
 * @tparam StatsPluginType Concrete stats plugin type under test.
 * @return `true` on success, otherwise `false`.
 */
template <typename StatsPluginType>
inline bool test_stats_stride_and_window() {
  StatsPluginType plugin;
  plugin.set_params({{"window", 4}, {"stride", 2}});

  const double expected_stddev = std::sqrt(1.25);
  const struct ExpectedWindow {
    size_t count;
    double mean;
    double stddev;
  } expectations[] = {
      {2u, 1.5, 0.5},
      {4u, 2.5, expected_stddev},
      {4u, 4.5, expected_stddev},
      {4u, 6.5, expected_stddev},
      {4u, 8.5, expected_stddev},
  };

  size_t emitted = 0;
  for (int value = 1; value <= 10; ++value) {
    json input{{"data", json::array({value})}};
    const return_type status = plugin.load_data(input);
    const return_type expected_status =
        (value % 2 == 0) ? return_type::success : return_type::retry;
    if (!check_equal(status, expected_status,
                     "load_data status for value " + to_string(value))) {
      return false;
    }

    if (status == return_type::success) {
      json output;
      if (!check_equal(plugin.process(output), return_type::success,
                       "process status for value " + to_string(value))) {
        return false;
      }
      if (!check_output(output, expectations[emitted].count,
                        expectations[emitted].mean,
                        expectations[emitted].stddev,
                        "window #" + to_string(emitted + 1))) {
        return false;
      }
      ++emitted;
    }
  }

  return check(emitted == 5u, "expected five output windows");
}

/*!
 * @brief Verify that missing `data` input is reported as an error.
 * @tparam StatsPluginType Concrete stats plugin type under test.
 * @return `true` on success, otherwise `false`.
 */
template <typename StatsPluginType>
inline bool test_missing_data_error() {
  StatsPluginType plugin;
  plugin.set_params({{"window", 4}, {"stride", 2}});
  return check_equal(plugin.load_data(json{{"wrong", json::array({1})}}),
                     return_type::error, "missing data field error");
}

/*!
 * @brief Execute the full stats plugin self-test suite.
 * @tparam StatsPluginType Concrete stats plugin type under test.
 * @return `true` when every stats test passes, otherwise `false`.
 */
template <typename StatsPluginType>
inline bool run_stats_tests() {
  return test_stats_stride_and_window<StatsPluginType>() &&
         test_missing_data_error<StatsPluginType>();
}

} // namespace test_helpers

#endif
