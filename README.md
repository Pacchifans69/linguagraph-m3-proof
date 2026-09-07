# LinguaGraph M3 independent hosted proof

This public repository is a checkpoint-scoped, disposable proof harness for the exact LinguaGraph M3 candidate. It does not modify the application repository or establish permanent CI policy.

## Exact proof target

- Application: `Pacchifans69/LinguaGraph`
- Branch: `m3-word-token-segmentation-foundation`
- Candidate SHA: `bc1a4cf3f4b0e7949f3185848533a912caf2026e`
- Candidate tree: `c2f1a0d47fe61397f9a7d024946ae3e428764b13`
- Frozen M3 contract/base: `fa861409947705f658209e53b8c507b535c5233a`
- Expected Alembic head: `0004`

The harness fails closed unless the remote candidate branch, detached checkout, commit tree, proof repository, proof branch, and proof commit all match the recorded values.

## Authority and boundary

A Human approved an M3-specific External Infrastructure Exception after the canonical exact-candidate GitHub Actions run failed before any workflow step started. The exception waives only successful proof on a GitHub-hosted runner.

It does not waive exact provenance, clean hosted Linux execution, Python 3.13, Node 24, PostgreSQL 18, frozen dependencies, Alembic empty-to-`0004` verification, full real-PostgreSQL backend tests with zero skips, frontend lint/typecheck/Vitest/build, Playwright golden path, Unicode blocker, M2 sentence segmentation, M3 token segmentation, cleanup, final tracked-tree integrity, or retained evidence.

Earlier M0.7, M1, and M2 exceptions and proof results do not prove this M3 candidate. This harness does not close `G2-X01`.

## Retained proof history

- Pipeline #1 used proof commit `6d6522356bb7d9e18574dcb5e99be2891d6f60fe` against candidate `11385271c2e15f2331338bfd382627013fe38564` / tree `5fecde0c23d5f4c577096fca62fdc1fdae3d56e4`.
- It reached the full real-PostgreSQL backend suite and reported `412 passed, 3 failed`; all three failures were stale `0003` / pre-M3 foreign-key expectations.
- Its failure logs and artifacts remain retained. They are diagnostic evidence and do not prove the repinned candidate.

- Pipeline #2 used proof commit `fda8103f3d2c48f4baa49488818df74eec42a2a7` against candidate `1aeef812a1df276784fecb999d7d5e4b36dbfabd` / tree `9e0d7be375cbf878e52ce1be3c0216d7cf7d07b7`.
- It passed all gates through the frontend production build; Playwright then reported three passed specifications and one failed M2 sentence-segmentation specification because `getByText('Saved')` ambiguously matched `Unsaved preview` and `Not saved` under strict mode.
- Its failure logs, traces, and artifacts remain retained as diagnostic evidence and do not prove the newly repinned candidate.

- Pipeline #3 used proof commit \`a54311bc73579810d212ffc21a8194b1f84e87b7\` against candidate \`0ddee8c9fec4a244af78987584eba16a88323acf\` / tree \`fe523d9306b588575eb46f44e862b5cae579f9f5\`.
- It passed every exact-candidate semantic gate: provenance, Python 3.13, Node 24, PostgreSQL 18, frozen dependency installs, Alembic \`0004\`, 415 real-PostgreSQL backend tests with zero skips, frontend lint/typecheck/Vitest/build, all four Playwright specifications, cleanup, and final integrity.
- Its logs and artifacts remain retained as successful proof of that historical candidate. They do not prove the newly repinned candidate.

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
