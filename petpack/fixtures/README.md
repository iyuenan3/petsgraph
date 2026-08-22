# Synthetic fixtures

`synthetic-cat-v1.petpack` is built from generated 2 by 2 premultiplied RGBA pixels. It contains two dwell loops and two directed transitions, which exercise graph connectivity without using a real animal identity.

Regenerate it from the repository root:

```bash
python3 -m petpack.tools.build_fixture petpack/fixtures/synthetic-cat-v1.petpack
```

Real pet media and customer packages must never be copied into this directory.
