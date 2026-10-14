# Metrics Design, Alerting and SLOs

What to measure and when to wake someone up. The SKILL.md "Alerting and
SLOs" section states the rules; this file has the queries.

## What to measure

- **Request-driven services — RED:** request **R**ate, **E**rrors,
  **D**uration, per route pattern and status class.
- **Resources (pools, queues, workers) — USE:** **U**tilization,
  **S**aturation (queue depth, wait time), **E**rrors.
- **Go runtime:** goroutine count, GC pause and CPU fraction, heap in use —
  from the Prometheus Go collector or OpenTelemetry runtime metrics.

## Histogram, not Summary

A Summary computes quantiles inside each process, and quantiles cannot be
averaged across instances. A Histogram exports buckets, which sum across
instances and are turned into quantiles at query time:

```promql
histogram_quantile(0.99,
  sum by (le, route) (rate(http_request_duration_seconds_bucket[5m])))
```

Put bucket boundaries around the SLO threshold (if the target is 300 ms,
have buckets at 250 ms and 300 ms), not just the defaults.

## SLO burn-rate alerts

With a 99.9% availability SLO the error budget is 0.1% of requests. Alert
on how fast the budget is burning, over a long and a short window
together, so a real incident pages fast and a blip does not:

```promql
# Page: burning 14.4x budget — 2% of a 30-day budget in 1 hour
(
  sum(rate(http_requests_total{status=~"5.."}[1h]))
    / sum(rate(http_requests_total[1h]))
) > (14.4 * 0.001)
and
(
  sum(rate(http_requests_total{status=~"5.."}[5m]))
    / sum(rate(http_requests_total[5m]))
) > (14.4 * 0.001)
```

A second, slower pair (6x over 6h and 30m) opens a ticket instead of a
page.

## Alert hygiene

- Alert on symptoms users feel (errors, latency, saturation), not causes
  (CPU at 80%) — causes go on dashboards.
- `rate()`, not `irate()`, in alerts — `irate` uses only the last two
  samples and flaps.
- Use `for:` on threshold alerts that are not already windowed.
- A series that stops existing does not fire a threshold alert; use
  `absent()` for metrics that must always be present.
- Every paging alert links a runbook.

## Exemplars

Attach the current trace ID when observing a latency histogram, so a
dashboard can jump from a p99 spike to one slow trace:

```go
obs := requestDuration.WithLabelValues(r.Method, route, status)
if eo, ok := obs.(prometheus.ExemplarObserver); ok {
    eo.ObserveWithExemplar(d.Seconds(), prometheus.Labels{"trace_id": traceID})
} else {
    obs.Observe(d.Seconds())
}
```

Exemplars need the OpenMetrics exposition format enabled on the handler
(`promhttp.HandlerOpts{EnableOpenMetrics: true}`).
