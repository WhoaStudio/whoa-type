#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
bench_dir=$(mktemp -d)
trap 'rm -rf "$bench_dir"' EXIT
xcrun swiftc -O \
  whoa-type/SoundPacks/SoundPackManifest.swift \
  whoa-type/SoundPacks/PreparedSoundBank.swift \
  whoa-type/Audio/AudioTrigger.swift whoa-type/Audio/TriggerRing.swift \
  whoa-type/Audio/AudioControlMailbox.swift whoa-type/Audio/VoicePool.swift \
  whoa-type/Audio/AudioRenderer.swift whoa-type/Input/KeyMapper.swift \
  whoa-type/Input/KeyboardGeometry.swift Tools/SyntheticBenchmark/main.swift \
  -o "$bench_dir/benchmark"
if [[ "${WHOA_CHECK_ALLOCATIONS:-0}" == 1 ]]; then
  xcrun clang -dynamiclib Tools/AllocationProbe.c -o "$bench_dir/probe.dylib"
  DYLD_INSERT_LIBRARIES="$bench_dir/probe.dylib" "$bench_dir/benchmark"
else
  "$bench_dir/benchmark"
fi
