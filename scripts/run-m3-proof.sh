#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

PROOF_ROOT="$(pwd -P)"
ARTIFACT_DIR="${PROOF_ROOT}/proof-artifacts"
CANDIDATE_DIR="${PROOF_ROOT}/candidate"
POSTGRES_CONTAINER="linguagraph-m3-postgres18"

mkdir -p "${ARTIFACT_DIR}"
: > "${ARTIFACT_DIR}/command-manifest.txt"

utc_now() {
  date -u +'%Y-%m-%dT%H:%M:%SZ'
}

record_manifest() {
  printf '%s\n' "$*" >> "${ARTIFACT_DIR}/command-manifest.txt"
}

run_stage() {
  local slug="$1"
  local label="$2"
  shift 2

  local started finished rc
  started="$(utc_now)"
  printf '\n===== %s =====\n' "${label}"
  record_manifest "stage=${slug}"
  record_manifest "label=${label}"
  record_manifest "started_at=${started}"

  set +e
  ( "$@" ) 2>&1 | tee "${ARTIFACT_DIR}/${slug}.log"
  rc="${PIPESTATUS[0]}"
  set -e

  finished="$(utc_now)"
  record_manifest "finished_at=${finished}"
  record_manifest "exit_code=${rc}"
  record_manifest "---"

  if [ "${rc}" -ne 0 ]; then
    printf 'Stage failed: %s (exit %s)\n' "${label}" "${rc}"
  fi
  return "${rc}"
}

load_uv() {
  export PATH="${HOME}/.local/bin:${PATH}"
  command -v uv >/dev/null
}

load_node() {
  export NVM_DIR="${HOME}/.nvm"
  # shellcheck disable=SC1091
  . "${NVM_DIR}/nvm.sh" --no-use
  nvm use --silent 24 >/dev/null
  test "$(node -p 'process.versions.node.split(".")[0]')" = "24"
}

finalize() {
  local rc="$?"
  local cleanup_rc=0
  trap - EXIT
  set +e

  {
    echo "finished_at=$(utc_now)"
    echo "script_exit_code_before_cleanup=${rc}"
    echo "circle_build_url=${CIRCLE_BUILD_URL:-unset}"
    echo "circle_workflow_id=${CIRCLE_WORKFLOW_ID:-unset}"
    echo "circle_sha1=${CIRCLE_SHA1:-unset}"
  } > "${ARTIFACT_DIR}/final-summary.txt"

  git -C "${PROOF_ROOT}" status --short --untracked-files=all \
    > "${ARTIFACT_DIR}/final-proof-repository-status.txt" 2>&1
  git -C "${PROOF_ROOT}" rev-parse HEAD \
    > "${ARTIFACT_DIR}/final-proof-repository-head.txt" 2>&1
  git -C "${PROOF_ROOT}" rev-parse 'HEAD^{tree}' \
    > "${ARTIFACT_DIR}/final-proof-repository-tree.txt" 2>&1

  if git -C "${CANDIDATE_DIR}" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "${CANDIDATE_DIR}" status --short --untracked-files=all \
      > "${ARTIFACT_DIR}/final-candidate-status.txt" 2>&1
    git -C "${CANDIDATE_DIR}" rev-parse HEAD \
      > "${ARTIFACT_DIR}/final-candidate-head.txt" 2>&1
    git -C "${CANDIDATE_DIR}" rev-parse 'HEAD^{tree}' \
      > "${ARTIFACT_DIR}/final-candidate-tree.txt" 2>&1
    git -C "${CANDIDATE_DIR}" diff --stat \
      > "${ARTIFACT_DIR}/final-candidate-diff-stat.txt" 2>&1
    git -C "${CANDIDATE_DIR}" diff --cached --stat \
      > "${ARTIFACT_DIR}/final-candidate-cached-diff-stat.txt" 2>&1
  fi

  if docker inspect "${POSTGRES_CONTAINER}" >/dev/null 2>&1; then
    docker inspect "${POSTGRES_CONTAINER}" \
      > "${ARTIFACT_DIR}/postgres-container-inspect.json" 2>&1
    docker logs "${POSTGRES_CONTAINER}" \
      > "${ARTIFACT_DIR}/postgres-container.log" 2>&1
    docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d postgres -Atc \
      "select datname from pg_database where datname like 'linguagraph_%' order by datname;" \
      > "${ARTIFACT_DIR}/final-disposable-databases.txt" 2>&1

    docker rm -f "${POSTGRES_CONTAINER}" >/dev/null 2>&1
    cleanup_rc="$?"
    echo "postgres_container_cleanup_exit_code=${cleanup_rc}" \
      >> "${ARTIFACT_DIR}/final-summary.txt"
    if [ "${rc}" -eq 0 ] && [ "${cleanup_rc}" -ne 0 ]; then
      rc=1
    fi
  else
    echo "postgres_container_cleanup=not_present" \
      >> "${ARTIFACT_DIR}/final-summary.txt"
  fi

  if [ -d "${CANDIDATE_DIR}/apps/web/test-results" ]; then
    tar -czf "${ARTIFACT_DIR}/playwright-test-results.tgz" \
      -C "${CANDIDATE_DIR}/apps/web" test-results
  fi

  echo "proof_exit_code=${rc}" >> "${ARTIFACT_DIR}/final-summary.txt"
  if [ "${rc}" -eq 0 ]; then
    echo "proof_result=PASS" >> "${ARTIFACT_DIR}/final-summary.txt"
  else
    echo "proof_result=FAIL" >> "${ARTIFACT_DIR}/final-summary.txt"
  fi

  (
    cd "${ARTIFACT_DIR}"
    find . -type f ! -name artifact-manifest.sha256 -print0 \
      | sort -z \
      | xargs -0 sha256sum \
      > artifact-manifest.sha256
  )

  exit "${rc}"
}

trap finalize EXIT

require_environment() {
  local name
  for name in \
    EXPECTED_PROOF_REPOSITORY \
    EXPECTED_PROOF_BRANCH \
    CANDIDATE_REPOSITORY_URL \
    EXPECTED_CANDIDATE_REPOSITORY \
    EXPECTED_CANDIDATE_BRANCH \
    EXPECTED_CANDIDATE_SHA \
    EXPECTED_CANDIDATE_TREE \
    DATABASE_URL \
    TEST_DATABASE_URL \
    CIRCLE_PROJECT_USERNAME \
    CIRCLE_PROJECT_REPONAME \
    CIRCLE_BRANCH \
    CIRCLE_SHA1; do
    test -n "${!name:-}" || {
      echo "Required environment variable is missing: ${name}"
      return 1
    }
  done
}

capture_environment() {
  {
    echo "captured_at=$(utc_now)"
    uname -a
    echo
    cat /etc/os-release
    echo
    echo "architecture=$(uname -m)"
    echo "processor_count=$(getconf _NPROCESSORS_ONLN)"
    free -h
    df -h .
    docker version
  } | tee "${ARTIFACT_DIR}/environment.txt"
}

verify_proof_source() {
  local actual_repository actual_head actual_tree
  actual_repository="${CIRCLE_PROJECT_USERNAME}/${CIRCLE_PROJECT_REPONAME}"
  actual_head="$(git -C "${PROOF_ROOT}" rev-parse HEAD)"
  actual_tree="$(git -C "${PROOF_ROOT}" rev-parse 'HEAD^{tree}')"

  printf '%s\n' \
    "expected_proof_repository=${EXPECTED_PROOF_REPOSITORY}" \
    "actual_proof_repository=${actual_repository}" \
    "expected_proof_branch=${EXPECTED_PROOF_BRANCH}" \
    "actual_proof_branch=${CIRCLE_BRANCH}" \
    "circle_sha1=${CIRCLE_SHA1}" \
    "proof_head=${actual_head}" \
    "proof_tree=${actual_tree}" \
    "proof_origin=$(git -C "${PROOF_ROOT}" remote get-url origin)" \
    | tee "${ARTIFACT_DIR}/proof-provenance.txt"

  test "${actual_repository}" = "${EXPECTED_PROOF_REPOSITORY}"
  test "${CIRCLE_BRANCH}" = "${EXPECTED_PROOF_BRANCH}"
  test "${actual_head}" = "${CIRCLE_SHA1}"
  test -f "${PROOF_ROOT}/.circleci/config.yml"
  test -f "${PROOF_ROOT}/scripts/run-m3-proof.sh"
  test -z "$(git -C "${PROOF_ROOT}" status --porcelain --untracked-files=no)"
}

checkout_candidate() {
  local remote_line remote_sha remote_ref actual_head actual_tree
  test ! -e "${CANDIDATE_DIR}"

  git init "${CANDIDATE_DIR}"
  git -C "${CANDIDATE_DIR}" remote add origin "${CANDIDATE_REPOSITORY_URL}"

  remote_line="$(git -C "${CANDIDATE_DIR}" ls-remote --refs origin "refs/heads/${EXPECTED_CANDIDATE_BRANCH}")"
  test -n "${remote_line}"
  read -r remote_sha remote_ref <<< "${remote_line}"
  test "${remote_ref}" = "refs/heads/${EXPECTED_CANDIDATE_BRANCH}"
  test "${remote_sha}" = "${EXPECTED_CANDIDATE_SHA}"

  git -C "${CANDIDATE_DIR}" fetch --no-tags --depth=1 origin \
    "refs/heads/${EXPECTED_CANDIDATE_BRANCH}:refs/remotes/origin/${EXPECTED_CANDIDATE_BRANCH}"
  test "$(git -C "${CANDIDATE_DIR}" rev-parse "refs/remotes/origin/${EXPECTED_CANDIDATE_BRANCH}")" \
    = "${EXPECTED_CANDIDATE_SHA}"
  git -C "${CANDIDATE_DIR}" -c advice.detachedHead=false checkout --detach \
    "${EXPECTED_CANDIDATE_SHA}"

  actual_head="$(git -C "${CANDIDATE_DIR}" rev-parse HEAD)"
  actual_tree="$(git -C "${CANDIDATE_DIR}" rev-parse 'HEAD^{tree}')"

  printf '%s\n' \
    "expected_candidate_repository=${EXPECTED_CANDIDATE_REPOSITORY}" \
    "candidate_origin=$(git -C "${CANDIDATE_DIR}" remote get-url origin)" \
    "expected_candidate_branch=${EXPECTED_CANDIDATE_BRANCH}" \
    "remote_candidate_branch_sha=${remote_sha}" \
    "expected_candidate_sha=${EXPECTED_CANDIDATE_SHA}" \
    "candidate_head=${actual_head}" \
    "expected_candidate_tree=${EXPECTED_CANDIDATE_TREE}" \
    "candidate_tree=${actual_tree}" \
    "candidate_object_type=$(git -C "${CANDIDATE_DIR}" cat-file -t "${actual_head}")" \
    | tee "${ARTIFACT_DIR}/candidate-provenance.txt"

  test "${actual_head}" = "${EXPECTED_CANDIDATE_SHA}"
  test "${actual_tree}" = "${EXPECTED_CANDIDATE_TREE}"
  test -z "$(git -C "${CANDIDATE_DIR}" status --porcelain)"

  if git -C "${CANDIDATE_DIR}" cat-file -e \
    "${EXPECTED_CANDIDATE_SHA}:.circleci/config.yml" 2>/dev/null; then
    echo "Candidate unexpectedly contains the external CircleCI configuration."
    return 1
  fi
}

install_uv_python() {
  curl -LsSf https://astral.sh/uv/install.sh | sh
  load_uv
  uv python install 3.13

  local python_bin python_version
  python_bin="$(uv python find 3.13)"
  python_version="$("${python_bin}" -c 'import platform, sys; assert sys.version_info[:2] == (3, 13); print(platform.python_version())')"

  printf 'uv=%s\npython=%s\n' "$(uv --version)" "${python_version}" \
    | tee -a "${ARTIFACT_DIR}/runtime-versions.txt"
}

install_node() {
  export NVM_DIR="${HOME}/.nvm"
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.7/install.sh | bash
  # shellcheck disable=SC1091
  . "${NVM_DIR}/nvm.sh" --no-use
  nvm install 24
  nvm use --silent 24 >/dev/null

  local node_version node_major npm_version
  node_version="$(node --version)"
  node_major="$(node -p 'process.versions.node.split(".")[0]')"
  npm_version="$(npm --version)"
  test "${node_major}" = "24"

  printf 'node=%s\nnpm=%s\n' "${node_version}" "${npm_version}" \
    | tee -a "${ARTIFACT_DIR}/runtime-versions.txt"
}

start_postgresql() {
  docker pull postgres:18
  docker run --detach \
    --name "${POSTGRES_CONTAINER}" \
    --env POSTGRES_USER=postgres \
    --env POSTGRES_PASSWORD=postgres \
    --env POSTGRES_DB=postgres \
    --publish 5432:5432 \
    postgres:18

  local ready=0 attempt postgres_version client_version image_id image_digest
  for attempt in $(seq 1 30); do
    if docker exec "${POSTGRES_CONTAINER}" pg_isready -U postgres -d postgres >/dev/null 2>&1; then
      ready=1
      break
    fi
    sleep 2
  done
  test "${ready}" = "1"

  postgres_version="$(docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d postgres -Atc 'show server_version')"
  client_version="$(docker exec "${POSTGRES_CONTAINER}" psql --version)"
  case "${postgres_version}" in
    18.*) ;;
    *)
      echo "PostgreSQL major-version mismatch: ${postgres_version}"
      return 1
      ;;
  esac

  image_id="$(docker image inspect postgres:18 --format '{{.Id}}')"
  image_digest="$(docker image inspect postgres:18 --format '{{join .RepoDigests ","}}')"
  printf 'postgresql=%s\npostgresql_client=%s\npostgres_image_id=%s\npostgres_image_digest=%s\n' \
    "${postgres_version}" "${client_version}" "${image_id}" "${image_digest}" \
    | tee -a "${ARTIFACT_DIR}/runtime-versions.txt"
}

capture_lock_hashes() {
  local phase="$1"
  {
    echo "phase=${phase}"
    sha256sum \
      "${CANDIDATE_DIR}/apps/api/pyproject.toml" \
      "${CANDIDATE_DIR}/apps/api/uv.lock" \
      "${CANDIDATE_DIR}/apps/web/package.json" \
      "${CANDIDATE_DIR}/apps/web/package-lock.json"
    echo "---"
  } | tee -a "${ARTIFACT_DIR}/dependency-lock-hashes.txt"
}

backend_sync() {
  load_uv
  cd "${CANDIDATE_DIR}/apps/api"
  uv sync --frozen
  uv run python -c \
    'import platform, sys; assert sys.version_info[:2] == (3, 13); print("backend-python=" + platform.python_version())'
}

migration_safety() {
  load_uv
  cd "${CANDIDATE_DIR}/apps/api"

  echo "public_tables_before=$(docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d postgres -Atc \
    "select count(*) from information_schema.tables where table_schema = 'public';")"
  uv run alembic upgrade head
  uv run alembic current | tee "${ARTIFACT_DIR}/alembic-current.txt"
  grep -q "0004 (head)" "${ARTIFACT_DIR}/alembic-current.txt"
  uv run alembic check
  echo "public_tables_after=$(docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d postgres -Atc \
    "select count(*) from information_schema.tables where table_schema = 'public';")"
}

backend_tests() {
  load_uv
  cd "${CANDIDATE_DIR}/apps/api"
  uv run pytest -q
}

zero_skip_guard() {
  if grep -qi "skipped" "${ARTIFACT_DIR}/backend-tests.log"; then
    echo "Backend suite reported skipped tests; real-PostgreSQL proof is invalid."
    return 1
  fi
  tail -10 "${ARTIFACT_DIR}/backend-tests.log"
}

frontend_install() {
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  npm ci
}

frontend_lint() {
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  npm run lint
}

frontend_typecheck() {
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  npm run typecheck
}

frontend_tests() {
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  npm run test
}

frontend_build() {
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  npm run build
}

playwright_install() {
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  npx playwright install --with-deps chromium
}

playwright_e2e() {
  load_uv
  load_node
  cd "${CANDIDATE_DIR}/apps/web"
  CI=1 npx playwright test e2e/golden-path.spec.ts e2e/unicode.spec.ts e2e/segmentation.spec.ts e2e/token-segmentation.spec.ts
}

prove_disposable_cleanup() {
  local leftovers
  leftovers="$(docker exec "${POSTGRES_CONTAINER}" psql -U postgres -d postgres -Atc \
    "select datname from pg_database where datname like 'linguagraph_%' order by datname;")"
  printf '%s\n' "${leftovers}" | tee "${ARTIFACT_DIR}/post-e2e-databases.txt"
  if [ -n "${leftovers}" ]; then
    echo "Disposable LinguaGraph databases remain after E2E."
    return 1
  fi
}

verify_final_integrity() {
  local final_remote_line final_remote_sha final_remote_ref actual_head actual_tree
  final_remote_line="$(git -C "${CANDIDATE_DIR}" ls-remote --refs origin \
    "refs/heads/${EXPECTED_CANDIDATE_BRANCH}")"
  read -r final_remote_sha final_remote_ref <<< "${final_remote_line}"

  actual_head="$(git -C "${CANDIDATE_DIR}" rev-parse HEAD)"
  actual_tree="$(git -C "${CANDIDATE_DIR}" rev-parse 'HEAD^{tree}')"

  printf '%s\n' \
    "final_remote_ref=${final_remote_ref}" \
    "final_remote_branch_sha=${final_remote_sha}" \
    "expected_candidate_sha=${EXPECTED_CANDIDATE_SHA}" \
    "final_candidate_head=${actual_head}" \
    "expected_candidate_tree=${EXPECTED_CANDIDATE_TREE}" \
    "final_candidate_tree=${actual_tree}" \
    | tee "${ARTIFACT_DIR}/final-integrity.txt"

  git -C "${CANDIDATE_DIR}" status --short --untracked-files=all \
    | tee "${ARTIFACT_DIR}/candidate-status-after-proof.txt"

  test "${final_remote_ref}" = "refs/heads/${EXPECTED_CANDIDATE_BRANCH}"
  test "${final_remote_sha}" = "${EXPECTED_CANDIDATE_SHA}"
  test "${actual_head}" = "${EXPECTED_CANDIDATE_SHA}"
  test "${actual_tree}" = "${EXPECTED_CANDIDATE_TREE}"
  test -z "$(git -C "${CANDIDATE_DIR}" status --porcelain --untracked-files=no)"
  git -C "${CANDIDATE_DIR}" diff --quiet
  git -C "${CANDIDATE_DIR}" diff --cached --quiet
  test -z "$(git -C "${PROOF_ROOT}" status --porcelain --untracked-files=no)"
}

run_stage "environment-contract" "Environment — required variables" require_environment
run_stage "environment" "Environment — hosted Linux manifest" capture_environment
run_stage "proof-provenance" "Provenance — proof repository" verify_proof_source
run_stage "candidate-checkout" "Provenance — exact candidate checkout" checkout_candidate
run_stage "dependency-hashes-before" "Integrity — dependency hashes before execution" capture_lock_hashes before
run_stage "runtime-python" "Runtime — uv and Python 3.13" install_uv_python
run_stage "runtime-node" "Runtime — Node 24" install_node
run_stage "runtime-postgresql" "Runtime — PostgreSQL 18" start_postgresql
run_stage "backend-sync" "Backend — uv sync --frozen" backend_sync
run_stage "migration" "Backend — Alembic empty to 0004 head/current/check" migration_safety
run_stage "backend-tests" "Backend — full real-PostgreSQL pytest suite" backend_tests
run_stage "backend-zero-skip" "Backend — zero skipped-test guard" zero_skip_guard
run_stage "frontend-install" "Frontend — npm ci" frontend_install
run_stage "frontend-lint" "Frontend — lint" frontend_lint
run_stage "frontend-typecheck" "Frontend — typecheck" frontend_typecheck
run_stage "frontend-tests" "Frontend — Vitest/RTL" frontend_tests
run_stage "frontend-build" "Frontend — production build" frontend_build
run_stage "playwright-install" "E2E — install Chromium and system dependencies" playwright_install
run_stage "playwright-e2e" "E2E — golden path, Unicode release blocker, and M3 segmentation" playwright_e2e
run_stage "database-cleanup" "E2E — prove disposable database cleanup" prove_disposable_cleanup
run_stage "dependency-hashes-after" "Integrity — dependency hashes after execution" capture_lock_hashes after
run_stage "final-integrity" "Integrity — candidate and proof source preserved" verify_final_integrity

echo "All M3 exact-candidate semantic gates completed successfully."
