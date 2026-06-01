# Benchmarks

এই numbers reproducible development metrics-এর জন্য, marketing claims নয়। এগুলো
standalone `nllclw` binary measure করে এবং `curl`-এর মতো external programs-এ কাজ
লুকানো এড়িয়ে চলে।

## Current Snapshot

macOS arm64 (Apple M3 Max)-এ ReleaseSmall build থেকে locally measured। Runtime
metrics `nllclw --help` ব্যবহার করে, তাই startup provider বা network work ছাড়াই
measured হয়।

| Metric | Value |
|---|---:|
| RAM | 1.53 MiB peak process RSS |
| RAM over `/usr/bin/true` | 0.39 MiB |
| Startup (0.8 GHz, raw process) | 5.67 ms p50 |
| Startup (0.8 GHz, over `/usr/bin/true`) | 1.74 ms p50 |
| Binary Size | 899,784 bytes (878.7 KiB) |
| Binary Size after platform `strip` | 813,760 bytes (794.7 KiB) |
| Tests | 385/385 default; 390/390 with `-Dshell-tool=true` |
| Source Files | 70 Zig files (`src/**/*.zig` + `build.zig`) |
| Zig LOC | 20,903 |

Notes:

- `878.7 KiB` হলো binary value। macOS `ls -lh` এটি `879K` হিসেবে print করে।
  Decimal units-এ এটি `899.8 KB`।
- macOS `/usr/bin/time -l` process RSS report করে, Zig heap usage নয়। Tiny
  `/usr/bin/true` process এই machine-এ ইতিমধ্যেই প্রায় `1.14 MiB` RSS, তাই useful
  comparison "over `/usr/bin/true`" হিসেবেও দেখানো হয়েছে।
- এগুলো standalone-binary numbers। HTTP/TLS path Zig binary-তে `std.http.Client`
  দিয়ে আছে; measurement system `curl`-এ কাজ লুকায় না।

## Startup Formula

Startup `nullclaw`-এর একই normalization style follow করে: `/usr/bin/time -l` থেকে
CPU cycle count ব্যবহার করুন, `/usr/bin/true` process baseline subtract করুন, তারপর
remaining process work 0.8 GHz edge core-এ normalize করুন।

```text
0.8 GHz = 800,000,000 cycles/sec = 800,000 cycles/ms
startup_raw_0_8ghz_ms = nllclw_cycles_elapsed / 800,000
startup_over_baseline_0_8ghz_ms = (nllclw_cycles_elapsed - true_cycles_elapsed) / 800,000
```

Current p50 startup number 200 runs থেকে আসে:

```text
4,533,231 cycles / 800,000 = 5.67 ms raw process total
3,140,628 baseline cycles / 800,000 = 3.93 ms macOS process-launch floor
(4,533,231 - 3,140,628 baseline cycles) / 800,000 = 1.74 ms over baseline
```

## Reproduce

Build:

```sh
zig build -Doptimize=ReleaseSmall
zig build -Doptimize=ReleaseSmall -Dsize-tuned=false
```

Binary size:

```sh
stat -f "%z bytes" zig-out/bin/nllclw
ls -lh zig-out/bin/nllclw

cp zig-out/bin/nllclw /tmp/nllclw-strip-check
strip /tmp/nllclw-strip-check
stat -f "%z bytes" /tmp/nllclw-strip-check
rm /tmp/nllclw-strip-check
```

One process measurement:

```sh
/usr/bin/time -l zig-out/bin/nllclw --help >/dev/null
```

p50 startup এবং RSS over 200 runs:

```sh
tmp_nllclw=$(mktemp)
for _ in $(seq 1 200); do
  /usr/bin/time -l zig-out/bin/nllclw --help >/dev/null
done 2> "$tmp_nllclw"

tmp_baseline=$(mktemp)
for _ in $(seq 1 200); do
  /usr/bin/time -l /usr/bin/true >/dev/null
done 2> "$tmp_baseline"

awk '/cycles elapsed/ { print $1 }' "$tmp_nllclw" | sort -n |
  awk 'BEGIN { n = 0 } { a[++n] = $1 } END { printf "p50 cycles: %d\nraw_0_8ghz_ms: %.2f\n", a[int((n + 1) / 2)], a[int((n + 1) / 2)] / 800000 }'

awk '/maximum resident set size/ { print $1 }' "$tmp_nllclw" | sort -n |
  awk 'BEGIN { n = 0 } { a[++n] = $1 } END { printf "p50 RSS: %.2f MiB\n", a[int((n + 1) / 2)] / 1048576 }'

awk '/cycles elapsed/ { print $1 }' "$tmp_baseline" | sort -n |
  awk 'BEGIN { n = 0 } { a[++n] = $1 } END { printf "baseline p50 cycles: %d\nbaseline_0_8ghz_ms: %.2f\n", a[int((n + 1) / 2)], a[int((n + 1) / 2)] / 800000 }'

awk '/maximum resident set size/ { print $1 }' "$tmp_baseline" | sort -n |
  awk 'BEGIN { n = 0 } { a[++n] = $1 } END { printf "baseline p50 RSS: %.2f MiB\n", a[int((n + 1) / 2)] / 1048576 }'

nllclw_cycles=$(awk '/cycles elapsed/ { print $1 }' "$tmp_nllclw" | sort -n |
  awk 'BEGIN { n = 0 } { a[++n] = $1 } END { print a[int((n + 1) / 2)] }')
baseline_cycles=$(awk '/cycles elapsed/ { print $1 }' "$tmp_baseline" | sort -n |
  awk 'BEGIN { n = 0 } { a[++n] = $1 } END { print a[int((n + 1) / 2)] }')
awk -v app="$nllclw_cycles" -v base="$baseline_cycles" \
  'BEGIN { printf "startup_over_baseline_0_8ghz_ms: %.2f\n", (app - base) / 800000 }'

rm "$tmp_nllclw" "$tmp_baseline"
```

Tests and cross-target builds:

```sh
zig build test --summary all
zig build test --summary all -Dshell-tool=true
zig build -Dtarget=x86_64-windows --release=small
zig build -Dtarget=x86_64-linux --release=small
zig build -Dtarget=aarch64-linux --release=small
zig build -Dtarget=aarch64-macos --release=small
zig build -Dtarget=wasm32-wasi --release=small
```

Source counts:

```sh
find . -path './.zig-cache' -prune -o -path './zig-out' -prune -o -path './.git' -prune -o -name '*.zig' -type f -print | wc -l
{ find src -name '*.zig' -type f -print | sort; printf 'build.zig\n'; } | xargs wc -l
```
