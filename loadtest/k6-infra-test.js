// k6 infrastructure load test
// Validates that deployed AKS infrastructure can handle expected traffic
// Usage: k6 run --env TARGET_URL=https://<endpoint> loadtest/k6-infra-test.js

import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";

const errorRate = new Rate("errors");
const latency = new Trend("request_latency");

// Ramp-up load profile to stress-test infrastructure capacity
export const options = {
  stages: [
    { duration: "30s", target: 10 },   // warm-up
    { duration: "1m",  target: 50 },   // ramp to moderate load
    { duration: "2m",  target: 100 },  // sustained load
    { duration: "1m",  target: 200 },  // peak load
    { duration: "30s", target: 0 },    // cool-down
  ],
  thresholds: {
    http_req_duration: ["p(95)<2000"],  // 95th percentile < 2s
    http_req_failed:   ["rate<0.05"],   // error rate < 5%
    errors:            ["rate<0.05"],
  },
};

const TARGET_URL = __ENV.TARGET_URL || "http://localhost";

export default function () {
  // Health endpoint check
  const healthRes = http.get(`${TARGET_URL}/healthz`, {
    tags: { name: "health_check" },
    timeout: "10s",
  });
  check(healthRes, {
    "health status 200": (r) => r.status === 200,
    "health response < 500ms": (r) => r.timings.duration < 500,
  });
  errorRate.add(healthRes.status !== 200);
  latency.add(healthRes.timings.duration);

  // Root endpoint load test
  const rootRes = http.get(`${TARGET_URL}/`, {
    tags: { name: "root" },
    timeout: "10s",
  });
  check(rootRes, {
    "root status < 500": (r) => r.status < 500,
    "root response < 2s": (r) => r.timings.duration < 2000,
  });
  errorRate.add(rootRes.status >= 500);
  latency.add(rootRes.timings.duration);

  // Simulate realistic user pacing
  sleep(1);
}

export function handleSummary(data) {
  const passed = data.metrics.http_req_failed.values.rate < 0.05 &&
                 data.metrics.http_req_duration.values["p(95)"] < 2000;

  const summary = {
    total_requests: data.metrics.http_reqs.values.count,
    failed_requests: Math.round(data.metrics.http_req_failed.values.rate * data.metrics.http_reqs.values.count),
    p95_latency_ms: data.metrics.http_req_duration.values["p(95)"],
    p99_latency_ms: data.metrics.http_req_duration.values["p(99)"],
    median_latency_ms: data.metrics.http_req_duration.values.med,
    max_vus: data.metrics.vus_max.values.value,
    result: passed ? "PASS" : "FAIL",
  };

  return {
    stdout: JSON.stringify(summary, null, 2) + "\n",
    "loadtest/results.json": JSON.stringify(summary, null, 2),
  };
}
