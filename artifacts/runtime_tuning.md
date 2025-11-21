# Runtime Tuning Guide

## Threading
- **Default**: Use `min(4, physical_cores)`.
- **Reasoning**: Android devices often have big.LITTLE architecture. Using too many threads (e.g., all 8 cores) can cause thermal throttling and schedule threads on little cores, reducing performance. 4 threads is usually the sweet spot.

## Memory Mapping (mmap)
- **Enabled by default**: `llama.cpp` uses mmap.
- **Behavior**: First inference might be slower as pages are faulted in.
- **Benefit**: Reduces memory pressure as OS can drop clean pages if needed.

## Sampling Parameters
- **Temperature**: Controls randomness. 0.7-0.8 is good for chat.
- **Top-K**: 40 is standard.
- **Top-P**: 0.9-0.95.

## Performance Monitoring
- Monitor `tokens/sec`.
- If thermal throttling occurs (speed drops significantly), reduce thread count or pause generation.
