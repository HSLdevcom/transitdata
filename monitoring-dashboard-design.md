# Transitdata Monitoring Dashboard Design

## 1. Goal

Enable the team to **quickly react to alerts and pinpoint problems**. Dashboards should be cohesive, comprehensive, and linked from alerts. We look at dashboards when alerts fire or to learn about the shape of our traffic -- not just when something is on fire.

## 2. Current State

### Existing Dashboards

| Dashboard | What it shows | Gaps |
|-----------|--------------|------|
| **Pulsar Overview** (`pulsar.json`) | `pulsar_rate_in` for 19 topics, `pulsar_subscription_msg_rate_out` for 3 topics, `pulsar_storage_size` for 2 topics | No data-flow ordering, incomplete rate_out coverage, incomplete storage_size coverage |
| **Pulsar built-in dashboards** | Suite of dashboards bundled with Pulsar: Overview, Topic Metrics, Broker Metrics, Bookie Metrics, JVM Metrics, Node Metrics, Messaging Metrics, Proxy Metrics, and others. Provide detailed per-topic drill-down (publish/delivery rate, throughput, backlog), broker health, JVM stats, etc. | Generic infrastructure dashboards -- not Transitdata-specific, require manual topic/component selection, no pipeline data-flow context |
| **GTFS-RT Feed Monitoring** (`gtfsrt-dashboard.json`) | Feed entity counts, timestamp age, scrape success/failure | No HTTP request duration, no request rate from consumers, no E2E latency |
| **MQTT Message Counts** (`mqtt-dashboard.json`) | Message rates per broker/topic-filter, connection status | Only covers external MQTT brokers, not Pulsar-side metrics |

### Existing Metrics (from transitdata-metrics-exporter)

| Metric | Type | Labels | Notes |
|--------|------|--------|-------|
| `gtfsrt_entity_count` | Histogram | `url` | Entity count per GTFS-RT feed |
| `gtfsrt_timestamp_age_seconds` | Histogram | `url` | Feed staleness |
| `gtfsrt_last_scrape_success` | Gauge | `url` | 1=OK, 0=failed |
| `gtfsrt_scrape_attempts_total` | Counter | `url`, `result` | Scrape outcomes |
| `mqtt_messages_received_total` | Counter | `broker`, `topic_filter`, `qos`, `is_duplicate`, `is_retained` | MQTT message rate |
| `mqtt_connected` | Gauge | `broker` | Connection status |
| `mqtt_connection_lost` | Counter | `broker` | Connection loss events |

### Existing Pulsar Metrics (from Pulsar's built-in Prometheus exporter)

Available in managed Prometheus via the Pulsar cluster:

| Metric | Description |
|--------|-------------|
| `pulsar_rate_in` | Messages/sec into topic |
| `pulsar_rate_out` | Messages/sec out of topic |
| `pulsar_subscription_msg_rate_out` | Messages/sec consumed per subscription |
| `pulsar_storage_size` | Topic storage size in bytes |
| `pulsar_msg_backlog` | Message backlog count per subscription |
| `pulsar_subscription_last_expire_timestamp` | Timestamp of last message expiry |
| `pulsar_subscription_oldest_msg_publish_time_ms` | Publish timestamp of oldest unacked message (if available) |

### Legacy Monitoring (to be replaced)

- `cronjob-pulsar-monitor-data-collector` -- pushes Pulsar stats to Azure custom metrics every minute
- `cronjob-gtfsrt-monitor-data-collector` -- pushes GTFS-RT stats to Azure custom metrics every minute
- `transitdata-mqtt-monitor-data-collector` -- pushes MQTT stats to Azure custom metrics

These currently power Azure-based alerting. The new Prometheus + Grafana stack should fully replace them.

### What's Missing

- **No alerting rules** in Prometheus/Grafana
- **No "golden signals" homepage** dashboard
- **No data-flow-ordered** view of the pipeline -- the built-in Pulsar Topic Metrics dashboard has backlog, rates, and throughput per topic, but it is a generic drill-down tool that requires manual topic selection. There is no Transitdata-specific dashboard that shows all key topics in data-flow order on a single page.
- **No error count** panels (logged errors by severity per microservice)
- **No GTFS-RT HTTP request rate/duration** from consumer perspective
- **No E2E latency** tracking (ptROI -> GTFS-RT, APC source -> finished APC)
- **No infrastructure panels** (pod ready/unready, CPU, memory, disk)
- **No database polling** metrics (latency, query errors, effective polling rate)
- Pulsar Overview dashboard doesn't cover all subscriptions for rate_out or storage_size (the built-in Topic Metrics dashboard does, but per-topic only)
- No dashboard-to-dashboard links or alert-to-dashboard links

---

## 3. Design Principles

1. **Golden Signals as homepage** -- a single dashboard gives the 10-second health check
2. **REDS** (Requests, Errors, Duration, Saturation) as primary organizing principle
3. **FLOW** (Failures, Lag, Output rate, Watermark staleness) as additive principle for the streaming pipeline
4. **Data-flow ordering** -- panels ordered top-to-bottom matching the direction of data flow: data sources first, then earliest Pulsar topics, then downstream processors, then output
5. **Alerts link to dashboards** -- every alert rule includes a `dashboard_url` + `panel_id` annotation
6. **Drill-down hierarchy** -- Golden Signals -> domain dashboard -> per-service detail

---

## 4. Dashboard Hierarchy

```
Golden Signals (homepage)
  |
  +-- Domain Flow Dashboards (one per domain, source -> sink ordering)
  |     +-- Arrival & Departure Time Predictions
  |     +-- Vehicle Positions
  |     +-- APC (Automatic Passenger Counting)
  |     +-- Cancellations & Service Alerts
  |     +-- EKE
  |
  +-- Pulsar Overview (existing custom dashboard)
  +-- Pulsar built-in dashboards (Topic Metrics, Broker Metrics, JVM, etc.)
  +-- GTFS-RT Overview (existing, extended)
  +-- MQTT Overview (existing, extended)
  +-- Databases (ptROI, DOI, OMM: connections, polling, query health)
  +-- Redis (cluster metrics, memory, connections)
  +-- Infrastructure (pods, CPU, memory, disk)
```

**Domain flow dashboards** show all component types in a given flow (databases, MQTT brokers, Redis, Java services, Pulsar topics), ordered from sources at the top to sinks at the bottom. Some components participate in multiple flows and may appear on more than one dashboard. From a domain flow dashboard, each component links to the relevant specialized technical dashboard for deeper drill-down (e.g., a Pulsar topic links to Pulsar Topic Metrics, a database links to the Databases dashboard, Redis links to the Redis dashboard).

**Specialized dashboards** (Pulsar Overview, GTFS-RT Overview, MQTT Overview, Databases, Redis, Infrastructure) provide cross-cutting technical views across all domains. They exist at the same level as the domain flow dashboards -- you can reach them directly from the Golden Signals homepage or from within a domain flow dashboard.

---

## 5. Dashboard Specifications

### 5.1 Golden Signals Dashboard (homepage)

**Purpose:** At-a-glance health of the entire Transitdata pipeline. This is the first dashboard you open when an alert fires.

**Layout:** 4 row sections, one per golden signal.

#### Row 1: Requests / Output Rate (R + O from REDS/FLOW)

| Panel | Type | Query | Notes |
|-------|------|-------|-------|
| **GTFS-RT API request rate** | Timeseries | `sum(rate(gtfsrt_scrape_attempts_total{result="success"}[$__rate_interval])) by (url)` | Polling rate as proxy for consumer requests |
| **GTFS-RT entity count** (all feeds) | Stat | `sum by (url) (rate(gtfsrt_entity_count_sum[$__rate_interval]) / rate(gtfsrt_entity_count_count[$__rate_interval]))` | Current avg entities per feed |
| **Pipeline output rate** | Timeseries | `sum(pulsar_rate_in{topic=~".*feedmessage-vehicleposition\|.*feedmessage-tripupdate"}) by (topic)` | Rate into final GTFS-RT Pulsar topics |
| **MQTT source message rate** | Timeseries | `sum(rate(mqtt_messages_received_total[$__rate_interval])) by (broker)` | Input from external sources |

#### Row 2: Errors / Failures (E + F)

| Panel | Type | Query | Notes |
|-------|------|-------|-------|
| **GTFS-RT feed status** | Stat (red/green) | `sum by (url) (gtfsrt_last_scrape_success)` | Quick pass/fail per feed |
| **GTFS-RT scrape errors** | Timeseries | `sum(rate(gtfsrt_scrape_attempts_total{result!="success"}[$__rate_interval])) by (url, result)` | Error rates by type |
| **MQTT broker connectivity** | Stat (red/green) | `sum by (broker) (mqtt_connected)` | Connected/Disconnected per broker |
| **Pod restarts** | Timeseries | `sum(increase(kube_pod_container_status_restarts_total{namespace="$k8s_namespace"}[$__rate_interval])) by (pod)` | Crash loops |
| **Logged errors** | Timeseries | *Requires new metric (see section 6)* | Error count by severity per microservice |

#### Row 3: Duration / Lag (D + L)

| Panel | Type | Query | Notes |
|-------|------|-------|-------|
| **GTFS-RT feed age** | Timeseries | `sum by (url) (rate(gtfsrt_timestamp_age_seconds_sum[$__rate_interval]) / rate(gtfsrt_timestamp_age_seconds_count[$__rate_interval]))` | How stale each feed is |
| **E2E latency: ptROI -> GTFS-RT Trip Updates** | Timeseries | *Requires new metric (see section 6)* | End-to-end prediction latency |
| **E2E latency: APC source -> finished APC** | Timeseries | *Requires new metric (see section 6)* | End-to-end APC latency |
| **DB polling latency** | Timeseries | *Requires new metric (see section 6)* | ptROI/ptDOI/OMM query duration |
| **Pulsar oldest unacked age (top-N)** | Timeseries | `time() * 1000 - pulsar_subscription_oldest_msg_publish_time_ms{cluster=~"$cluster", namespace=~"$namespace"}` | Watermark staleness (consumer lag in time) |

#### Row 4: Saturation (S)

| Panel | Type | Query | Notes |
|-------|------|-------|-------|
| **Pods ready / not ready** | Stat | `sum(kube_pod_status_ready{namespace="$k8s_namespace", condition="true"})` vs `sum(kube_pod_status_ready{namespace="$k8s_namespace", condition="false"})` | Pod health |
| **CPU usage** | Timeseries | `sum(rate(container_cpu_usage_seconds_total{namespace="$k8s_namespace"}[$__rate_interval])) by (pod)` | Top-N pods by CPU |
| **Memory usage** | Timeseries | `container_memory_working_set_bytes{namespace="$k8s_namespace"} / container_spec_memory_limit_bytes{namespace="$k8s_namespace"}` | Memory utilization % |
| **Pulsar backlog (top-N)** | Timeseries | `topk(10, pulsar_msg_backlog{cluster=~"$cluster", namespace=~"$namespace"})` | Biggest backlogs |
| **Pulsar storage size** | Timeseries | `sum(pulsar_storage_size{cluster=~"$cluster", namespace=~"$namespace"}) by (topic)` | Disk pressure |

---

### 5.2 Domain Flow Dashboards

Each domain flow dashboard follows the same structure:
- **Ordering:** Sources at the top, sinks at the bottom
- **All component types shown:** databases, MQTT brokers, Redis caches, Java microservices, Pulsar topics
- **Pulsar topic panels** link to the built-in **Pulsar Topic Metrics** dashboard for per-topic drill-down
- Components shared between flows may appear on multiple dashboards

#### Standard panel types per component kind:

| Component Kind | Panels |
|---------------|--------|
| **MQTT broker** | Connection status (`mqtt_connected`), message rate (`rate(mqtt_messages_received_total)`), connection losses |
| **Database** | Polling rate, poll latency, query errors, rows returned *(new metrics -- see section 6)* |
| **Redis** | Connection status, memory usage, key count *(from Redis exporter or kube metrics)* |
| **Java microservice** | Pod ready/restart status, CPU, memory, logged errors *(new metric -- see section 6)* |
| **Pulsar topic** | Message rate in (`pulsar_rate_in`), backlog per subscription (`pulsar_msg_backlog`), storage size (`pulsar_storage_size`) |

---

#### 5.2.1 Arrival & Departure Time Predictions

**Scope:** From database polling and metro ATS ingestion through to GTFS-RT Trip Update output.

```
Sources
  ptROI DB ──> transitdata-pubtrans-arrival-source ──> source-pt-roi/arrival
  ptROI DB ──> transitdata-pubtrans-departure-source ──> source-pt-roi/departure
  Metro MQTT (hsl-mqtt-lab-a) ──> transitdata-metro-ats-mqtt-pulsar-gateway
    ──> metro-ats-mqtt-raw/metro-estimate
    ──> transitdata-metro-ats-mqtt-deduplicator
    ──> metro-ats-mqtt-raw-deduplicated/metro-estimate
    ──> transitdata-metro-ats-parser
    ──> source-metro-ats/metro-estimate

Processing
  transitdata-pubtrans-stop-estimates ──> internal-messages/pubtrans-stop-estimate
  transitdata-metro-estimate-stop-estimates (+ Redis metro cache)
  transitdata-cache-bootstrapper (+ Redis)

Output
  transitdata-tripupdate-processor ──> internal-messages/feedmessage-tripupdate
  transitdata-stop-cancellation-processor ──> gtfs-rt/feedmessage-tripupdate
  transitdata-tripupdate-full-dataset ──> HTTP API
  transitdata-mqtt-gateway-tripupdate ──> prod MQTT broker
```

**Dashboard rows (top to bottom):**

| Row | Component | Type | Key metrics |
|-----|-----------|------|-------------|
| 1 | ptROI DB | Database | Poll latency, query errors, polling rate *(new)* |
| 2 | transitdata-pubtrans-arrival-source | Service | Pod status, CPU, memory |
| 3 | transitdata-pubtrans-departure-source | Service | Pod status, CPU, memory |
| 4 | `source-pt-roi/arrival` | Pulsar topic | rate_in, backlog, storage |
| 5 | `source-pt-roi/departure` | Pulsar topic | rate_in, backlog, storage |
| 6 | Metro MQTT broker (`hsl-mqtt-lab-a`) | MQTT | `mqtt_connected`, message rate |
| 7 | transitdata-metro-ats-mqtt-pulsar-gateway | Service | Pod status |
| 8 | `metro-ats-mqtt-raw/metro-estimate` | Pulsar topic | rate_in, backlog, storage |
| 9 | transitdata-metro-ats-mqtt-deduplicator | Service | Pod status |
| 10 | `metro-ats-mqtt-raw-deduplicated/metro-estimate` | Pulsar topic | rate_in, backlog, storage |
| 11 | transitdata-metro-ats-parser | Service | Pod status |
| 12 | `source-metro-ats/metro-estimate` | Pulsar topic | rate_in, backlog, storage |
| 13 | Redis (metro) + Redis (main) | Redis | Connection, memory |
| 14 | transitdata-pubtrans-stop-estimates | Service | Pod status, CPU, memory |
| 15 | transitdata-metro-estimate-stop-estimates | Service | Pod status |
| 16 | `internal-messages/pubtrans-stop-estimate` | Pulsar topic | rate_in, backlog, storage |
| 17 | transitdata-tripupdate-processor | Service | Pod status, CPU, memory |
| 18 | `internal-messages/feedmessage-tripupdate` | Pulsar topic | rate_in, backlog, storage |
| 19 | transitdata-stop-cancellation-processor | Service | Pod status *(shared with Cancellations flow)* |
| 20 | `gtfs-rt/feedmessage-tripupdate` | Pulsar topic | rate_in, rate_out, backlog, storage |
| 21 | transitdata-tripupdate-full-dataset | Service | Pod status |
| 22 | transitdata-mqtt-gateway-tripupdate | Service | Pod status |

---

#### 5.2.2 Vehicle Positions

**Scope:** From HFP MQTT ingestion (including ferries) through to GTFS-RT Vehicle Position output.

```
Sources
  HFP MQTT (hfprec938, hfprec939) ──> transitdata-hfp-mqtt-pulsar-gateway-1/2
    ──> hfp-mqtt-raw/v2
  Ferry sources (suomenlinna-ferry-hfp, matkahuolto-hfp) ──> HFP MQTT

Processing
  transitdata-hfp-mqtt-deduplicator ──> hfp-mqtt-raw-deduplicated/v2
  transitdata-hfp-parser ──> hfp/v2
  transitdata-vehicleposition-processor ──> gtfs-rt/feedmessage-vehicleposition

Output
  transitdata-vehicleposition-full-dataset ──> HTTP API
  transitdata-mqtt-gateway-vehicleposition ──> prod MQTT broker
```

**Dashboard rows (top to bottom):**

| Row | Component | Type | Key metrics |
|-----|-----------|------|-------------|
| 1 | HFP MQTT brokers (`hfprec938`, `hfprec939`) | MQTT | `mqtt_connected`, message rate (`/hfp/v2/journey/ongoing/#`) |
| 2 | `mqtt.hsl.fi` (ferries) | MQTT | `mqtt_connected`, message rate |
| 3 | suomenlinna-ferry-hfp, matkahuolto-hfp | Service | Pod status |
| 4 | transitdata-hfp-mqtt-pulsar-gateway-1/2 | Service | Pod status |
| 5 | `hfp-mqtt-raw/v2` | Pulsar topic | rate_in, backlog, storage |
| 6 | transitdata-hfp-mqtt-deduplicator | Service | Pod status |
| 7 | `hfp-mqtt-raw-deduplicated/v2` | Pulsar topic | rate_in, backlog, storage |
| 8 | transitdata-hfp-parser | Service | Pod status, CPU, memory |
| 9 | `hfp/v2` | Pulsar topic | rate_in, backlog, storage |
| 10 | transitdata-vehicleposition-processor | Service | Pod status, CPU, memory |
| 11 | `gtfs-rt/feedmessage-vehicleposition` | Pulsar topic | rate_in, rate_out, backlog, storage |
| 12 | transitdata-vehicleposition-full-dataset | Service | Pod status |
| 13 | transitdata-mqtt-gateway-vehicleposition | Service | Pod status |

---

#### 5.2.3 APC (Automatic Passenger Counting)

**Scope:** From APC MQTT ingestion through full APC and partial APC paths to expanded APC output.

```
Sources
  APC MQTT (apc.rt.hsl.fi)
    ──> transitdata-apc-mqtt-pulsar-gateway-1/2 ──> hfp-mqtt-raw/apc
    ──> transitdata-partial-apc-mqtt-pulsar-gateway-1/2 ──> hfp-mqtt-raw/partial-apc

Full APC path
  transitdata-apc-mqtt-deduplicator ──> hfp-mqtt-raw-deduplicated/apc
  transitdata-apc-parser ──> hfp/passenger-count

Partial APC path
  transitdata-partial-apc-mqtt-deduplicator ──> hfp-mqtt-raw-deduplicated/partial-apc
  transitdata-partial-apc-pbf-json-transformer
  transitdata-partial-apc-expander-combiner
    ──> hfp/expanded-apc
    ──> hfp/expanded-apc-mqtt-backfeed

Output
  transitdata-expanded-apc-mqtt-pulsar-gateway-1 ──> APC MQTT broker (backfeed)
  transitdata-partial-apc-pulsar-mqtt-gateway ──> MQTT
```

**Dashboard rows (top to bottom):**

| Row | Component | Type | Key metrics |
|-----|-----------|------|-------------|
| 1 | APC MQTT broker (`apc.rt.hsl.fi`) | MQTT | `mqtt_connected`, message rate (`/hfp/v2/journey/ongoing/apc/#`, `apc-partial/#`) |
| 2 | transitdata-apc-mqtt-pulsar-gateway-1/2 | Service | Pod status |
| 3 | transitdata-partial-apc-mqtt-pulsar-gateway-1/2 | Service | Pod status |
| 4 | `hfp-mqtt-raw/apc` | Pulsar topic | rate_in, backlog, storage |
| 5 | `hfp-mqtt-raw/partial-apc` | Pulsar topic | rate_in, backlog, storage |
| 6 | transitdata-apc-mqtt-deduplicator | Service | Pod status |
| 7 | transitdata-partial-apc-mqtt-deduplicator | Service | Pod status |
| 8 | `hfp-mqtt-raw-deduplicated/apc` | Pulsar topic | rate_in, backlog, storage |
| 9 | `hfp-mqtt-raw-deduplicated/partial-apc` | Pulsar topic | rate_in, backlog, storage |
| 10 | transitdata-apc-parser | Service | Pod status |
| 11 | `hfp/passenger-count` | Pulsar topic | rate_in, rate_out, backlog, storage |
| 12 | transitdata-partial-apc-pbf-json-transformer | Service | Pod status |
| 13 | transitdata-partial-apc-expander-combiner | Service | Pod status, CPU, memory |
| 14 | `hfp/expanded-apc` | Pulsar topic | rate_in, backlog, storage |
| 15 | `hfp/expanded-apc-mqtt-backfeed` | Pulsar topic | rate_in, backlog, storage |
| 16 | transitdata-expanded-apc-mqtt-pulsar-gateway-1 | Service | Pod status |
| 17 | transitdata-partial-apc-pulsar-mqtt-gateway | Service | Pod status |

---

#### 5.2.4 Cancellations & Service Alerts

**Scope:** From OMM DB and stop cancellation sources through to cancellation processing and service alert output.

```
Cancellation sources
  OMM DB ──> transitdata-omm-cancellation-source
  transitdata-metro-ats-cancellation-source
  transitdata-stop-cancellation-source ──> internal-messages/stop-cancellation
  transitdata-cancellation-processor

Stop cancellation processing
  transitdata-stop-cancellation-processor
    (reads internal-messages/feedmessage-tripupdate + internal-messages/stop-cancellation)
    ──> gtfs-rt/feedmessage-tripupdate

Service alerts
  OMM DB ──> transitdata-omm-alert-source
  transitdata-alert-processor
  transitdata-servicealert-full-dataset ──> HTTP API
  transitdata-mqtt-gateway-servicealert ──> prod MQTT broker
```

**Dashboard rows (top to bottom):**

| Row | Component | Type | Key metrics |
|-----|-----------|------|-------------|
| 1 | OMM DB | Database | Poll latency, query errors, polling rate *(new)* |
| 2 | transitdata-omm-cancellation-source | Service | Pod status |
| 3 | transitdata-metro-ats-cancellation-source | Service | Pod status |
| 4 | transitdata-stop-cancellation-source | Service | Pod status |
| 5 | transitdata-cancellation-processor | Service | Pod status |
| 6 | `internal-messages/stop-cancellation` | Pulsar topic | rate_in, backlog, storage |
| 7 | transitdata-stop-cancellation-processor | Service | Pod status |
| 8 | `gtfs-rt/feedmessage-tripupdate` | Pulsar topic | rate_in, rate_out, backlog, storage *(shared with Predictions flow)* |
| 9 | transitdata-omm-alert-source | Service | Pod status |
| 10 | transitdata-alert-processor | Service | Pod status |
| 11 | Service alert Pulsar topics | Pulsar topic | rate_in, backlog, storage *(confirm topic names from cluster)* |
| 12 | transitdata-servicealert-full-dataset | Service | Pod status |
| 13 | transitdata-mqtt-gateway-servicealert | Service | Pod status |

> **Note:** Exact Pulsar topic names for cancellation and service alert internal topics need to be confirmed from the cluster. The architecture description mentions these flows but the topics are not all present in the current Pulsar Overview dashboard.

---

#### 5.2.5 EKE

**Scope:** From EKE MQTT ingestion (commuter train data) through parsing to sink and cancellation feed.

```
Source
  EKE MQTT (sm5.rt.hsl.fi, eke/v1/sm5/#)
    ──> transitdata-eke-mqtt-parser (mqtt-pulsar-gateway)

Processing
  transitdata-eke-mqtt-deduplicator
  transitdata-eke-mqtt-parser

Sink
  transitdata-eke-sink
  Feeds into cancellation flow (stop-cancellation-source)
```

**Dashboard rows (top to bottom):**

| Row | Component | Type | Key metrics |
|-----|-----------|------|-------------|
| 1 | EKE MQTT broker (`sm5.rt.hsl.fi`) | MQTT | `mqtt_connected`, message rate (`eke/v1/sm5/#`) |
| 2 | EKE mqtt-pulsar-gateway | Service | Pod status |
| 3 | EKE raw Pulsar topic | Pulsar topic | rate_in, backlog, storage *(confirm topic name)* |
| 4 | transitdata-eke-mqtt-deduplicator | Service | Pod status |
| 5 | EKE deduplicated Pulsar topic | Pulsar topic | rate_in, backlog, storage *(confirm topic name)* |
| 6 | transitdata-eke-mqtt-parser | Service | Pod status |
| 7 | transitdata-eke-sink | Service | Pod status |

> **Note:** EKE Pulsar topic names need to be confirmed from the cluster. The EKE flow feeds into the Cancellations & Service Alerts flow via stop-cancellation-source.

---

### 5.3 GTFS-RT HTTP APIs Dashboard

**Purpose:** Monitor the published HTTP APIs that consumers (Google Maps, Reittiopas, bus stop signs) hit. This is a cross-cutting dashboard -- it monitors the final consumer-facing output regardless of which domain flow produced it.

Consolidates and extends the existing `gtfsrt-dashboard.json`.

#### Row 1: Status Overview
- **Feed status (stat panels):** `gtfsrt_last_scrape_success` per URL -- red/green banner

#### Row 2: Requests
- **Scrape rate by URL:** `sum by (url) (rate(gtfsrt_scrape_attempts_total[$__rate_interval]))` -- total scrape rate
- **Scrape success rate:** `sum by (url) (rate(gtfsrt_scrape_attempts_total{result="success"}[$__rate_interval]))` -- successful scrapes/sec

#### Row 3: Entity Counts (by feed type)
- **Trip Updates entity count** (filtered by URL containing `trip-updates`)
- **Vehicle Positions entity count** (filtered by URL containing `vehicle-positions`)
- **Service Alerts entity count** (filtered by URL containing `service-alerts`)

#### Row 4: Duration / Freshness
- **Feed timestamp age by URL:** avg seconds since last feed header timestamp
- **HTTP request duration:** *Requires new metric -- see section 6*

#### Row 5: Errors
- **Scrape errors by type:** `rate(gtfsrt_scrape_attempts_total{result!="success"}[$__rate_interval])` grouped by `url`, `result`
- **Scrape success over time:** `gtfsrt_last_scrape_success` showing transitions

---

### 5.4 MQTT Overview Dashboard

**Purpose:** Cross-cutting view of all external MQTT broker connectivity and message ingest rates. Extends the existing `mqtt-dashboard.json`.

#### Row 1: Connectivity
- **Broker connection status (stat panels):** `mqtt_connected` per broker -- red/green
- **Connection losses:** `rate(mqtt_connection_lost[$__rate_interval])` per broker

#### Row 2-N: Message Rates (one row per broker)
For each broker, a panel per topic filter showing `rate(mqtt_messages_received_total{broker=~"...", topic_filter="..."}[$__rate_interval])`.

Brokers and their topic filters (from prod deployment):

| Broker | Topic Filters |
|--------|--------------|
| `apc.rt.hsl.fi` | `/hfp/v2/journey/ongoing/apc/#`, `/hfp/v2/journey/ongoing/apc/bus/#`, `/hfp/v2/journey/ongoing/apc-partial/#` |
| `cmqttdev.cinfra.fi` | `gtfsrt/dev/fi/hsl/vp/#` |
| `hfprec938.rt.hsl.fi` | `/hfp/v2/journey/ongoing/#`, `/hfp/v2/journey/ongoing/vp/metro/#` |
| `hfprec939.rt.hsl.fi` | `/hfp/v2/journey/ongoing/#` |
| `hsl-mqtt-lab-a.cinfra.fi` | `metro-mipro-ats/v1/schedule/#` |
| `mqtt.hsl.fi` | `/hfp/v2/journey/ongoing/vp/+/0060/#` |
| `predin.rt.hsl.fi` | `gtfsrt/v2/fi/hsl/sa`, `gtfsrt/v2/fi/hsl/tu` |
| `sm5.rt.hsl.fi` | `eke/v1/sm5/#` |

---

### 5.5 Databases Dashboard

**Purpose:** Cross-cutting view of all external database connections and polling health. Linked from domain flow dashboards when a DB component is shown.

*Polling metrics are new and must be instrumented -- see section 6.*

#### Row per database:

**Databases tracked:**
- **Pubtrans ROI DB** -- used by `transitdata-pubtrans-arrival-source`, `transitdata-pubtrans-departure-source`
- **Pubtrans DOI DB** -- used by departure estimate flows
- **OMM DB** -- used by `transitdata-omm-cancellation-source`, `transitdata-omm-alert-source`

#### Panels per database:

| Panel | Metric (proposed) | Notes |
|-------|-------------------|-------|
| **Polling rate** | `transitdata_db_poll_total` | Effective polls/sec |
| **Poll latency** | `transitdata_db_poll_duration_seconds` | Histogram of query duration |
| **Query errors** | `transitdata_db_poll_errors_total` | Errors by type |
| **Rows returned** | `transitdata_db_poll_rows_total` | Data volume indicator |
| **Connection pool status** | TBD (depends on connection pool library) | Active/idle/max connections |

Label: `source` = `pubtrans-roi-arrival`, `pubtrans-roi-departure`, `pubtrans-doi`, `omm-cancellation`, `omm-alert`, `metro-ats-cancellation`, `stop-cancellation`

---

### 5.6 Redis Dashboard

**Purpose:** Cross-cutting view of Redis cluster health. Linked from domain flow dashboards where Redis is used.

**Redis instances:**
- **transitdata-redis-cluster** -- used by multiple components (cache-bootstrapper, stop-estimates, etc.)
- **transitdata-metro-redis** -- used by metro estimate flows

#### Panels:

| Panel | Metric source | Notes |
|-------|--------------|-------|
| **Connected clients** | Redis exporter or kube metrics | Connections per instance |
| **Memory usage** | `redis_memory_used_bytes` / `redis_memory_max_bytes` | Utilization % |
| **Key count** | `redis_db_keys` | Keys per database |
| **Hit/miss ratio** | `redis_keyspace_hits_total` / (`hits` + `misses`) | Cache effectiveness |
| **Command latency** | `redis_commands_duration_seconds_total` | Slowness indicator |
| **Evicted keys** | `redis_evicted_keys_total` | Memory pressure |

> **Note:** Redis metrics require a Redis exporter (e.g., `redis_exporter`) running as a sidecar or separate deployment. Check if the managed AKS/Prometheus setup already scrapes Redis metrics.

---

### 5.7 Infrastructure Dashboard

**Purpose:** AKS cluster and Pulsar infrastructure health for saturation analysis.

#### Row 1: Pod Health
- **Pods ready vs desired:** `kube_deployment_status_replicas_ready` vs `kube_deployment_spec_replicas` (filtered by Transitdata deployments)
- **Pod restarts (24h):** `increase(kube_pod_container_status_restarts_total[24h])` filtered by Transitdata pods
- **OOMKilled events:** `kube_pod_container_status_last_terminated_reason{reason="OOMKilled"}` filtered by Transitdata pods

#### Row 2: Resource Usage
- **CPU usage per pod:** `rate(container_cpu_usage_seconds_total[$__rate_interval])` vs requests/limits, filtered by Transitdata pods
- **Memory usage per pod:** `container_memory_working_set_bytes` vs limits, filtered by Transitdata pods
- **Disk usage (PVCs):** `kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes` for Pulsar PVCs

#### Row 3: Pulsar Cluster Health
- **Pulsar broker count:** `count(pulsar_version_info)`
- **Total topics:** `count(pulsar_rate_in)`
- **Total storage:** `sum(pulsar_storage_size)`
- **Total backlog:** `sum(pulsar_msg_backlog)`

---

## 6. New Metrics Required

These metrics do not exist today and need to be instrumented in the microservices or in transitdata-metrics-exporter.

### 6.1GTFS-RT HTTP Request Duration

**Where:** transitdata-metrics-exporter (already makes HTTP requests to GTFS-RT endpoints)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `gtfsrt_scrape_duration_seconds` | Histogram | `url` | Duration of each HTTP GET to GTFS-RT feeds |

**Implementation:** Record the time between HTTP request start and response received in `GtfsRtMetricsExporter`. Micrometer `Timer` or manual `DistributionSummary` on elapsed time.

### 6.2Database Polling Metrics

**Where:** Each database-polling microservice (`transitdata-pubtrans-arrival-source`, `transitdata-pubtrans-departure-source`, `transitdata-omm-cancellation-source`, `transitdata-omm-alert-source`, `transitdata-stop-cancellation-source`, `transitdata-metro-ats-cancellation-source`)

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `transitdata_db_poll_duration_seconds` | Histogram | `source` | Query execution time |
| `transitdata_db_poll_total` | Counter | `source`, `result` | Poll attempts (success/error) |
| `transitdata_db_poll_rows_total` | Counter | `source` | Number of rows returned |

**Implementation:** These are Java microservices. Add Micrometer dependency + Prometheus registry. Expose `/metrics` endpoint. Add ServiceMonitor to AKS manifests.

**Decision needed:** Instrument each microservice individually, or create a shared library in `transitdata-common`? Recommendation: add a metrics utility to `transitdata-common` and use it from each service. This keeps the Prometheus endpoint setup and metric definitions consistent.

### 6.3End-to-End Latency Metrics

**Where:** Output-stage microservices that can compute the difference between the original event timestamp and the current time.

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `transitdata_e2e_latency_seconds` | Histogram | `pipeline` | Time from source event to GTFS-RT output |

Pipelines:
- `ptROI_to_tripupdate` -- measured in `transitdata-tripupdate-processor`: `now() - pubtrans ROI event timestamp`
- `apc_source_to_expanded` -- measured in `transitdata-partial-apc-expander-combiner`: `now() - original APC message timestamp`

**Implementation:** The Pulsar message publish timestamp or the embedded event timestamp from the protobuf message can serve as the start time. Compute `System.currentTimeMillis() - eventTimestamp` at the output processor.

### 6.4Logged Error Counts

**Option A (recommended):** Use Prometheus log-based metrics via a log exporter sidecar (e.g., `mtail` or `promtail` with metrics).

**Option B:** Add a Micrometer counter in each microservice's logging framework (Logback appender that increments a counter per log level).

| Metric | Type | Labels | Description |
|--------|------|--------|-------------|
| `transitdata_log_messages_total` | Counter | `service`, `level` | Log messages by severity |

---

## 7. Implementation Plan

### Phase 1: Dashboards Using Existing Metrics (no new instrumentation needed)

1. **Create Golden Signals dashboard** using existing metrics (`gtfsrt_*`, `mqtt_*`, `pulsar_*`, `kube_*`)
2. **Create domain flow dashboards** (sections 5.2.1--5.2.5) using existing Pulsar metrics (`pulsar_rate_in`, `pulsar_msg_backlog`, `pulsar_storage_size`), MQTT metrics (`mqtt_connected`, `mqtt_messages_received_total`), and kube metrics for service pod status. Confirm missing Pulsar topic names (EKE, cancellation, service alert topics) from the cluster.
3. **Consolidate GTFS-RT dashboard** into the new hierarchy (section 5.3)
4. **Add dashboard links** -- Golden Signals links to domain flow dashboards, domain flow topic panels link to built-in Pulsar Topic Metrics dashboard
5. **Set up Grafana Alerting** with critical and warning rules that use existing metrics

### Phase 2: Instrument New Metrics in transitdata-metrics-exporter

6. Add `gtfsrt_scrape_duration_seconds` to transitdata-metrics-exporter (HTTP request timing)
7. Update GTFS-RT dashboard with duration panels
8. Add alert for HTTP request duration degradation

### Phase 3: Instrument Microservice Metrics

9. Add Micrometer + Prometheus registry to `transitdata-common`
10. Instrument database polling metrics in source microservices (ptROI, OMM, etc.)
11. Add ServiceMonitors for each instrumented microservice
12. Add DB polling panels to Predictions and Cancellations domain flow dashboards
13. Add DB polling alerts

### Phase 4: End-to-End Latency + Error Tracking

14. Instrument E2E latency in `transitdata-tripupdate-processor` and `transitdata-partial-apc-expander-combiner`
15. Add log-level counting (Logback appender or sidecar approach)
16. Add E2E latency and error panels to Golden Signals and relevant domain flow dashboards
17. Add remaining alert rules

### Phase 5: Decommission Legacy Monitoring

18. Verify all legacy Azure custom metric alerts are covered by Grafana alerts
19. Remove `cronjob-pulsar-monitor-data-collector`
20. Remove `cronjob-gtfsrt-monitor-data-collector`
21. Remove `transitdata-mqtt-monitor-data-collector`

---

## 8. Open Questions

1. **Backlog thresholds:** What Pulsar backlog counts should trigger warnings? Need to observe baseline during normal operations and set thresholds at e.g., 2x-5x normal.
2. **GTFS-RT feed age thresholds:** What's an acceptable timestamp age? 60s? 120s? This varies by feed type (service alerts update less frequently than vehicle positions).
3. **Notification channels:** Where should alerts be sent? Slack channel? PagerDuty? Email?
4. **Pulsar topic completeness:** Several topic names need to be confirmed from the cluster -- EKE raw/deduplicated topics, cancellation internal topics, and service alert topics are referenced in the architecture but not present in the current Pulsar Overview dashboard.
5. **Log-based error metrics approach:** Option A (sidecar/promtail) vs Option B (Logback counter appender) -- which is preferred? Option A is less invasive but requires sidecar containers. Option B is simpler but requires touching every microservice.
6. **Recording rules:** Should we create Prometheus recording rules for expensive queries (e.g., baseline calculations for anomaly detection)?
7. **Dashboard access:** Should dashboards be public (no login) or restricted? Who needs edit access vs. view access?
