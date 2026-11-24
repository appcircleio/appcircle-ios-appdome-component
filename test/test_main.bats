#!/usr/bin/env bats
#
# Unit tests for main.sh (Appdome Build-2Secure for iOS step).
#
#   bats test/
#
# `download_file` is tested in-process: main.sh is sourced (the source guard
# stops before the step runs) and `curl` is replaced by a shell function.
#
# The whole step is run as a subprocess with a clean environment (`env -i`):
#   - It runs inside a per-test tmpdir, so the `appdome-api-bash` checkout,
#     downloaded app files and the env file all stay inside BATS_TEST_TMPDIR.
#   - Stub `git` and `curl` are first on PATH. `git clone` creates a local
#     `appdome-api-bash/appdome_api.sh` stub instead of cloning, and `curl`
#     writes a dummy file instead of downloading. No network, no Appdome API.
#   - The `appdome_api.sh` stub records each argument on its own line, so the
#     composed command can be asserted exactly (including empty arguments).

bats_require_minimum_version 1.5.0

MAIN_SH="${BATS_TEST_DIRNAME}/../main.sh"

setup() {
  WORK="${BATS_TEST_TMPDIR}/work"
  STEP_DIR="${WORK}/step"
  APP_DIR="${WORK}/app"
  OUT_DIR="${WORK}/output"
  FAKE_HOME="${WORK}/home"
  FAKE_BIN="${WORK}/bin"
  STUB_SRC="${WORK}/stub-src"
  CALLS="${WORK}/calls.log"
  ARGS="${WORK}/appdome_args.log"
  APPDOME_PWD="${WORK}/appdome_pwd.log"
  ENV_FILE="${WORK}/ac_env"
  BASH_BIN="$(command -v bash)"
  mkdir -p "$STEP_DIR" "$APP_DIR" "$OUT_DIR" "$FAKE_HOME" "$FAKE_BIN" "$STUB_SRC"
  : > "$CALLS"

  # appdome_api.sh: records its arguments (one per line) and working directory.
  cat > "${STUB_SRC}/appdome_api.sh" <<'STUB'
#!/bin/bash
printf '%s\n' "$@" > "$STUB_APPDOME_ARGS"
pwd > "$STUB_APPDOME_PWD"
echo "appdome_api.sh $*" >> "$STUB_CALLS"
if [ -n "$STUB_APPDOME_EXIT" ]; then
  echo "appdome_api.sh: stub failure" >&2
  exit "$STUB_APPDOME_EXIT"
fi
echo "Appdome stub: build finished"
STUB

  # git: `git clone <url>` creates the appdome-api-bash checkout from the stub.
  cat > "${FAKE_BIN}/git" <<'STUB'
#!/bin/bash
echo "git $*" >> "$STUB_CALLS"
if [ -n "$STUB_GIT_EXIT" ]; then
  echo "fatal: stub clone failure" >&2
  exit "$STUB_GIT_EXIT"
fi
if [ "$1" = "clone" ]; then
  mkdir -p appdome-api-bash
  cp "$STUB_APPDOME_SRC" appdome-api-bash/appdome_api.sh
  chmod +x appdome-api-bash/appdome_api.sh
  echo "Cloning into 'appdome-api-bash'..."
fi
STUB

  # curl: logs its arguments and writes a dummy file to the --output path.
  cat > "${FAKE_BIN}/curl" <<'STUB'
#!/bin/bash
echo "curl $*" >> "$STUB_CALLS"
if [ -n "$STUB_CURL_EXIT" ]; then
  echo "curl: (6) Could not resolve host" >&2
  exit "$STUB_CURL_EXIT"
fi
out=""
while [ $# -gt 0 ]; do
  if [ "$1" = "--output" ]; then out="$2"; shift; fi
  shift
done
[ -n "$out" ] && echo "dummy-app" > "$out"
exit 0
STUB

  chmod +x "${FAKE_BIN}/git" "${FAKE_BIN}/curl"

  APP_IPA="${APP_DIR}/MyApp.ipa"
  PROFILE="${APP_DIR}/profile.mobileprovision"
  CERT="${APP_DIR}/cert.p12"

  # A valid On-Appdome configuration. Tests override or drop single entries.
  BASE_ENV=(
    "AC_APPDOME_IPA_PATH=${APP_IPA}"
    "AC_APPDOME_API_KEY=test-api-key"
    "AC_APPDOME_FUSION_SET_ID=fusion-123"
    "AC_APPDOME_SIGN_METHOD=On-Appdome"
    "AC_APPDOME_PROVISIONING_PROFILES=${PROFILE}"
    "AC_APPDOME_CERTIFICATES=${CERT}"
    "AC_APPDOME_CERTIFICATES_PASS=p12-pass"
    "AC_OUTPUT_DIR=${OUT_DIR}"
    "AC_ENV_FILE_PATH=${ENV_FILE}"
  )
}

# run_step [-u NAME]... [NAME=value]...
# Runs main.sh with BASE_ENV, minus every `-u NAME`, plus the given overrides
# (a later NAME=value wins over the BASE_ENV entry).
run_step() {
  local drop=() env_args=() kv name skip
  while [ "$1" = "-u" ]; do
    drop+=("$2")
    shift 2
  done
  for kv in "${BASE_ENV[@]}"; do
    skip=""
    for name in "${drop[@]}"; do
      if [[ "$kv" == "${name}="* ]]; then skip=1; fi
    done
    if [ -z "$skip" ]; then env_args+=("$kv"); fi
  done

  cd "$STEP_DIR"
  run --separate-stderr env -i \
    HOME="$FAKE_HOME" \
    PATH="${FAKE_BIN}:/usr/bin:/bin" \
    STUB_CALLS="$CALLS" \
    STUB_APPDOME_SRC="${STUB_SRC}/appdome_api.sh" \
    STUB_APPDOME_ARGS="$ARGS" \
    STUB_APPDOME_PWD="$APPDOME_PWD" \
    "${env_args[@]}" \
    "$@" \
    "$BASH_BIN" "$MAIN_SH"
}

# assert_appdome_args ARG...
# The appdome_api.sh stub was called with exactly these arguments, in order.
assert_appdome_args() {
  local expected actual
  expected="$(printf '%s\n' "$@")"
  actual="$(cat "$ARGS")"
  if [ "$expected" != "$actual" ]; then
    echo "expected appdome_api.sh args:"
    echo "$expected"
    echo "actual appdome_api.sh args:"
    echo "$actual"
    return 1
  fi
}

# arg_after FLAG: prints the argument that follows FLAG in the appdome_api.sh call.
arg_after() {
  awk -v flag="$1" 'found { print; exit } $0 == flag { found = 1 }' "$ARGS"
}

# has_arg FLAG: FLAG is one of the appdome_api.sh arguments.
has_arg() {
  grep -qxF -- "$1" "$ARGS"
}

# Assertion helpers. On bash 3.2 (macOS /bin/bash) a failing `[[ ... ]]` or
# `! cmd` line does not stop a bats test, so these return non-zero explicitly.

# assert_contains HAYSTACK NEEDLE
assert_contains() {
  case "$1" in
    *"$2"*) return 0 ;;
  esac
  echo "expected to contain: $2"
  echo "actual: $1"
  return 1
}

# refute_contains HAYSTACK NEEDLE
refute_contains() {
  case "$1" in
    *"$2"*)
      echo "expected not to contain: $2"
      echo "actual: $1"
      return 1
      ;;
  esac
  return 0
}

# refute CMD...: CMD must fail.
refute() {
  if "$@"; then
    echo "expected to fail: $*"
    return 1
  fi
  return 0
}

# Loads main.sh into the test shell and replaces curl with a recording function.
# STUB_CURL_EXIT makes the replacement fail with that code.
load_download_file() {
  source "$MAIN_SH"
  curl() {
    printf '%s\n' "$@" > "$CALLS"
    if [ -n "$STUB_CURL_EXIT" ]; then
      echo "curl: stub failure" >&2
      return "$STUB_CURL_EXIT"
    fi
    return 0
  }
}

# ---------------------------------------------------------------------------
# Loading contract
# ---------------------------------------------------------------------------

@test "sourcing main.sh returns 0, defines download_file and does not run the step" {
  cd "$STEP_DIR"
  run --separate-stderr env -i HOME="$FAKE_HOME" PATH="${FAKE_BIN}:/usr/bin:/bin" \
    STUB_CALLS="$CALLS" STUB_APPDOME_SRC="${STUB_SRC}/appdome_api.sh" \
    STUB_APPDOME_ARGS="$ARGS" STUB_APPDOME_PWD="$APPDOME_PWD" \
    "${BASE_ENV[@]}" AC_APPDOME_IPA_PATH="https://example.com/MyApp.ipa" \
    "$BASH_BIN" -c 'source "$1"; echo "source-status=$?"; type -t download_file' _ "$MAIN_SH"

  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "source-status=0" ]
  [ "${lines[1]}" = "function" ]
  [ "${#lines[@]}" -eq 2 ]
  [ ! -s "$CALLS" ]
  [ ! -e "${STEP_DIR}/appdome-api-bash" ]
  [ ! -e "$ENV_FILE" ]
}

# ---------------------------------------------------------------------------
# download_file
# ---------------------------------------------------------------------------

@test "download_file: URL with query string downloads to the file name without the query" {
  load_download_file

  run --separate-stderr download_file "https://cdn.example.com/builds/MyApp.ipa?token=abc&exp=1"

  [ "$status" -eq 0 ]
  [ "$output" = "MyApp.ipa" ]
  [ "$(cat "$CALLS")" = "$(printf '%s\n' -L 'https://cdn.example.com/builds/MyApp.ipa?token=abc&exp=1' --output MyApp.ipa)" ]
}

@test "download_file: URL without query string uses its last path segment" {
  load_download_file

  run --separate-stderr download_file "http://example.com/path/to/Release.ipa"

  [ "$status" -eq 0 ]
  [ "$output" = "Release.ipa" ]
  [ "$(cat "$CALLS")" = "$(printf '%s\n' -L 'http://example.com/path/to/Release.ipa' --output Release.ipa)" ]
}

@test "download_file: query string is cut at the first '?'" {
  load_download_file

  run --separate-stderr download_file "https://example.com/a/App.ipa?x=1?y=2"

  [ "$status" -eq 0 ]
  [ "$output" = "App.ipa" ]
}

@test "download_file: the file is written to the current directory" {
  cd "$STEP_DIR"
  source "$MAIN_SH"
  export STUB_CALLS="$CALLS"
  PATH="${FAKE_BIN}:${PATH}"

  run --separate-stderr download_file "https://example.com/dl/MyApp.ipa?sig=1"

  [ "$status" -eq 0 ]
  [ "$output" = "MyApp.ipa" ]
  [ "$(cat "${STEP_DIR}/MyApp.ipa")" = "dummy-app" ]
}

@test "download_file: curl failure returns non-zero and prints no file name" {
  load_download_file
  STUB_CURL_EXIT=1

  run --separate-stderr download_file "https://example.com/MyApp.ipa"

  [ "$status" -ne 0 ]
  [ -z "$output" ]
  assert_contains "$stderr" "curl: stub failure"
}

@test "download_file: curl exit code is returned unchanged" {
  load_download_file
  STUB_CURL_EXIT=22

  run --separate-stderr download_file "https://example.com/MyApp.ipa"

  [ "$status" -eq 22 ]
}

@test "download_file: empty URL passes empty URL and output name to curl" {
  load_download_file

  run --separate-stderr download_file ""

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(cat "$CALLS")" = "$(printf '%s\n' -L '' --output '')" ]
}

@test "download_file: no argument behaves like an empty URL and fails when curl rejects it" {
  load_download_file
  STUB_CURL_EXIT=2

  run --separate-stderr download_file

  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [ "$(cat "$CALLS")" = "$(printf '%s\n' -L '' --output '')" ]
}

# ---------------------------------------------------------------------------
# Signing methods (AC_APPDOME_SIGN_METHOD)
# ---------------------------------------------------------------------------

@test "On-Appdome: calls appdome_api.sh with keystore arguments" {
  run_step

  [ "$status" -eq 0 ]
  assert_contains "$output" "On Appdome Signing"
  assert_appdome_args \
    --api_key test-api-key \
    --app "$APP_IPA" \
    --fusion_set_id fusion-123 \
    --sign_on_appdome \
    --keystore "$CERT" \
    --keystore_pass p12-pass \
    --provisioning_profiles "$PROFILE" \
    --output "${OUT_DIR}/Appdome_MyApp.ipa" \
    --certificate_output "${OUT_DIR}/certificate.pdf"
}

@test "Private-Signing: calls appdome_api.sh without keystore arguments" {
  run_step AC_APPDOME_SIGN_METHOD="Private-Signing"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Private Signing"
  assert_appdome_args \
    --api_key test-api-key \
    --app "$APP_IPA" \
    --fusion_set_id fusion-123 \
    --private_signing \
    --provisioning_profiles "$PROFILE" \
    --output "${OUT_DIR}/Appdome_MyApp.ipa" \
    --certificate_output "${OUT_DIR}/certificate.pdf"
}

@test "Auto-Dev-Signing: calls appdome_api.sh without keystore arguments" {
  run_step AC_APPDOME_SIGN_METHOD="Auto-Dev-Signing"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Auto Dev Signing"
  assert_appdome_args \
    --api_key test-api-key \
    --app "$APP_IPA" \
    --fusion_set_id fusion-123 \
    --auto_dev_private_signing \
    --provisioning_profiles "$PROFILE" \
    --output "${OUT_DIR}/Appdome_MyApp.ipa" \
    --certificate_output "${OUT_DIR}/certificate.pdf"
}

@test "AC_APPDOME_SIGN_METHOD missing: appdome_api.sh is not called but outputs are still exported (current behaviour)" {
  run_step -u AC_APPDOME_SIGN_METHOD

  [ "$status" -eq 0 ]
  [ ! -e "$ARGS" ]
  refute_contains "$output" "Signing"
  grep -qxF "AC_APPDOME_SECURED_IPA_PATH=${OUT_DIR}/Appdome_MyApp.ipa" "$ENV_FILE"
  grep -qxF "AC_APPDOME_CERTIFICATE_PATH=${OUT_DIR}/certificate.pdf" "$ENV_FILE"
}

@test "AC_APPDOME_SIGN_METHOD empty: appdome_api.sh is not called (current behaviour)" {
  run_step AC_APPDOME_SIGN_METHOD=""

  [ "$status" -eq 0 ]
  [ ! -e "$ARGS" ]
  refute_contains "$output" "Signing"
}

@test "AC_APPDOME_SIGN_METHOD unknown value: matching is case-sensitive and nothing is signed" {
  run_step AC_APPDOME_SIGN_METHOD="on-appdome"

  [ "$status" -eq 0 ]
  [ ! -e "$ARGS" ]
}

# ---------------------------------------------------------------------------
# AC_APPDOME_IPA_PATH
# ---------------------------------------------------------------------------

@test "AC_APPDOME_IPA_PATH local path: is passed as-is and nothing is downloaded" {
  run_step

  [ "$status" -eq 0 ]
  [ "$(arg_after --app)" = "$APP_IPA" ]
  [ "$(arg_after --output)" = "${OUT_DIR}/Appdome_MyApp.ipa" ]
  refute grep -q "^curl " "$CALLS"
}

@test "AC_APPDOME_IPA_PATH URL: downloads the app and passes it relative to the clone dir" {
  run_step AC_APPDOME_IPA_PATH="https://cdn.example.com/builds/MyApp.ipa?token=abc"

  [ "$status" -eq 0 ]
  grep -qxF "curl -L https://cdn.example.com/builds/MyApp.ipa?token=abc --output MyApp.ipa" "$CALLS"
  [ "$(arg_after --app)" = "../MyApp.ipa" ]
  [ "$(arg_after --output)" = "${OUT_DIR}/Appdome_MyApp.ipa" ]
  # appdome_api.sh runs inside the clone, so ../MyApp.ipa is the downloaded file.
  [ "$(cat "$(cat "$APPDOME_PWD")/../MyApp.ipa")" = "dummy-app" ]
}

@test "AC_APPDOME_IPA_PATH plain http URL: is downloaded too" {
  run_step AC_APPDOME_IPA_PATH="http://example.com/MyApp.ipa"

  [ "$status" -eq 0 ]
  grep -qxF "curl -L http://example.com/MyApp.ipa --output MyApp.ipa" "$CALLS"
  [ "$(arg_after --app)" = "../MyApp.ipa" ]
}

@test "AC_APPDOME_IPA_PATH local path containing 'http': is treated as a URL (current behaviour)" {
  run_step AC_APPDOME_IPA_PATH="${APP_DIR}/httpdocs/MyApp.ipa"

  [ "$status" -eq 0 ]
  grep -qxF "curl -L ${APP_DIR}/httpdocs/MyApp.ipa --output MyApp.ipa" "$CALLS"
  [ "$(arg_after --app)" = "../MyApp.ipa" ]
}

@test "AC_APPDOME_IPA_PATH URL download fails: step fails before cloning or signing" {
  run_step AC_APPDOME_IPA_PATH="https://example.com/MyApp.ipa" STUB_CURL_EXIT=6

  [ "$status" -ne 0 ]
  assert_contains "$stderr" "Could not resolve host"
  refute grep -q "^git " "$CALLS"
  [ ! -e "$ARGS" ]
  [ ! -e "$ENV_FILE" ]
}

@test "AC_APPDOME_IPA_PATH missing: empty --app is passed and output type is undefined (current behaviour)" {
  run_step -u AC_APPDOME_IPA_PATH

  [ "$status" -eq 0 ]
  has_arg --app
  [ "$(arg_after --app)" = "" ]
  [ "$(arg_after --output)" = "${OUT_DIR}/Appdome_" ]
  assert_contains "$output" "Secured app output type is undefined: ${OUT_DIR}/Appdome_"
  [ "$(cat "$ENV_FILE")" = "AC_APPDOME_CERTIFICATE_PATH=${OUT_DIR}/certificate.pdf" ]
  refute grep -q "^curl " "$CALLS"
}

@test "AC_APPDOME_IPA_PATH empty: empty --app is passed and output type is undefined (current behaviour)" {
  run_step AC_APPDOME_IPA_PATH=""

  [ "$status" -eq 0 ]
  [ "$(arg_after --app)" = "" ]
  assert_contains "$output" "Secured app output type is undefined: ${OUT_DIR}/Appdome_"
  [ "$(cat "$ENV_FILE")" = "AC_APPDOME_CERTIFICATE_PATH=${OUT_DIR}/certificate.pdf" ]
}

# ---------------------------------------------------------------------------
# AC_APPDOME_API_KEY / AC_APPDOME_FUSION_SET_ID
# (required inputs, not validated by main.sh: appdome_api.sh receives them as-is)
# ---------------------------------------------------------------------------

@test "AC_APPDOME_API_KEY missing: an empty --api_key is forwarded to appdome_api.sh" {
  run_step -u AC_APPDOME_API_KEY

  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$ARGS")" = "--api_key" ]
  [ "$(sed -n 2p "$ARGS")" = "" ]
}

@test "AC_APPDOME_API_KEY empty: an empty --api_key is forwarded to appdome_api.sh" {
  run_step AC_APPDOME_API_KEY=""

  [ "$status" -eq 0 ]
  [ "$(arg_after --api_key)" = "" ]
}

@test "AC_APPDOME_API_KEY empty: step fails when appdome_api.sh rejects the call" {
  run_step AC_APPDOME_API_KEY="" STUB_APPDOME_EXIT=1

  [ "$status" -eq 1 ]
  assert_contains "$stderr" "appdome_api.sh: stub failure"
  [ ! -e "$ENV_FILE" ]
}

@test "AC_APPDOME_FUSION_SET_ID missing: an empty --fusion_set_id is forwarded" {
  run_step -u AC_APPDOME_FUSION_SET_ID

  [ "$status" -eq 0 ]
  has_arg --fusion_set_id
  [ "$(arg_after --fusion_set_id)" = "" ]
}

@test "AC_APPDOME_FUSION_SET_ID empty: an empty --fusion_set_id is forwarded" {
  run_step AC_APPDOME_FUSION_SET_ID=""

  [ "$status" -eq 0 ]
  [ "$(arg_after --fusion_set_id)" = "" ]
}

# ---------------------------------------------------------------------------
# AC_APPDOME_TEAM_ID (optional)
# ---------------------------------------------------------------------------

@test "AC_APPDOME_TEAM_ID set: --team_id is added after --fusion_set_id" {
  run_step AC_APPDOME_TEAM_ID="team-42"

  [ "$status" -eq 0 ]
  assert_appdome_args \
    --api_key test-api-key \
    --app "$APP_IPA" \
    --fusion_set_id fusion-123 \
    --team_id team-42 \
    --sign_on_appdome \
    --keystore "$CERT" \
    --keystore_pass p12-pass \
    --provisioning_profiles "$PROFILE" \
    --output "${OUT_DIR}/Appdome_MyApp.ipa" \
    --certificate_output "${OUT_DIR}/certificate.pdf"
}

@test "AC_APPDOME_TEAM_ID set: is used by every signing method" {
  local method
  for method in On-Appdome Private-Signing Auto-Dev-Signing; do
    rm -rf "${STEP_DIR}/appdome-api-bash" "$ARGS"
    run_step AC_APPDOME_SIGN_METHOD="$method" AC_APPDOME_TEAM_ID="team-42"
    [ "$status" -eq 0 ]
    [ "$(arg_after --team_id)" = "team-42" ]
  done
}

@test "AC_APPDOME_TEAM_ID missing: --team_id is not passed" {
  run_step

  [ "$status" -eq 0 ]
  refute has_arg --team_id
}

@test "AC_APPDOME_TEAM_ID empty: --team_id is not passed" {
  run_step AC_APPDOME_TEAM_ID=""

  [ "$status" -eq 0 ]
  refute has_arg --team_id
}

# ---------------------------------------------------------------------------
# AC_APPDOME_IOS_ENTITLEMENTS (optional)
# ---------------------------------------------------------------------------

@test "AC_APPDOME_IOS_ENTITLEMENTS set: --entitlements is added before --output" {
  run_step AC_APPDOME_SIGN_METHOD="Private-Signing" \
    AC_APPDOME_IOS_ENTITLEMENTS="${APP_DIR}/a.plist,${APP_DIR}/b.plist"

  [ "$status" -eq 0 ]
  assert_appdome_args \
    --api_key test-api-key \
    --app "$APP_IPA" \
    --fusion_set_id fusion-123 \
    --private_signing \
    --provisioning_profiles "$PROFILE" \
    --entitlements "${APP_DIR}/a.plist,${APP_DIR}/b.plist" \
    --output "${OUT_DIR}/Appdome_MyApp.ipa" \
    --certificate_output "${OUT_DIR}/certificate.pdf"
}

@test "AC_APPDOME_IOS_ENTITLEMENTS with a space in the path: is split into separate arguments (current behaviour)" {
  run_step AC_APPDOME_IOS_ENTITLEMENTS="${APP_DIR}/My App.plist"

  [ "$status" -eq 0 ]
  [ "$(arg_after --entitlements)" = "${APP_DIR}/My" ]
  has_arg "App.plist"
}

@test "AC_APPDOME_IOS_ENTITLEMENTS missing: --entitlements is not passed" {
  run_step

  [ "$status" -eq 0 ]
  refute has_arg --entitlements
}

@test "AC_APPDOME_IOS_ENTITLEMENTS empty: --entitlements is not passed" {
  run_step AC_APPDOME_IOS_ENTITLEMENTS=""

  [ "$status" -eq 0 ]
  refute has_arg --entitlements
}

# ---------------------------------------------------------------------------
# AC_APPDOME_PROVISIONING_PROFILES
# ---------------------------------------------------------------------------

@test "AC_APPDOME_PROVISIONING_PROFILES pipe separated: is converted to a comma separated list" {
  run_step AC_APPDOME_PROVISIONING_PROFILES="${APP_DIR}/a.mobileprovision|${APP_DIR}/b.mobileprovision"

  [ "$status" -eq 0 ]
  [ "$(arg_after --provisioning_profiles)" = "${APP_DIR}/a.mobileprovision,${APP_DIR}/b.mobileprovision" ]
  assert_contains "$output" "Provision Profile List: ${APP_DIR}/a.mobileprovision,${APP_DIR}/b.mobileprovision"
}

@test "AC_APPDOME_PROVISIONING_PROFILES comma separated: is passed unchanged" {
  run_step AC_APPDOME_PROVISIONING_PROFILES="${APP_DIR}/a.mobileprovision,${APP_DIR}/b.mobileprovision"

  [ "$status" -eq 0 ]
  [ "$(arg_after --provisioning_profiles)" = "${APP_DIR}/a.mobileprovision,${APP_DIR}/b.mobileprovision" ]
}

@test "AC_APPDOME_PROVISIONING_PROFILES missing: an empty --provisioning_profiles is forwarded" {
  run_step -u AC_APPDOME_PROVISIONING_PROFILES

  [ "$status" -eq 0 ]
  has_arg --provisioning_profiles
  [ "$(arg_after --provisioning_profiles)" = "" ]
  assert_contains "$output" "Provision Profile List: "
}

@test "AC_APPDOME_PROVISIONING_PROFILES empty: an empty --provisioning_profiles is forwarded" {
  run_step AC_APPDOME_PROVISIONING_PROFILES=""

  [ "$status" -eq 0 ]
  [ "$(arg_after --provisioning_profiles)" = "" ]
}

# ---------------------------------------------------------------------------
# AC_APPDOME_CERTIFICATES / AC_APPDOME_CERTIFICATES_PASS (used by On-Appdome only)
# ---------------------------------------------------------------------------

@test "AC_APPDOME_CERTIFICATES missing: On-Appdome forwards an empty --keystore" {
  run_step -u AC_APPDOME_CERTIFICATES

  [ "$status" -eq 0 ]
  has_arg --keystore
  [ "$(arg_after --keystore)" = "" ]
}

@test "AC_APPDOME_CERTIFICATES empty: On-Appdome forwards an empty --keystore" {
  run_step AC_APPDOME_CERTIFICATES=""

  [ "$status" -eq 0 ]
  [ "$(arg_after --keystore)" = "" ]
}

@test "AC_APPDOME_CERTIFICATES missing: Private-Signing does not need it" {
  run_step -u AC_APPDOME_CERTIFICATES AC_APPDOME_SIGN_METHOD="Private-Signing"

  [ "$status" -eq 0 ]
  refute has_arg --keystore
  refute has_arg --keystore_pass
}

@test "AC_APPDOME_CERTIFICATES_PASS missing: On-Appdome forwards an empty --keystore_pass" {
  run_step -u AC_APPDOME_CERTIFICATES_PASS

  [ "$status" -eq 0 ]
  has_arg --keystore_pass
  [ "$(arg_after --keystore_pass)" = "" ]
}

@test "AC_APPDOME_CERTIFICATES_PASS empty: On-Appdome forwards an empty --keystore_pass" {
  run_step AC_APPDOME_CERTIFICATES_PASS=""

  [ "$status" -eq 0 ]
  [ "$(arg_after --keystore_pass)" = "" ]
}

@test "AC_APPDOME_CERTIFICATES_PASS with spaces and quotes: is passed as a single argument" {
  run_step AC_APPDOME_CERTIFICATES_PASS='p@ss "word" $HOME'

  [ "$status" -eq 0 ]
  [ "$(arg_after --keystore_pass)" = 'p@ss "word" $HOME' ]
}

# ---------------------------------------------------------------------------
# AC_APPDOME_BUILD_LOGS (read but not used by main.sh)
# ---------------------------------------------------------------------------

@test "AC_APPDOME_BUILD_LOGS set: does not change the appdome_api.sh call" {
  run_step
  local baseline
  baseline="$(cat "$ARGS")"
  rm -rf "${STEP_DIR}/appdome-api-bash" "$ARGS" "$ENV_FILE"

  run_step AC_APPDOME_BUILD_LOGS="true"

  [ "$status" -eq 0 ]
  [ "$(cat "$ARGS")" = "$baseline" ]
}

@test "AC_APPDOME_BUILD_LOGS missing: step succeeds" {
  run_step -u AC_APPDOME_BUILD_LOGS

  [ "$status" -eq 0 ]
  refute has_arg --build_logs
}

@test "AC_APPDOME_BUILD_LOGS empty: step succeeds" {
  run_step AC_APPDOME_BUILD_LOGS=""

  [ "$status" -eq 0 ]
  refute has_arg --build_logs
}

# ---------------------------------------------------------------------------
# Output variables (AC_ENV_FILE_PATH / AC_OUTPUT_DIR)
# ---------------------------------------------------------------------------

@test "outputs: .ipa app exports AC_APPDOME_SECURED_IPA_PATH and AC_APPDOME_CERTIFICATE_PATH" {
  run_step

  [ "$status" -eq 0 ]
  run cat "$ENV_FILE"
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "AC_APPDOME_SECURED_IPA_PATH=${OUT_DIR}/Appdome_MyApp.ipa" ]
  [ "${lines[1]}" = "AC_APPDOME_CERTIFICATE_PATH=${OUT_DIR}/certificate.pdf" ]
}

@test "outputs: .sh output exports AC_APPDOME_PRIVATE_SIGN_SCRIPT_PATH" {
  run_step AC_APPDOME_SIGN_METHOD="Auto-Dev-Signing" AC_APPDOME_IPA_PATH="${APP_DIR}/sign_script.sh"

  [ "$status" -eq 0 ]
  run cat "$ENV_FILE"
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "AC_APPDOME_PRIVATE_SIGN_SCRIPT_PATH=${OUT_DIR}/Appdome_sign_script.sh" ]
  [ "${lines[1]}" = "AC_APPDOME_CERTIFICATE_PATH=${OUT_DIR}/certificate.pdf" ]
}

@test "outputs: unknown output extension only exports AC_APPDOME_CERTIFICATE_PATH" {
  run_step AC_APPDOME_IPA_PATH="${APP_DIR}/MyApp.zip"

  [ "$status" -eq 0 ]
  assert_contains "$output" "Secured app output type is undefined: ${OUT_DIR}/Appdome_MyApp.zip"
  [ "$(cat "$ENV_FILE")" = "AC_APPDOME_CERTIFICATE_PATH=${OUT_DIR}/certificate.pdf" ]
}

@test "outputs: appends to an existing env file without touching earlier lines" {
  printf 'AC_FOO=bar\n' > "$ENV_FILE"

  run_step

  [ "$status" -eq 0 ]
  run cat "$ENV_FILE"
  [ "${#lines[@]}" -eq 3 ]
  [ "${lines[0]}" = "AC_FOO=bar" ]
}

@test "AC_ENV_FILE_PATH missing: fails with non-zero exit after appdome_api.sh ran" {
  run_step -u AC_ENV_FILE_PATH

  [ "$status" -ne 0 ]
  assert_contains "$stderr" "No such file or directory"
  [ -e "$ARGS" ]
}

@test "AC_ENV_FILE_PATH empty: fails with non-zero exit" {
  run_step AC_ENV_FILE_PATH=""

  [ "$status" -ne 0 ]
  assert_contains "$stderr" "No such file or directory"
}

@test "AC_OUTPUT_DIR missing: output paths fall back to the root directory (current behaviour)" {
  run_step -u AC_OUTPUT_DIR

  [ "$status" -eq 0 ]
  [ "$(arg_after --output)" = "/Appdome_MyApp.ipa" ]
  [ "$(arg_after --certificate_output)" = "/certificate.pdf" ]
}

# ---------------------------------------------------------------------------
# External command failures
# ---------------------------------------------------------------------------

@test "git clone: clones the Appdome API repository and runs appdome_api.sh inside it" {
  run_step

  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$CALLS")" = "git clone https://github.com/Appdome/appdome-api-bash.git" ]
  [ "$(cat "$APPDOME_PWD")" = "$(cd "${STEP_DIR}/appdome-api-bash" && pwd -P)" ] ||
    [ "$(cat "$APPDOME_PWD")" = "${STEP_DIR}/appdome-api-bash" ]
}

@test "git clone failure: step fails before appdome_api.sh is called" {
  run_step STUB_GIT_EXIT=128

  [ "$status" -eq 128 ]
  assert_contains "$stderr" "fatal: stub clone failure"
  [ ! -e "$ARGS" ]
  [ ! -e "$ENV_FILE" ]
}

@test "appdome_api.sh failure: its exit code is propagated and no outputs are exported" {
  run_step STUB_APPDOME_EXIT=3

  [ "$status" -eq 3 ]
  assert_contains "$stderr" "appdome_api.sh: stub failure"
  [ ! -e "$ENV_FILE" ]
}

@test "appdome_api.sh failure: Private-Signing also stops the step" {
  run_step AC_APPDOME_SIGN_METHOD="Private-Signing" STUB_APPDOME_EXIT=1

  [ "$status" -eq 1 ]
  [ ! -e "$ENV_FILE" ]
}

@test "appdome_api.sh failure: Auto-Dev-Signing also stops the step" {
  run_step AC_APPDOME_SIGN_METHOD="Auto-Dev-Signing" STUB_APPDOME_EXIT=1

  [ "$status" -eq 1 ]
  [ ! -e "$ENV_FILE" ]
}
