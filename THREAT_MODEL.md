# redis-detail-exporter threat model

## Overview

Go HTTP exporter turns Redis keyspace/list lengths into Prometheus queue metrics on each scrape; standalone binary and container are supported (main.go:54, main.go:77, main.go:109; Dockerfile:16).

The table maps source-established consumers to effective resources; live deployment is unverified.

| Deployment / consumer | Configuration → effective resource | Recipients | Enforcing control | Evidence |
| --- | --- | --- | --- | --- |
| binary/container / HTTP metrics | PORT; default fallback → :8001/metrics unless PORT overrides | Reachable HTTP clients | Host network controls; handler has no auth middleware | main.go:150; main.go:159 |
| binary/container / Redis scanning | REDIS_ADDR → explicit address, or localhost:6379 in the exporter network namespace when unset/empty (go-redis default); REDIS_KEY_PATTERNS comma split, default *; all nonempty DBs; SCAN count 1000 | Exporter process; Redis server | Redis external access control; app constructs no password/TLS options | main.go:23; main.go:42; main.go:63; main.go:155 |
| main push / Container image | Dockerfile build → GHCR tags → ghcr.io/&lt;repository&gt;:latest and :&lt;commit SHA&gt;; amd64/arm64 | Registry consumers | GitHub workflow job permissions and registry token | Dockerfile:4; .github/workflows/build.yaml:32 |

## Threat Model, Trust Boundaries, and Assumptions

**Protected assets and objectives.** Redis availability; database numbers, queue names and lengths; container publication integrity. Key names are emitted as metric labels (main.go:115). Keep Redis reads and scrape cost within operational capacity; restrict metric readers where names carry sensitive context; prevent build credentials from reaching published artifacts.

The exporter brokers a narrow Redis read operation for each scraper. Scrapers do not supply the Redis destination or arbitrary Redis commands. Deployment operators choose the destination and key patterns; unset or empty REDIS_ADDR still selects localhost:6379 in the exporter network namespace, so incomplete configuration does not disable Redis access; Redis writers choose the names and data structures the exporter encounters. These are different capabilities. A compromised Redis writer does not automatically obtain exporter process or cloud authority, and a legitimate scrape is not itself an unauthorized database read.

The exposed dataset is operational metadata rather than list contents. That distinction limits ordinary confidentiality impact, but names can encode identifiers, customer context or application internals. Decide the intended audience from actual names and downstream access. A hostname or private container placement alone does not establish who can reach the HTTP listener.

**Attacker starting position.** A network-reachable caller can scrape without application authentication. A Redis writer can influence metric names/cardinality; neither capability implies AWS, host, Redis administration or repository write access.

**Assumptions and unresolved evidence.** User context: most infrastructure is AWS and almost all services use Cloudflare; this does not establish a particular ingress or Access policy. Minors’ PII is highly sensitive, including copies in diagnostics or downstream datasets. No runtime deployment, IAM, network rules or Cloudflare routing is defined here; do not infer public exposure from binding all interfaces. The repository tracks go.sum, including module and go.mod checksums for github.com/redis/go-redis/v9 v9.18.0 and transitive dependencies; these are available dependency-integrity evidence, not proof that dependency code is safe (go.sum:1-10; go.mod:5; [pinned go-redis address normalization](https://github.com/redis/go-redis/blob/v9.18.0/options.go#L309)).

Freshness also matters operationally: cached keys remain in the process map and disappearing queues become zero. Consumers should distinguish a valid zero from collection failure using independent health signals; a stale or missing observation is not proof of an empty workload (main.go:112; main.go:137).

## Attack Surface, Mitigations, and Attacker Stories

These are investigation hypotheses, not validated vulnerabilities. Establish each prerequisite before assigning impact; mitigations apply if the scenario is confirmed.

| Priority | Scenario and capability gain | Prerequisites | Impact | Existing controls | Mitigation | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | A reachable unauthorized scraper learns queue names or database structure beyond its intended audience. | The listener is reachable across a real reader boundary and labels contain sensitive information. | Disclosure of workload metadata, potentially identifiable student context if applications encode it in keys. | Endpoint only emits names/counts; no list-content retrieval. Network restrictions belong to the host. | Restrict scrape ingress to monitoring principals; remove identifiers from key-derived labels or provide approved aggregate labels. | main.go:109; main.go:115; main.go:159 |
| 2 | Repeated concurrent scrapes or a rapidly growing keyspace impose Redis scanning work that harms the source application. | Caller can reach exporter; representative keyspace and scrape concurrency exceed actual Redis/host capacity. | Shared Redis latency or monitoring interruption; broader outage requires measured source-workload impact. | SCAN iterates with count 1000; list type errors are skipped. These are not a total-work budget. | Set deployment scrape concurrency/rate limits and representative collection budgets; measure impact before claiming denial of service. | main.go:35; main.go:77; main.go:120 |
| 3 | A Redis writer influences Prometheus output through key names, increasing cardinality or producing misleading metric text. | Writer controls scanned keys and monitoring consumes resulting labels as operational truth. | Metric integrity loss, monitoring cost or misdiagnosis; downstream parser behavior must be established. | Only selected patterns are collected, and LLEN excludes non-list values. Pattern choice is trusted configuration. | Encode label values using the monitoring format’s escaping rules and choose stable bounded label dimensions. | main.go:88; main.go:98; main.go:115; main.go:155 |
| 4 | Release input compromise changes the exporter image consumed by infrastructure. | Attacker reaches a dependency/build input or gains a relevant repository/workflow capability. | Published image can inherit its deploying host’s network and credential authority. | Main-branch workflow, pinned action commits and package-write job permission separate publication from ordinary scraping. | Protect branch/workflow changes and dependency resolution; deploy an approved immutable image identity. | Dockerfile:4; .github/workflows/build.yaml:3; .github/workflows/build.yaml:17; .github/workflows/build.yaml:38 |

## Severity Calibration (Critical, High, Medium, Low)

| Level | Concrete example | Counterexample or limiting prerequisite |
| --- | --- | --- |
| Critical | Demonstrated image compromise obtains broad production privileges and causes widespread high-sensitivity data exposure. | No such privileges or production deployment are established by this repository; exporter process compromise alone is insufficient. |
| High | An unauthorized reader obtains highly sensitive identifiable student data embedded in exported keys, or collection causes a material shared Redis outage. | Requires actual labels, reachable audience and workload impact. Routine queue counts do not establish this severity. |
| Medium | A reachable caller causes sustained localized exporter degradation, or a Redis writer corrupts operational metrics across a meaningful boundary. | Quantify duration, resource limits and downstream consumption; authorized key creation and legitimate scrapes are not findings. |
| Low | Non-sensitive internal names leak to a limited audience or individual scrapes fail without meaningful service impact. | Publicly intended metadata and a caller’s own failed request may carry no security impact at all. |

Independent offline source architecture review; no application execution or live configuration validation. Source evidence does not establish exploitability. Revisit when entry points, recipients, permissions or deployment paths change.

Repository: github.com/mathspace/redis-detail-exporter
Version: a788e2f6d89326befa3012aec514bfdf5f568ca3
