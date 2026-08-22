# Synthetic fixtures

`synthetic-cat-v1.petpack` is built from generated 2 by 2 premultiplied RGBA pixels. It contains two dwell loops and two directed transitions, which exercise graph connectivity without using a real animal identity.

`synthetic-cat-forward-v1.petpack` uses the same synthetic media and graph, adds the unknown optional capability `future-audio`, and leaves node and scene weight overrides empty. It proves that Players ignore unknown optional capabilities and apply default weight `1.0` consistently.

Regenerate it from the repository root:

```bash
python3 -m petpack.tools.build_fixture petpack/fixtures/synthetic-cat-v1.petpack
python3 -m petpack.tools.build_fixture \
  --forward-compatible petpack/fixtures/synthetic-cat-forward-v1.petpack
```

Real pet media and customer packages must never be copied into this directory.
