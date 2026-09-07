# LinguaGraph M3 independent hosted proof

This public repository is a checkpoint-scoped, disposable proof harness for the exact LinguaGraph M3 candidate. It does not modify the application repository or establish permanent CI policy.

## Exact proof target

- Application: `Pacchifans69/LinguaGraph`
- Branch: `m3-word-token-segmentation-foundation`
- Candidate SHA: `11385271c2e15f2331338bfd382627013fe38564`
- Candidate tree: `5fecde0c23d5f4c577096fca62fdc1fdae3d56e4`
- Frozen M3 contract/base: `fa861409947705f658209e53b8c507b535c5233a`
- Expected Alembic head: `0004`

The harness fails closed unless the remote candidate branch, detached checkout, commit tree, proof repository, proof branch, and proof commit all match the recorded values.

## Authority and boundary

A Human approved an M3-specific External Infrastructure Exception after the canonical exact-candidate GitHub Actions run failed before any workflow step started. The exception waives only successful proof on a GitHub-hosted runner.

It does not waive exact provenance, clean hosted Linux execution, Python 3.13, Node 24, PostgreSQL 18, frozen dependencies, Alembic empty-to-`0004` verification, full real-PostgreSQL backend tests with zero skips, frontend lint/typecheck/Vitest/build, Playwright golden path, Unicode blocker, M2 sentence segmentation, M3 token segmentation, cleanup, final tracked-tree integrity, or retained evidence.

Earlier M0.7, M1, and M2 exceptions and proof results do not prove this M3 candidate. This harness does not close `G2-X01`.

## Execution

CircleCI runs `.circleci/config.yml` on a fresh Ubuntu 24.04 machine executor. `scripts/run-m3-proof.sh`:

1. verifies the proof repository and exact application SHA/tree;
2. records OS, runtime, Git, and container-image provenance;
3. installs dependencies from frozen lockfiles;
4. migrates a fresh PostgreSQL 18 schema through Alembic `0004` and checks it;
5. runs the complete backend suite and rejects every skipped test;
6. runs frontend lint, typecheck, Vitest, and production build;
7. runs Playwright golden-path, Unicode, M2 sentence-segmentation, and M3 token-segmentation specifications;
8. verifies disposable-database cleanup and that the candidate remains unmodified;
9. retains command, environment, test, cleanup, and SHA-256 evidence.

A successful run supplies evidence for a later Gate 2 audit. It does not create or merge a LinguaGraph pull request or complete M3 by itself.
