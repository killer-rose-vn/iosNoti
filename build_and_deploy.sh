#!/usr/bin/env bash
#
#  build_and_deploy.sh — build .deb và cài tự động qua SSH lên iPhone jailbreak.
#
#  Dùng:
#    ./build_and_deploy.sh 192.168.1.25
#    ./build_and_deploy.sh 192.168.1.25 22
#    IP=192.168.1.25 PORT=2222 ./build_and_deploy.sh
#
#  Yêu cầu trên máy build (macOS/Linux):
#    - Theos (mặc định /opt/theos, override bằng biến THEOS)
#    - ssh + scp, và đã cài SSH key hoặc biết mật khẩu root của máy (alpine)
#    - make, dpkg-deb (Theos đã kèm)
#
#  Trên iPhone:
#    - OpenSSH đã cài, đăng nhập root được
#    - Jailbreak rootless (Dopamine/palera1n) hoặc rootful — script tự nhận
#
#  Kết quả: ./packages/*.deb được cài, respring tự động.
#

set -euo pipefail

# ------------------------------------------------------------------ cấu hình
DEVICE_IP="${1:-${IP:-}}"
DEVICE_PORT="${2:-${PORT:-22}}"
DEVICE_USER="${USER_OVERRIDE:-root}"

THEOS_DIR="${THEOS:-/opt/theos}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGES_DIR="$PROJECT_DIR/packages"

# Màu cho dễ đọc
if [ -t 1 ]; then
    C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
    C_BLU=$'\033[34m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_BLU=""; C_DIM=""; C_RST=""
fi

step()  { printf '%s==>%s %s\n' "$C_BLU" "$C_RST" "$*"; }
ok()    { printf '%s  ✓%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn()  { printf '%s  !%s %s\n' "$C_YEL" "$C_RST" "$*"; }
die()   { printf '%s  ✗%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }

# ------------------------------------------------------------------ kiểm tra
if [ -z "$DEVICE_IP" ]; then
    cat <<EOF
Cách dùng:
  ./build_and_deploy.sh <IP_iPhone> [PORT]

Ví dụ:
  ./build_and_deploy.sh 192.168.1.25
  IP=192.168.1.25 PORT=2222 ./build_and_deploy.sh

Biến môi trường:
  THEOS          đường dẫn Theos (mặc định /opt/theos)
  USER_OVERRIDE  user SSH (mặc định root)
EOF
    exit 1
fi

command -v make >/dev/null 2>&1 || die "không tìm thấy 'make'"
command -v ssh  >/dev/null 2>&1 || die "không tìm thấy 'ssh'"
command -v scp  >/dev/null 2>&1 || die "không tìm thấy 'scp'"
[ -d "$THEOS_DIR" ] || die "không thấy Theos tại $THEOS_DIR (export THEOS=/duong/dan/theos)"

export THEOS="$THEOS_DIR"
SSH_OPTS=(-p "$DEVICE_PORT" -o ConnectTimeout=10 -o StrictHostKeyChecking=no)
SSH_TARGET="${DEVICE_USER}@${DEVICE_IP}"

step "Kiểm tra kết nối SSH tới ${SSH_TARGET}:${DEVICE_PORT}"
if ! ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "echo connected" >/dev/null 2>&1; then
    die "không SSH được. Kiểm tra: IP, cổng, OpenSSH trên máy, mật khẩu/key root."
fi
ok "SSH OK"

# Nhận diện rootless / rootful
if ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "[ -d /var/jb ]" 2>/dev/null; then
    SCHEME="rootless"; DPKG="/var/jb/usr/bin/dpkg"; UICHACE="/var/jb/usr/bin/uicache"
    ok "máy ROOTLESS (/var/jb tồn tại)"
else
    SCHEME="rootful"; DPKG="/usr/bin/dpkg"; UICHACE="/usr/bin/uicache"
    ok "máy ROOTFUL"
fi

# ------------------------------------------------------------------ build
step "Build .deb"
cd "$PROJECT_DIR"
make clean >/dev/null 2>&1 || true
make package FINALPACKAGE=1

DEB="$(ls -t "$PACKAGES_DIR"/*.deb 2>/dev/null | head -1 || true)"
[ -n "$DEB" ] || die "không tìm thấy .deb trong $PACKAGES_DIR"
ok "đã tạo $(basename "$DEB") ($(du -h "$DEB" | cut -f1))"

if grep -q "THEOS_PACKAGE_SCHEME[[:space:]]*=[[:space:]]*rootless" Makefile 2>/dev/null; then
    PACKAGE_SCHEME="rootless"
else
    PACKAGE_SCHEME="rootful"
fi
ok "scheme .deb sẽ build: ${PACKAGE_SCHEME}"

if [ "$SCHEME" != "$PACKAGE_SCHEME" ]; then
    warn "máy là ${SCHEME} nhưng .deb build theo ${PACKAGE_SCHEME} — có thể cài sai đường dẫn."
    warn "sửa THEOS_PACKAGE_SCHEME trong Makefile gốc rồi chạy lại."
fi

# ------------------------------------------------------------------ deploy
REMOTE_TMP="/tmp/$(basename "$DEB")"

step "Copy .deb sang máy"
scp -P "$DEVICE_PORT" -o StrictHostKeyChecking=no "$DEB" "${SSH_TARGET}:${REMOTE_TMP}"
ok "đã copy → ${REMOTE_TMP}"

step "Cài đặt (dpkg -i)"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$DPKG -i '$REMOTE_TMP' || $DPKG -i --force-overwrite '$REMOTE_TMP'"
ok "cài xong"

step "Cập nhật icon app"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$UICHACE -a 2>/dev/null || $UICHACE -p /Applications/IosNoti.app 2>/dev/null || true"
ok "uicache xong"

step "Respring"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "killall -9 SpringBoard 2>/dev/null || true"
ok "SpringBoard sẽ khởi động lại"

step "Dọn file tạm trên máy"
ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "rm -f '$REMOTE_TMP'" || true

printf '\n%sXong.%s Theo dõi log:\n' "$C_GRN" "$C_RST"
printf '  %sssh -p %s %s "idevicesyslog | grep IosNoti"%s\n' "$C_DIM" "$DEVICE_PORT" "$SSH_TARGET" "$C_RST"
printf '  %s(hoặc: idevicesyslog -u <UDID> | grep IosNoti)%s\n\n' "$C_DIM" "$C_RST"
