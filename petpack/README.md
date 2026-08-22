# PetPack 1.0

PetPack is the public, platform-neutral runtime contract between a private pet-production workflow and PetsGraph Player. A `.petpack` is a single ZIP file containing one pet, a directed action graph, passive behavior timing, fixed-stage clip metadata, premultiplied RGBA media, and a complete integrity manifest.

This directory contains only public schemas, a standard-library validator, deterministic synthetic fixtures, and tests. It contains no real pet media, customer material, provider configuration, prompts, or production records.

## Validate a package

From the repository root:

```bash
python3 -m petpack.validator pet.petpack
```

Successful validation prints a JSON report without the full local path or pet display name. Failures use a stable error code, print no package content, and exit non-zero.

The validator applies archive safety limits before reading entries, rejects path traversal and executable content, verifies exact integrity coverage, and validates the manifest, graph, behavior, clips, and baseline media semantics.

## Build the synthetic fixture

```bash
python3 -m petpack.tools.build_fixture petpack/fixtures/synthetic-cat-v1.petpack
python3 -m unittest discover -s petpack/tests -v
```

The fixture uses generated 2 by 2 RGBA pixels and has no real pet identity. The builder uses fixed timestamps and canonical JSON so repeated builds are byte-identical on the same Python ZIP implementation.

## PetPack 1.0 baseline

- ZIP entries use UTF-8 forward-slash paths and store or deflate compression. Entries are contiguous and may not use explicit directories, comments, encryption, strong-encryption flags, data descriptors, prefix data, gaps, or trailing data.
- `manifest.json`, `graph.json`, `behavior.json`, `integrity.json`, `clips/`, and `media/` are the only runtime roots.
- `integrity.json` covers every regular file except itself.
- Each runtime clip contains exactly one required `cropped-rgba-clips` representation.
- Semantic-version core numbers and frame counts must fit a signed 32-bit integer on every platform. Build metadata does not affect version precedence, while canonical package paths still use the complete version string.
- Baseline media is raw, sRGB, premultiplied RGBA8 with fixed crop geometry and `1.0` playback rate.
- Packages are data, never plugins. Scripts, executables, dynamic libraries, symlinks, and executable permission bits are rejected.
- Signature structure and trust verification are intentionally deferred. PetPack 1.0 packages produced in this phase are unsigned.

Product semantics and long-term compatibility requirements are defined in `AIREADME/SPEC.md`.
