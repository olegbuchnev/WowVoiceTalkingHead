# Portrait loading diagnostics

In DevTools Elements, the first element immediately inside `<body>` is hidden:

```html
<div id="portrait-debug" hidden aria-hidden="true">{"questID":977,"npcID":10377,"displayID":9780,"modelFileID":119369,"state":"ready","loadID":"p-a81f3c92d640"}</div>
```

Double-click the single JSON text node in Elements to copy the complete diagnostic
line, including quests without a load ID. Diagnostic values appear only in the
JSON text, without duplicate data attributes. `loadID` identifies one portrait mount, not a visitor. Preloading
the next portrait does not replace the current ID. On the series completion
screen it retains the last displayed portrait. A quest without a model has an
empty load ID and `state: "unavailable"`; no viewer request is made.

## Read over SSH

The production host has `/srv/talkinghead/trace-portrait.py`. Run as the deployment
administrator:

```sh
python3 /srv/talkinghead/trace-portrait.py p-a81f3c92d640
docker logs --since 30m talkinghead-vote-web-1
tail -n 100 /var/log/nginx/talkinghead-assets.jsonl
```

The helper joins browser events to Node/container Nginx and HTTPS edge logs by
resource request IDs. It also reads rotated edge logs. No admin-panel password
is required. Container logs rotate at 10 MiB x 3; recreation removes the old
container's logs. Preserve a diagnostic extract before another deployment when
investigating a specific report. Host logs have a separate logrotate rule.

## Events and interpretation

- `portrait_client`: started/ready/timeout/error/cancelled, quest/display/model
  IDs, load ID, visibility and timing. All mounts report, including preloads.
- `asset_server`: read time and response finish time inside the Node asset
  service. Reading is asynchronous; it is **not** a promise of physical disk IO:
  Linux may satisfy the read from its page cache.
- `asset_proxy`: container Nginx time, upstream timing, bytes and gzip ratio.
- `asset_edge`: HTTPS Nginx time and bytes actually sent toward the client.

Browser phase times are milliseconds since portrait creation: `viewerMs`,
`assetsReadyMs` (geometry, animation and texture readiness), `visibleMs` (camera,
lighting and two animation frames completed). `cameraMs` is a duration after
asset readiness, including its settings request. Resource timings separately
record TTFB, transfer duration and encoded/decoded byte counts for the main M2
and camera request. `reused` means the resource request began before this mount;
zero transferred bytes may indicate browser caching. These timings do not isolate
pure GPU work: asset readiness includes other texture/dependency requests and
the readiness polling interval. Multiple portraits can overlap on the network.

Reports contain no cookies, IPs, quest text, free-form error messages or full URLs.
They use a small best-effort POST; they never block voting, retry indefinitely or
show errors to the visitor. Thus reports may be absent when the connection is
lost or the tab closes. The endpoint validates and bounds fields and body size,
and both Nginx and Node limit request volume. Client metrics are untrusted
diagnostics, entirely separate from votes.

## Host setup

Install `docker/asset-diagnostics.conf` into `/etc/nginx/conf.d/`. In the HTTPS
virtual host replace `access_log off` with:

```nginx
access_log /var/log/nginx/talkinghead-assets.jsonl talkinghead_assets if=$talkinghead_log_asset;
```

Install `docker/asset-diagnostics.logrotate` into `/etc/logrotate.d/talkinghead-assets`.
Run `nginx -t` before `systemctl reload nginx`. The edge request ID is taken from
the container's response, joining its logs and the browser's Server-Timing data.

## Baseline, 2026-10-12

The cache is about 839 MiB on disk; the host has 1,895 MiB RAM and the web
container has a 384 MiB limit. No application-level whole-cache RAM preload.
Linux manages its own page cache. Model 119369 is 24,478,808 bytes, transferred
as 11,353,298 gzip bytes. Two host-local reads took 13–15 ms; local Nginx gzip
responses took 0.55–0.65 s. A remote HTTPS probe received the first byte after
0.42 s but finished after 56.9 s. That observation points to transfer latency
on this route rather than slow file reads. It does not establish whether the
server's network or the visitor's route is limiting throughput. Compare reports
from other connections before choosing RAM upgrades or a delivery redesign.
