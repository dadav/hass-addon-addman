#!/usr/bin/env bash
# ==============================================================================
# AddMan smoke test
#
# Runs an already-built add-on image against a mock Supervisor API
# (tests/mock_supervisor.py) and asserts that AddMan performs the expected
# reconciliation (add repo -> install add-on -> validate+set options -> start)
# without crashing.
#
# Usage: bash tests/smoke_test.sh [IMAGE]   (default IMAGE: addman-test)
#
# We run addman.sh directly via the `bashio` launcher rather than the image's
# default s6 entrypoint: the base s6 services (banner, log-level, ...) make
# their own Supervisor calls and abort startup against a partial mock. Invoking
# bashio directly exercises the real production script path
# (/usr/bin/addman.sh, same as /etc/services.d/addman/run) in isolation.
#
# The container loops forever, so we stop it once the mock has observed the
# expected calls and deliberately do NOT gate on the container's exit code.
# bashio reads the Supervisor base URL from the SUPERVISOR_API env var and the
# add-on's own options from GET /addons/self/options/config (not /data), so no
# options file needs to be mounted.
# ==============================================================================
set -euo pipefail

IMAGE="${1:-addman-test}"
CONTAINER="addman-smoke"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOCK_PORT="${MOCK_PORT:-8099}"
MOCK_LOG="$(mktemp)"
CONTAINER_LOG="$(mktemp)"
MOCK_PID=""

export MOCK_HOST="127.0.0.1"
export MOCK_PORT
export MOCK_LOG
export MOCK_DRY_RUN=false

cleanup() {
    docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
    [[ -n "${MOCK_PID}" ]] && kill "${MOCK_PID}" >/dev/null 2>&1 || true
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    echo "----- container logs -----" >&2
    cat "${CONTAINER_LOG}" >&2 || true
    echo "----- mock request log -----" >&2
    cat "${MOCK_LOG}" >&2 || true
    exit 1
}

start_mock() {
    echo "Starting mock Supervisor on 127.0.0.1:${MOCK_PORT}..."
    python3 "${SCRIPT_DIR}/mock_supervisor.py" &
    MOCK_PID=$!

    for _ in $(seq 1 30); do
        if curl -fsS "http://127.0.0.1:${MOCK_PORT}/store/repositories" >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done
    curl -fsS "http://127.0.0.1:${MOCK_PORT}/store/repositories" >/dev/null 2>&1 \
        || fail "mock Supervisor did not come up"
}

# ------------------------------------------------------------------------------
# 1. Start the mock Supervisor and wait until it answers.
# ------------------------------------------------------------------------------
start_mock

# ------------------------------------------------------------------------------
# 2. Run the real add-on script against the mock.
# ------------------------------------------------------------------------------
echo "Starting add-on container from image '${IMAGE}'..."
docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
docker run -d --name "${CONTAINER}" --network host \
    --entrypoint /usr/bin/bashio \
    -e "SUPERVISOR_API=http://127.0.0.1:${MOCK_PORT}" \
    -e "SUPERVISOR_TOKEN=test-token" \
    -v "${SCRIPT_DIR}/fixtures/addman.yaml:/config/addman.yaml:ro" \
    "${IMAGE}" /usr/bin/addman.sh >/dev/null

# ------------------------------------------------------------------------------
# 3. Poll the mock log until the key reconciliation calls appear (timeout ~60s).
# ------------------------------------------------------------------------------
echo "Waiting for AddMan to reconcile..."
seen=0
for _ in $(seq 1 60); do
    if grep -q '"POST".*"/store/repositories"' "${MOCK_LOG}" \
        && grep -q '/addons/test_addon/options/validate' "${MOCK_LOG}" \
        && grep -q '/addons/test_addon/start' "${MOCK_LOG}" \
        && grep -q '/addons/absent_addon/uninstall' "${MOCK_LOG}"; then
        seen=1
        break
    fi
    sleep 1
done

docker logs "${CONTAINER}" >"${CONTAINER_LOG}" 2>&1 || true
[[ "${seen}" -eq 1 ]] || fail "expected reconciliation calls did not appear within timeout"

# ------------------------------------------------------------------------------
# 4. Assertions.
# ------------------------------------------------------------------------------
echo "Asserting recorded Supervisor calls..."
grep -q '"POST".*"/store/repositories"' "${MOCK_LOG}" \
    || fail "AddMan did not POST the new repository"
grep -q '"/addons/test_addon/install"' "${MOCK_LOG}" \
    || fail "AddMan did not install test_addon"
grep -q '/addons/test_addon/options/validate' "${MOCK_LOG}" \
    || fail "AddMan did not validate test_addon options"
grep -q '"/addons/test_addon/start"' "${MOCK_LOG}" \
    || fail "AddMan did not start test_addon"
grep -q '"/addons/absent_addon/uninstall"' "${MOCK_LOG}" \
    || fail "AddMan did not uninstall absent_addon (state: absent)"

echo "Asserting container logs..."
grep -qi 'Adding addon repository' "${CONTAINER_LOG}" \
    || fail "log missing 'Adding addon repository'"
grep -qi 'Installing add-on' "${CONTAINER_LOG}" \
    || fail "log missing 'Installing add-on'"
grep -qi 'Starting add-on' "${CONTAINER_LOG}" \
    || fail "log missing 'Starting add-on'"
grep -qi 'Uninstalling add-on' "${CONTAINER_LOG}" \
    || fail "log missing 'Uninstalling add-on'"
if grep -qiE 'crashed|fatal' "${CONTAINER_LOG}"; then
    fail "container reported a crash/fatal error"
fi

echo "PASS: AddMan reconciled the test scenario successfully."

# ------------------------------------------------------------------------------
# 5. Dry-run mode: plan the same scenario but do not mutate Supervisor state.
# ------------------------------------------------------------------------------
docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
kill "${MOCK_PID}" >/dev/null 2>&1 || true
MOCK_PID=""

CONTAINER="addman-smoke-dry-run"
MOCK_LOG="$(mktemp)"
CONTAINER_LOG="$(mktemp)"
MOCK_DRY_RUN=true
export MOCK_LOG
export MOCK_DRY_RUN

start_mock

echo "Starting dry-run add-on container from image '${IMAGE}'..."
docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
docker run -d --name "${CONTAINER}" --network host \
    --entrypoint /usr/bin/bashio \
    -e "SUPERVISOR_API=http://127.0.0.1:${MOCK_PORT}" \
    -e "SUPERVISOR_TOKEN=test-token" \
    -v "${SCRIPT_DIR}/fixtures/addman.yaml:/config/addman.yaml:ro" \
    "${IMAGE}" /usr/bin/addman.sh >/dev/null

echo "Waiting for AddMan dry-run plan..."
seen=0
for _ in $(seq 1 60); do
    docker logs "${CONTAINER}" >"${CONTAINER_LOG}" 2>&1 || true
    if grep -q '\[dry-run\].*Would add addon repository' "${CONTAINER_LOG}" \
        && grep -q '\[dry-run\].*Would install add-on' "${CONTAINER_LOG}" \
        && grep -q '\[dry-run\].*Would uninstall add-on' "${CONTAINER_LOG}"; then
        seen=1
        break
    fi
    sleep 1
done

[[ "${seen}" -eq 1 ]] || fail "expected dry-run plan did not appear within timeout"

echo "Asserting dry-run did not mutate Supervisor state..."
if grep -q '"POST".*"/store/repositories"' "${MOCK_LOG}"; then
    fail "dry-run added a repository"
fi
if grep -q '"/addons/test_addon/install"' "${MOCK_LOG}"; then
    fail "dry-run installed test_addon"
fi
if grep -q '"/addons/test_addon/options"' "${MOCK_LOG}"; then
    fail "dry-run changed test_addon options"
fi
if grep -q '"/addons/test_addon/start"' "${MOCK_LOG}"; then
    fail "dry-run started test_addon"
fi
if grep -q '"/addons/absent_addon/uninstall"' "${MOCK_LOG}"; then
    fail "dry-run uninstalled absent_addon"
fi

grep -q '/addons/test_addon/options/validate' "${MOCK_LOG}" \
    || fail "dry-run did not validate test_addon options"

echo "PASS: AddMan dry-run planned the scenario without mutating state."

# ------------------------------------------------------------------------------
# 6. Empty desired state: missing repositories/addons sections must not crash.
# ------------------------------------------------------------------------------
docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
kill "${MOCK_PID}" >/dev/null 2>&1 || true
MOCK_PID=""

CONTAINER="addman-smoke-no-sections"
MOCK_LOG="$(mktemp)"
CONTAINER_LOG="$(mktemp)"
MOCK_DRY_RUN=false
export MOCK_LOG
export MOCK_DRY_RUN

start_mock

echo "Starting no-sections add-on container from image '${IMAGE}'..."
docker rm -f "${CONTAINER}" >/dev/null 2>&1 || true
docker run -d --name "${CONTAINER}" --network host \
    --entrypoint /usr/bin/bashio \
    -e "SUPERVISOR_API=http://127.0.0.1:${MOCK_PORT}" \
    -e "SUPERVISOR_TOKEN=test-token" \
    -v "${SCRIPT_DIR}/fixtures/no_sections.yaml:/config/addman.yaml:ro" \
    "${IMAGE}" /usr/bin/addman.sh >/dev/null

sleep 3
docker logs "${CONTAINER}" >"${CONTAINER_LOG}" 2>&1 || true

if ! docker inspect -f '{{.State.Running}}' "${CONTAINER}" 2>/dev/null | grep -q true; then
    fail "no-sections config caused the add-on container to stop"
fi
if grep -qiE 'parse error|crashed|fatal' "${CONTAINER_LOG}"; then
    fail "no-sections config produced an error"
fi

echo "PASS: AddMan accepted a config without repositories/addons sections."
