#!/bin/bash
# SPDX-FileCopyrightText: 2026 Harald Pretl
# Johannes Kepler University, Department for Integrated Circuits
# SPDX-License-Identifier: Apache-2.0
#
# Regression test for EDA server shared-mount defaults and container UID mapping.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONF_PATH="$ROOT_DIR/eda_server_conf.sh"
START_VNC_PATH="$ROOT_DIR/start_vnc.sh"
UTILS_PATH="$ROOT_DIR/eda_server_utils.sh"

if [[ ! -f "$CONF_PATH" ]]; then
    echo "[ERROR] Missing config script: $CONF_PATH"
    exit 1
fi

if [[ ! -f "$UTILS_PATH" ]]; then
    echo "[ERROR] Missing helper script: $UTILS_PATH"
    exit 1
fi

if [[ ! -f "$START_VNC_PATH" ]]; then
    echo "[ERROR] Missing VNC start script: $START_VNC_PATH"
    exit 1
fi

mapfile -t conf_values < <(
    HOME=/tmp/iic-osic-tools-test-home \
    bash -lc "unset EDA_USER_HOME COMMON_DESIGNS EDA_CREDENTIAL_FILE; source '$CONF_PATH'; printf '%s\n' \"\$EDA_USER_HOME\" \"\$COMMON_DESIGNS\" \"\$EDA_CREDENTIAL_FILE\""
)

expected_user_home="$ROOT_DIR/eda"
expected_common_designs="$ROOT_DIR/eda/common"
expected_credentials="$ROOT_DIR/eda_user_credentials.json"

if [[ "${conf_values[0]}" != "$expected_user_home" ]]; then
    echo "[ERROR] EDA_USER_HOME defaulted to '${conf_values[0]}', expected '$expected_user_home'."
    exit 1
fi

if [[ "${conf_values[1]}" != "$expected_common_designs" ]]; then
    echo "[ERROR] COMMON_DESIGNS defaulted to '${conf_values[1]}', expected '$expected_common_designs'."
    exit 1
fi

if [[ "${conf_values[2]}" != "$expected_credentials" ]]; then
    echo "[ERROR] EDA_CREDENTIAL_FILE defaulted to '${conf_values[2]}', expected '$expected_credentials'."
    exit 1
fi

container_uid="$(
    bash -lc "source '$UTILS_PATH'; eda_server_container_user_from_username u50001"
)"

if [[ "$container_uid" != "50001" ]]; then
    echo "[ERROR] Unexpected container UID '$container_uid' for username u50001."
    exit 1
fi

if bash -lc "source '$UTILS_PATH'; eda_server_container_user_from_username designer" >/dev/null 2>&1; then
    echo "[ERROR] Invalid usernames must not resolve to a container UID."
    exit 1
fi

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/bin"
fake_log="$tmp_dir/docker-run.log"
designs_dir="$tmp_dir/designs"
common_dir="$tmp_dir/common"

mkdir -p "$fake_bin" "$designs_dir" "$common_dir"

cat > "$fake_bin/docker" <<EOF
#!/bin/bash
case "\$1" in
    ps)
        exit 0
        ;;
    run)
        printf '%s\n' "\$@" > "$fake_log"
        exit 0
        ;;
    *)
        exit 0
        ;;
esac
EOF
chmod +x "$fake_bin/docker"

bash -lc "PATH='$fake_bin':\$PATH DESIGNS='$designs_dir' COMMON_DESIGNS='$common_dir' WEBSERVER_PORT=0 VNC_PORT=0 CONTAINER_NAME=test-common-mount source '$START_VNC_PATH'"

if ! grep -q 'dst=/foss/common,readonly' "$fake_log"; then
    echo "[ERROR] COMMON_DESIGNS was not mounted at /foss/common."
    exit 1
fi

if grep -q 'dst=/foss/designs/common,readonly' "$fake_log"; then
    echo "[ERROR] COMMON_DESIGNS must not be mounted under /foss/designs."
    exit 1
fi

echo "[INFO] Test <EDA server common mount defaults> passed."
