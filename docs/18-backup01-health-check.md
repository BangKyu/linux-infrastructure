# backup01 백업 상태 점검 및 자동 실행 

## 1. 작업 목적

`backup01`에서 백업 저장소와 날짜별 백업본의 상태를 점검하는 스크립트를 작성하였다. 
정상 상태와 오래된 백업본을 감지하는 상황을 각각 시험하고, systemd 서비스와 타이머를 이용해 점검 작업이 자동으로 실행되는지 확인하였다.

```text
매일 03:00  backup-storage01.timer
             → storage01 데이터를 백업

매일 04:00  check-backup-storage01.timer
             → 백업 저장소와 최신 백업본 상태 점검
```

## 2. 작업 환경

| 항목 | 설정 |
|---|---|
| 서버 | `backup01` |
| 운영체제 | Rocky Linux 9.8 |
| 백업 저장소 | `/backup/storage01` |
| 날짜별 백업 경로 | `/backup/storage01/snapshots` |
| 백업 생성 서비스 | `backup-storage01.service` |
| 백업 생성 타이머 | `backup-storage01.timer` |
| 상태 점검 스크립트 | `/usr/local/sbin/check-backup-storage01.sh` |
| 상태 점검 서비스 | `check-backup-storage01.service` |
| 상태 점검 타이머 | `check-backup-storage01.timer` |
| 최신 백업본 허용 시간 | 26시간 |

## 3. 점검 전 상태 확인

백업 저장소의 마운트 상태를 확인하였다.

```bash
findmnt /backup/storage01
```

결과:

```text
TARGET            SOURCE                          FSTYPE
/backup/storage01 /dev/mapper/vg_backup-lv_backup xfs
```

백업 생성 타이머의 상태와 다음 실행 시각을 확인하였다.

```bash
systemctl is-enabled backup-storage01.timer
systemctl is-active backup-storage01.timer
systemctl list-timers --all --no-pager --full backup-storage01.timer
```

주요 결과:

```text
enabled
active
NEXT: 2026-10-13 03:00:00 KST
```

최근 백업 서비스 로그에서 백업 성공 기록을 확인하였다.

```bash
sudo journalctl -u backup-storage01.service -n 15 --no-pager
systemctl show -p Result -p ExecMainStatus backup-storage01.service
```

주요 결과:

```text
BACKUP_OK /backup/storage01/snapshots/20261012-165636
Result=success
ExecMainStatus=0
```

최신 날짜별 백업본을 확인하였다.

```bash
sudo find /backup/storage01/snapshots \
  -mindepth 1 -maxdepth 1 -type d -name '20*' -printf '%f\n' |
  LC_ALL=C sort |
  tail -n 1
```

결과:

```text
20261012-165636
```

남아 있는 미완료 백업 폴더도 확인하였다.

```bash
sudo find /backup/storage01/snapshots \
  -mindepth 1 -maxdepth 1 -type d -name '.incomplete-*' -printf '%f\n'
```

출력 결과가 없었으므로 확인 시점에는 `.incomplete-*` 폴더가 남아 있지 않았다.

`Result=success`는 마지막 서비스 실행 결과를 나타낸다. 이것만으로 백업본이 최근에 만들어졌거나 앞으로 예정된 백업이 성공할 것이라고 판단할 수는 없다.

## 4. 최신 백업본의 나이 계산

최신 백업본 이름 `20261012-165636`은 `2026-10-12 16:56:36`을 뜻한다.

현재 시각과 백업본 시각을 비교하였다.

```bash
date '+현재 시각: %F %T %Z'
date -d '2026-10-12 16:56:36' \
  '+최신 백업본 시각: %F %T %Z'
```

결과:

```text
현재 시각: 2026-10-12 17:19:34 KST
최신 백업본 시각: 2026-10-12 16:56:36 KST
```

두 시각을 초 단위 숫자로 바꾼 뒤 분 단위 차이를 계산하였다.

```bash
now_seconds="$(date +%s)"
backup_seconds="$(date -d '2026-10-12 16:56:36' +%s)"

echo "백업 후 경과 시간: $(( (now_seconds - backup_seconds) / 60 ))분"
```

실행 시점에는 백업 후 약 27분이 지난 상태였다. 시간이 흐르므로 이후 계산 결과는 달라질 수 있다.

## 5. 폴더 이름에서 백업 시각 자동 추출

백업 시각을 매번 직접 입력하지 않도록 최신 백업본의 이름을 변수에 저장하였다.

```bash
latest_name="$(
  sudo find /backup/storage01/snapshots \
    -mindepth 1 -maxdepth 1 -type d -name '20*' -printf '%f\n' |
  LC_ALL=C sort |
  tail -n 1
)"

printf '최신 백업본: %s\n' "$latest_name"
```

결과:

```text
최신 백업본: 20261012-165636
```

폴더 이름에서 연·월·일·시·분·초를 추출하여 읽기 쉬운 형식으로 변환하였다.

```bash
latest_time="${latest_name:0:4}-${latest_name:4:2}-${latest_name:6:2} ${latest_name:9:2}:${latest_name:11:2}:${latest_name:13:2}"

[Oprintf '읽어낸 시각: %s\n' "$latest_time"
date -d "$latest_time" '+변환된 시각: %F %T %Z'
```

결과:

```text
읽어낸 시각: 2026-10-12 16:56:36
변환된 시각: 2026-10-12 16:56:36 KST
```

`${latest_name:0:4}`는 변수의 0번째 글자부터 4글자를 가져오는 Bash 문자열 추출 방식이다.

## 6. 최신 백업본 허용 시간 시험

하루에 한 번 백업하므로, 이번 실습에서는 최신 백업본의 허용 시간을 **26시간**으로 정하였다. 24시간 백업 주기에 2시간의 여유를 둔 실습 기준이며, 모든 환경에 적용되는 고정값은 아니다.

```bash
now_seconds="$(date +%s)"
backup_seconds="$(date -d "$latest_time" +%s)"
age_minutes=$(( (now_seconds - backup_seconds) / 60 ))
max_age_minutes=$(( 26 * 60 ))

printf '백업 후 경과: %s분 / 허용 시간: %s분\n' \
  "$age_minutes" "$max_age_minutes"

if (( age_minutes <= max_age_minutes )); then
  echo "BACKUP_RECENT"
else
  echo "BACKUP_STALE"
fi
```

결과:

```text
백업 후 경과: 29분 / 허용 시간: 1560분
BACKUP_RECENT
```

경고 판단이 동작하는지도 확인하기 위해 현재 터미널의 허용 시간 변수를 임시로 10분으로 변경하였다.

```bash
max_age_minutes=10

if (( age_minutes <= max_age_minutes )); then
  echo "BACKUP_RECENT"
else
  echo "BACKUP_STALE"
fi
```

결과:

```text
BACKUP_STALE
```

백업본이 만들어진 지 29분이 지나 10분 기준을 초과했기 때문이다. 이 작업은 현재 터미널의 변수만 변경했으며, 백업 파일이나 실제 백업 일정은 변경하지 않았다.

## 7. 백업 상태 점검 스크립트 작성

반복해서 실행할 수 있도록 상태 점검 스크립트를 작성하였다.

```bash
sudo vi /usr/local/sbin/check-backup-storage01.sh
```

작성한 내용:

```bash
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
```

스크립트는 다음을 순서대로 점검한다.

1. 백업 저장소 마운트 여부
2. 백업 생성 타이머의 활성화 및 실행 상태
3. 최신 날짜별 백업본 존재 여부와 이름 형식
4. 최신 백업본의 생성 시각이 허용 범위 이내인지 여부
5. 미완료 백업 폴더의 존재 여부

조건을 통과하지 못하면 오류를 출력하고 종료 코드 `1`을 반환한다. 모든 조건을 통과하면 `BACKUP_HEALTH_OK`를 출력한다.

## 8. 점검 스크립트 정상 실행

스크립트 실행 권한을 설정하고 문법을 검사하였다.

```bash
sudo chmod 700 /usr/local/sbin/check-backup-storage01.sh
sudo bash -n /usr/local/sbin/check-backup-storage01.sh
```

`bash -n`은 스크립트를 실행하지 않고 문법만 검사한다. 오류 출력이 없었다.

실제로 스크립트를 실행하고 종료 코드를 확인하였다.

```bash
sudo /usr/local/sbin/check-backup-storage01.sh
echo $?
```

결과:

```text
BACKUP_HEALTH_OK latest=20261012-165636 age=32분
0
```

정상 상태에서 점검 스크립트가 종료 코드 `0`을 반환하였다.

## 9. 오래된 백업본 경고 시험

운영 중인 원본 점검 스크립트를 변경하지 않도록 실습용 복사본을 만들었다.

```bash
sudo cp -a /usr/local/sbin/check-backup-storage01.sh \
  /root/check-backup-storage01-stale-test.sh
```

복사본의 허용 시간만 10분으로 변경하였다.

```bash
sudo vi /root/check-backup-storage01-stale-test.sh
```

변경한 값:

```bash
max_age_minutes=10
```

복사본의 문법을 검사한 뒤 실행하였다.

```bash
sudo bash -n /root/check-backup-storage01-stale-test.sh
sudo bash /root/check-backup-storage01-stale-test.sh
echo $?
```

결과:

```text
ERROR: 최신 백업본의 시각이 비정상적이거나 너무 오래됐습니다. age=33분
1
```

33분 전에 생성된 백업본은 시험용 10분 기준을 초과했으므로 경고와 종료 코드 `1`이 출력되었다. 이는 **경고 조건을 시험한 것**이며, 실제 백업 작업이 실패하거나 백업 데이터가 손상된 것은 아니다.

원본 점검 스크립트는 26시간 기준으로 유지하였다.

## 10. systemd 점검 서비스 구성

점검 스크립트를 systemd에서 실행하고 로그를 확인할 수 있도록 서비스 파일을 작성하였다.

```bash
sudo vi /etc/systemd/system/check-backup-storage01.service
```

설정:

```ini
[Unit]
Description=Check storage01 backup health

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/sbin/check-backup-storage01.sh
```

`Type=oneshot`이므로 점검을 한 번 실행하고 작업이 끝나면 서비스가 종료된다.

서비스 파일 검사와 수동 실행:

```bash
sudo systemd-analyze verify \
  /etc/systemd/system/check-backup-storage01.service
sudo systemctl daemon-reload
sudo systemctl start check-backup-storage01.service

systemctl show -p Result -p ExecMainStatus \
  check-backup-storage01.service
sudo journalctl -u check-backup-storage01.service -n 10 --no-pager
```

결과:

```text
Result=success
ExecMainStatus=0

Oct 12 17:31:26 backup01 systemd[1]: Starting Check storage01 backup health...
Oct 12 17:31:26 backup01 check-backup-storage01.sh[8303]: BACKUP_HEALTH_OK latest=20261012-165636 age=34분
Oct 12 17:31:26 backup01 systemd[1]: check-backup-storage01.service: Deactivated successfully.
Oct 12 17:31:26 backup01 systemd[1]: Finished Check storage01 backup health.
```

17:31의 기록은 **서비스를 수동으로 시작한 결과**이다. 아직 타이머가 자동으로 실행한 기록은 아니다.

## 11. 매일 04:00 점검 타이머 구성

백업 생성은 매일 03:00에 예정되어 있으므로, 상태 점검은 한 시간 뒤인 매일 04:00으로 설정하였다.

```bash
sudo vi /etc/systemd/system/check-backup-storage01.timer
```

설정:

```ini
[Unit]
Description=Check storage01 backup health daily

[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true
Unit=check-backup-storage01.service

[Install]
WantedBy=timers.target
```

설정 문법을 검사하고 타이머를 활성화하였다.

```bash
systemd-analyze calendar --iterations=2 '*-*-* 04:00:00'
sudo systemd-analyze verify \
  /etc/systemd/system/check-backup-storage01.timer
sudo systemctl daemon-reload
sudo systemctl enable --now check-backup-storage01.timer
```

상태 확인 결과:

```text
enabled
active
NEXT: 2026-10-13 04:00:00 KST
LAST: -
```

타이머는 활성화되었으나, 이 시점에는 타이머에 의한 실제 자동 실행 기록이 없었다.

## 12. 일회성 시험 타이머 설정

다음 날 04:00까지 기다리지 않고 타이머의 자동 실행을 검증하기 위해, 기존 04:00 설정을 먼저 백업하였다.

```bash
sudo cp -a /etc/systemd/system/check-backup-storage01.timer \
  /root/check-backup-storage01.timer.before-lab
```

시험 시각을 확인하였다.

```bash
date '+현재: %F %T %Z'
date -d '+10 minutes' '+시험 시각: %F %T %Z'
```

결과:

```text
현재: 2026-10-12 17:33:28 KST
시험 시각: 2026-10-12 17:43:28 KST
```

타이머의 `[Timer]` 부분을 시험용으로 변경하였다.

```ini
[Timer]
OnCalendar=2026-10-12 17:43:28
Persistent=false
Unit=check-backup-storage01.service
```

설정 검사 후 타이머를 다시 시작하여 새 일정을 적용하였다.

```bash
sudo systemd-analyze verify \
  /etc/systemd/system/check-backup-storage01.timer
sudo systemctl daemon-reload
sudo systemctl restart check-backup-storage01.timer

systemctl list-timers --all --no-pager --full \
  check-backup-storage01.timer
```

결과:

```text
NEXT: 2026-10-12 17:43:28 KST
LAST: -
```

이 시점에는 일회성 시험 실행이 **예약된 것만** 확인하였다.

## 13. 타이머 자동 실행 결과

시험 시각이 지난 후 타이머 기록을 확인하였다.

```bash
date '+%F %T %Z'
systemctl list-timers --all --no-pager --full \
  check-backup-storage01.timer
```

주요 결과:

```text
현재 시각: 2026-10-12 17:44:50 KST
NEXT: -
LAST: 2026-10-12 17:43:54 KST
```

`LAST`에 시험 시각의 실행 기록이 표시되었다. 일회성 일정이므로 다음 실행 시각인 `NEXT`는 표시되지 않았다.

실제로 점검 서비스가 실행됐는지 로그와 종료 상태를 확인하였다.

```bash
sudo journalctl -u check-backup-storage01.service \
  --since '2026-10-12 17:42:00' --no-pager

systemctl show -p Result -p ExecMainStatus \
  check-backup-storage01.service
```

결과:

```text
Oct 12 17:43:55 backup01 systemd[1]: Starting Check storage01 backup health...
Oct 12 17:43:55 backup01 check-backup-storage01.sh[8458]: BACKUP_HEALTH_OK latest=20261012-165636 age=47분
Oct 12 17:43:55 backup01 systemd[1]: check-backup-storage01.service: Deactivated successfully.
Oct 12 17:43:55 backup01 systemd[1]: Finished Check storage01 backup health.

Result=success
ExecMainStatus=0
```

17:31의 수동 실행과 달리, 17:43 실행은 예약된 시험 시각에 타이머가 점검 서비스를 실행한 결과이다.

## 14. 매일 04:00 설정 복원

시험을 마친 뒤 보관한 원래 설정을 확인하였다.

```bash
sudo cat /root/check-backup-storage01.timer.before-lab
```

확인한 설정:

```ini
[Timer]
OnCalendar=*-*-* 04:00:00
Persistent=true
Unit=check-backup-storage01.service
```

원래 설정을 복원하고 적용하였다.

```bash
sudo cp -a /root/check-backup-storage01.timer.before-lab \
  /etc/systemd/system/check-backup-storage01.timer

sudo systemd-analyze verify \
  /etc/systemd/system/check-backup-storage01.timer
sudo systemctl daemon-reload
sudo systemctl restart check-backup-storage01.timer
```

최종 설정과 상태를 확인하였다.

```bash
systemctl cat check-backup-storage01.timer
systemctl is-enabled check-backup-storage01.timer
systemctl is-active check-backup-storage01.timer
systemctl list-timers --all --no-pager --full \
  check-backup-storage01.timer
systemctl --failed
```

주요 결과:

```text
OnCalendar=*-*-* 04:00:00
Persistent=true

enabled
active
NEXT: 2026-10-13 04:00:00 KST

0 loaded units listed.
```

복원 후 `list-timers`의 `LAST` 값은 앞서 확인한 17:43 시험 실행 시각과 다르게 표시되었다. 따라서 **시험 실행 성공의 근거는 17:43:55의 점검 서비스 로그와 종료 상태**로 기록하였다.

## 15. 작업 결과와 검증 범위

이번 실습에서 다음을 확인하였다.

| 확인 항목 | 결과 |
|---|---|
| 저장소 마운트 및 백업 타이머 상태 | 정상 |
| 최신 백업본 시각 계산 | 확인 |
| 26시간 기준 정상 판단 | `BACKUP_HEALTH_OK`, 종료 코드 `0` |
| 복사본의 10분 기준 경고 시험 | 오류 출력, 종료 코드 `1` |
| 점검 서비스 수동 실행 | 성공 |
| 17:43 일회성 타이머 자동 실행 | 성공 |
| 원래 04:00 정기 설정 복원 | 완료 |
| 실패 상태의 systemd 유닛 | 없음 |

17:43 시험으로 **타이머가 점검 서비스를 자동 실행할 수 있음**을 확인하였다. 그러나 원래 일정인 **다음 날 04:00의 실제 실행은 아직 확인하지 않았다.**

이번 점검은 마운트, 타이머 상태, 백업본의 최근성 및 미완료 폴더 유무를 확인했지만 백업 파일 내용의 무결성이나 실제 복원 가능성을 증명하는 검사는 아니므로, 복원은 별도의 실습에서 검증한다.

