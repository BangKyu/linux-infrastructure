#!/usr/bin/env bash
set -euo pipefail

backup_root="/backup/storage01"
snapshots_dir="$backup_root/snapshots"
max_age_minutes=1560

if ! mountpoint -q "$backup_root"; then
    echo "ERROR: 백업 저장소가 마운트되지 않았습니다." >&2
    exit 1
fi

if ! systemctl is-enabled --quiet backup-storage01.timer ||
   ! systemctl is-active --quiet backup-storage01.timer; then
    echo "ERROR: 백업 타이머가 활성화되어 있지 않습니다." >&2
    exit 1
fi

latest_name="$(
    find "$snapshots_dir" -mindepth 1 -maxdepth 1 \
        -type d -name '20*' -printf '%f\n' |
    LC_ALL=C sort |
    tail -n 1
)"

if [[ ! "$latest_name" =~ ^[0-9]{8}-[0-9]{6}(-v[0-9]+)?$ ]]; then
    echo "ERROR: 최신 백업본을 찾을 수 없거나 이름 형식이 잘못되었습니다." >&2
    exit 1
fi

latest_time="${latest_name:0:4}-${latest_name:4:2}-${latest_name:6:2} ${latest_name:9:2}:${latest_name:11:2}:${latest_name:13:2}"
backup_seconds="$(date -d "$latest_time" +%s)"
age_minutes=$(( ($(date +%s) - backup_seconds) / 60 ))

if (( age_minutes < 0 || age_minutes > max_age_minutes )); then
    echo "ERROR: 최신 백업본의 시각이 비정상적이거나 너무 오래됐습니다. age=${age_minutes}분" >&2
    exit 1
fi

if [[ -n "$(find "$snapshots_dir" -mindepth 1 -maxdepth 1 \
    -type d -name '.incomplete-*' -print -quit)" ]]; then
    echo "ERROR: 미완료 백업 폴더가 남아 있습니다." >&2
    exit 1
fi

printf 'BACKUP_HEALTH_OK latest=%s age=%s분\n' "$latest_name" "$age_minutes"
