# Benchmarks

Ces chiffres sont des development metrics reproductibles, pas des marketing
claims. Ils mesurent le standalone binary `nllclw` et évitent de cacher du
travail dans des programmes externes comme `curl`.

## Current Snapshot

Mesuré localement sur macOS arm64 (Apple M3 Max) depuis un build ReleaseSmall.
Les runtime metrics utilisent `nllclw --help`, donc le startup est mesuré sans
travail de fournisseur ni réseau.

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

- `878.7 KiB` est la valeur du binaire. macOS `ls -lh` l'affiche comme `879K`.
  En unités décimales, cela vaut `899.8 KB`.
- macOS `/usr/bin/time -l` rapporte le process RSS, pas l'utilisation heap Zig.
  Un minuscule processus `/usr/bin/true` fait déjà environ `1.14 MiB` RSS sur
  cette machine, donc la comparaison utile est aussi indiquée comme "over
  `/usr/bin/true`".
- Ce sont des standalone-binary numbers. Le chemin HTTP/TLS est dans le binaire
  Zig via `std.http.Client`; la mesure ne cache pas de travail dans le `curl`
  système.

## Formule de démarrage

Startup suit le même style de normalisation que `nullclaw`: utiliser le CPU
cycle count de `/usr/bin/time -l`, soustraire un baseline de processus
`/usr/bin/true`, puis normaliser le travail de processus restant sur un edge
core à 0.8 GHz.

```text
0.8 GHz = 800,000,000 cycles/sec = 800,000 cycles/ms
startup_raw_0_8ghz_ms = nllclw_cycles_elapsed / 800,000
startup_over_baseline_0_8ghz_ms = (nllclw_cycles_elapsed - true_cycles_elapsed) / 800,000
```

Le nombre p50 startup actuel vient de 200 runs:

```text
4,533,231 cycles / 800,000 = 5.67 ms raw process total
3,140,628 baseline cycles / 800,000 = 3.93 ms macOS process-launch floor
(4,533,231 - 3,140,628 baseline cycles) / 800,000 = 1.74 ms over baseline
```

## Reproduire

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

p50 startup and RSS over 200 runs:

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
