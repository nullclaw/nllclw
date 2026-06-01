# Benchmarks

ये numbers reproducible development metrics के लिए हैं, marketing claims के लिए
नहीं। ये standalone `nllclw` binary measure करते हैं और `curl` जैसे external
programs में work छिपाने से बचते हैं।

## Current Snapshot

ReleaseSmall build से macOS arm64 (Apple M3 Max) पर locally measured।
Runtime metrics `nllclw --help` इस्तेमाल करते हैं ताकि startup provider या network
work के बिना measured हो।

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

- `878.7 KiB` binary value है। macOS `ls -lh` इसे `879K` print करता है।
  Decimal units में यह `899.8 KB` है।
- macOS `/usr/bin/time -l` process RSS report करता है, Zig heap usage नहीं।
  Tiny `/usr/bin/true` process इस machine पर पहले से लगभग `1.14 MiB` RSS है,
  इसलिए useful comparison "over `/usr/bin/true`" के रूप में भी दिखाया गया है।
- ये standalone-binary numbers हैं। HTTP/TLS path Zig binary में `std.http.Client`
  के माध्यम से है; measurement system `curl` में work नहीं छिपाता।

## Startup Formula

Startup `nullclaw` जैसी normalization style follow करता है: `/usr/bin/time -l`
से CPU cycle count लें, `/usr/bin/true` process baseline subtract करें, फिर बाकी
process work को 0.8 GHz edge core पर normalize करें।

```text
0.8 GHz = 800,000,000 cycles/sec = 800,000 cycles/ms
startup_raw_0_8ghz_ms = nllclw_cycles_elapsed / 800,000
startup_over_baseline_0_8ghz_ms = (nllclw_cycles_elapsed - true_cycles_elapsed) / 800,000
```

Current p50 startup number 200 runs से आता है:

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

p50 startup और RSS over 200 runs:

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

Tests और cross-target builds:

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
