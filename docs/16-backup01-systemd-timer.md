# backup01 systemd 서비스 및 백업 타이머 구성

## 1. 작업 목적

`backup01`에서 수동으로 실행하던 백업 스크립트를 systemd 서비스로 등록하고, 매일 03:00에 실행하도록 타이머를 구성하였다.

서비스를 수동 실행해 백업 결과를 확인한 뒤, 타이머를 임시로 16:15에 실행하여 **예약 시각에 실제로 백업이 수행되는지** 검증하였다. 실습 후에는 매일 03:00 일정으로 복원하였다.

## 2. 작업 환경

| 항목 | 설정 |
|---|---|
| 백업 서버 | `backup01` (`10.10.10.103`) |
| 백업 원본 서버 | `storage01` (`10.10.10.102`) |
| 백업 스크립트 | `/usr/local/sbin/backup-storage01.sh` |
| 백업 저장소 | `/backup/storage01` |
| 날짜별 백업 경로 | `/backup/storage01/snapshots/` |
| 서비스 파일 | `/etc/systemd/system/backup-storage01.service` |
| 타이머 파일 | `/etc/systemd/system/backup-storage01.timer` |
| 정기 실행 시각 | 매일 03:00 KST |

백업 스크립트는 `backup01`에서 root 권한으로 실행되며, `storage01`에는 SSH를 사용하여 `backupreader` 계정으로 접속한다.

## 3. 작업 전 상태 확인

백업 저장소가 마운트되어 있는지 확인하였다.

```bash
findmnt /backup/storage01
df -hT /backup/storage01
sudo du -sh /backup/storage01/snapshots
```

결과:

```text
TARGET            SOURCE                          FSTYPE
/backup/storage01 /dev/mapper/vg_backup-lv_backup xfs

Filesystem                      Type  Size  Used Avail Use% Mounted on
/dev/mapper/vg_backup-lv_backup xfs    30G  247M   30G   1% /backup/storage01

16K     /backup/storage01/snapshots
```

백업 스크립트의 문법과 실행 권한도 확인하였다.

```bash
sudo bash -n /usr/local/sbin/backup-storage01.sh
sudo ls -l /usr/local/sbin/backup-storage01.sh
```

결과:

```text
-rwx------. 1 root root 1435 Oct 12 15:04 /usr/local/sbin/backup-storage01.sh
```

`bash -n`에서 오류가 출력되지 않았고, 스크립트에 실행 권한이 있는 것을 확인하였다.

## 4. systemd 서비스 구성

백업 스크립트를 실행할 서비스 파일을 작성하였다.

```bash
sudo vi /etc/systemd/system/backup-storage01.service
```

작성한 내용:

```ini
[Unit]
Description=Back up storage01 NFS data
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
User=root
ExecStart=/usr/local/sbin/backup-storage01.sh
```

`Type=oneshot`은 백업처럼 한 번 실행하고 종료되는 작업에 사용하였다. `ExecStart`에는 기존에 수동으로 실행하던 백업 스크립트의 경로를 지정하였다.

서비스 파일을 검사하고 systemd에 반영하였다.

```bash
sudo systemd-analyze verify /etc/systemd/system/backup-storage01.service
sudo systemctl daemon-reload
```

`verify`에서 오류가 출력되지 않았다. 이 검사는 서비스 파일을 검사하는 것이며 백업을 실제로 실행하지는 않는다.

## 5. 서비스 수동 실행 검증

서비스를 수동으로 시작하였다.

```bash
sudo systemctl start backup-storage01.service
```

서비스 상태와 실행 로그를 확인하였다.

```bash
systemctl status backup-storage01.service --no-pager -l
sudo journalctl -u backup-storage01.service -n 30 --no-pager
systemctl show -p Result -p ExecMainStatus backup-storage01.service
```

주요 결과:

```text
PREVIOUS_BACKUP /backup/storage01/snapshots/20261012-150433
BACKUP_OK /backup/storage01/snapshots/20261012-155929
backup-storage01.service: Deactivated successfully.
Result=success
ExecMainStatus=0
```

새 백업본 `20261012-155929`가 생성되고 서비스가 성공 상태로 종료되었다.

백업 서비스는 한 번 실행하고 종료되는 `oneshot` 방식이므로, 작업 후 `inactive (dead)`로 표시되는 것이 정상이다. 

서비스는 `static` 상태이며, 정기 실행은 활성화된 타이머가 담당한다.

## 6. 정기 실행 일정 확인

서버의 시간대와 시간 동기화 상태를 확인하였다.

```bash
timedatectl
```

주요 결과:

```text
Time zone: Asia/Seoul (KST, +0900)
System clock synchronized: yes
NTP service: active
```

매일 03:00 일정의 다음 실행 시각을 계산하였다.

```bash
systemd-analyze calendar --iterations=3 '*-*-* 03:00:00'
```

결과:

```text
Normalized form: *-*-* 03:00:00
Next elapse: Tue 2026-10-13 03:00:00 KST
Iter. #2: Wed 2026-10-14 03:00:00 KST
Iter. #3: Thu 2026-10-15 03:00:00 KST
```

## 7. systemd 타이머 구성

타이머 파일을 작성하였다.

```bash
sudo vi /etc/systemd/system/backup-storage01.timer
```

작성한 내용:

```ini
[Unit]
Description=Run storage01 backup daily

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true
Unit=backup-storage01.service

[Install]
WantedBy=timers.target
```

`OnCalendar`로 매일 03:00 실행을 지정하였다. `Unit`은 타이머가 실행할 백업 서비스를 지정한다.

`Persistent=true`는 VM이 꺼져 있는 동안 예약 시각을 놓쳤을 때, 타이머가 다시 활성화되면 놓친 실행을 보충하도록 설정한 것이다. **이번 실습에서 실제 VM 종료를 통한 보충 실행까지 검증한 것은 아니다.**

설정을 검사하고 활성화하였다.

```bash
sudo systemd-analyze verify /etc/systemd/system/backup-storage01.timer
sudo systemctl daemon-reload
sudo systemctl enable --now backup-storage01.timer
```

상태 확인:

```bash
systemctl is-enabled backup-storage01.timer
systemctl is-active backup-storage01.timer
systemctl list-timers --all backup-storage01.timer
```

결과:

```text
enabled
active
NEXT: Tue 2026-10-13 03:00:00 KST
```

이 시점에는 타이머가 다음 실행을 기다리고 있었으며, 아직 예약 실행으로 생성된 새 백업본은 없었다.

## 8. 임시 일정으로 실제 타이머 실행 검증

다음 날 03:00까지 기다리지 않고 타이머의 실제 실행을 확인하기 위해, 기존 타이머 파일을 먼저 백업하였다.

```bash
sudo cp -a /etc/systemd/system/backup-storage01.timer \
  /root/backup-storage01.timer.before-lab
```

타이머의 `[Timer]` 부분을 이번 실습에 한해 다음처럼 변경하였다.

```ini
[Timer]
OnCalendar=2026-10-12 16:15:00
Persistent=false
Unit=backup-storage01.service
```

날짜와 시각을 지정해 한 번 실행되도록 하였고, 임시 실습 중 놓친 시각을 뒤늦게 실행하지 않도록 `Persistent=false`로 변경하였다.

일정을 확인하고 변경된 타이머를 적용하였다.

```bash
systemd-analyze calendar '2026-10-12 16:15:00'
sudo systemd-analyze verify /etc/systemd/system/backup-storage01.timer
sudo systemctl daemon-reload
sudo systemctl restart backup-storage01.timer
systemctl list-timers --all --no-pager backup-storage01.timer
```

적용 후 `NEXT`가 2026년 10월 12일 16:15 KST로 표시되었다.

## 9. 예약 시각의 백업 실행 확인

16:15가 지난 후 서비스 로그와 종료 상태를 확인하였다.

```bash
sudo journalctl -u backup-storage01.service \
  --since '2026-10-12 16:14:00' --no-pager

systemctl show -p Result -p ExecMainStatus backup-storage01.service
```

결과:

```text
Oct 12 16:15:14 backup01 systemd[1]: Starting Back up storage01 NFS data...
Oct 12 16:15:14 backup01 backup-storage01.sh[7934]: PREVIOUS_BACKUP /backup/storage01/snapshots/20261012-155929
Oct 12 16:15:15 backup01 backup-storage01.sh[7946]: .d..tpog.a. ./
Oct 12 16:15:15 backup01 backup-storage01.sh[7934]: BACKUP_OK /backup/storage01/snapshots/20261012-161514
Oct 12 16:15:15 backup01 systemd[1]: backup-storage01.service: Deactivated successfully.
Oct 12 16:15:15 backup01 systemd[1]: Finished Back up storage01 NFS data.
Result=success
ExecMainStatus=0
```

16:15에 타이머가 백업 서비스를 실행하였고, 새 백업본 `20261012-161514`가 생성되었다.

한 번만 실행하도록 지정한 임시 타이머는 실행 후 다음 일정이 없으므로 `NEXT`가 `-`로 표시되었다.

## 10. 매일 03:00 설정 복원

실습 전에 백업한 원래 타이머 파일의 내용을 확인하였다.

```bash
sudo cat /root/backup-storage01.timer.before-lab
```

`OnCalendar=*-*-* 03:00:00`과 `Persistent=true`가 있는 것을 확인한 후 복원하였다.

```bash
sudo cp -a /root/backup-storage01.timer.before-lab \
  /etc/systemd/system/backup-storage01.timer

sudo systemd-analyze verify /etc/systemd/system/backup-storage01.timer
sudo systemctl daemon-reload
sudo systemctl restart backup-storage01.timer
```

최종 상태 확인:

```bash
systemctl cat backup-storage01.timer
systemctl is-enabled backup-storage01.timer
systemctl is-active backup-storage01.timer
systemctl list-timers --all --no-pager --full backup-storage01.timer
systemctl --failed
```

주요 결과:

```text
OnCalendar=*-*-* 03:00:00
Persistent=true
enabled
active

NEXT: Tue 2026-10-13 03:00:00 KST
LAST: Mon 2026-10-12 16:07:16 KST

0 loaded units listed.
```

최종 `NEXT`가 매일 03:00 일정으로 복원되었음을 확인하였다.

설정 복원 후 `LAST`에는 16:07:16이 표시되었다. 따라서 **16:15 실습 실행의 증거로 최종 `LAST` 값을 사용하지 않고**, 16:15의 서비스 로그와 새 백업본을 근거로 기록하였다.

## 11. 새 백업본의 데이터 확인

예약 실행으로 생성된 백업본에 실습용 파일이 있는지 확인하였다.

```bash
sudo cat /backup/storage01/snapshots/20261012-161514/version-test.txt
```

결과:

```text
version 2 - changed
```

타이머가 서비스를 실행한 사실뿐 아니라, 생성된 백업본에서 파일을 읽을 수 있는 것도 확인하였다.

## 12. 작업 결과

| 검증 항목 | 결과 |
|---|---|
| systemd 서비스 파일 검사 | 오류 없음 |
| 서비스 수동 실행 | 성공, 새 백업본 생성 |
| 타이머 등록 상태 | `enabled`, `active` |
| 임시 16:15 자동 실행 | 서비스 로그와 새 백업본으로 확인 |
| 자동 실행 종료 상태 | `Result=success`, `ExecMainStatus=0` |
| 새 백업본 파일 읽기 | 성공 |
| 매일 03:00 일정 복원 | `NEXT` 시각으로 확인 |
| 실패한 systemd 서비스 | 없음 |

이번 실습에서는 systemd 타이머가 예약 시각에 백업 서비스를 실제로 실행하는 것을 확인하였다. 

매일 03:00 일정은 복원하고 다음 실행 시각까지 확인했지만, **03:00 예약 실행 자체와 VM 종료 후 놓친 작업의 보충 실행은 아직 검증하지 않았다.**
