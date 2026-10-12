# backup01 백업 보존 대상 및 저장소 용량 점검

## 1. 작업 목적

`backup01`에 쌓이는 날짜별 백업본과 저장소 사용량을 확인하였다. 최신 7개를 보관한다고 가정했을 때 어떤 백업본이 정리 대상이 되는지 미리 확인하였다.

이번 실습에서는 **백업본을 삭제하지 않았고 자동 삭제도 설정하지 않았다.**

## 2. 작업 환경

| 항목 | 설정 |
|---|---|
| 서버 | `backup01` |
| 운영체제 | Rocky Linux 9.8 |
| 백업 파일시스템 | XFS |
| 백업 마운트 지점 | `/backup/storage01` |
| 날짜별 백업 경로 | `/backup/storage01/snapshots` |
| 백업 실행 방식 | `backup-storage01.service` 및 `backup-storage01.timer` |
| 실습용 보존 기준 | 최신 백업본 7개 |

## 3. 백업 저장소 상태 확인

백업 저장소가 마운트되어 있는지 확인하였다.

```bash
findmnt /backup/storage01
```

결과:

```text
TARGET            SOURCE                          FSTYPE
/backup/storage01 /dev/mapper/vg_backup-lv_backup xfs
```

파일시스템의 공간 사용량을 확인하였다.

```bash
df -hT /backup/storage01
```

결과:

```text
Filesystem                      Type  Size  Used Avail Use% Mounted on
/dev/mapper/vg_backup-lv_backup xfs    30G  247M   30G   1% /backup/storage01
```

inode 사용량도 확인하였다.

```bash
df -i /backup/storage01
```

처음 확인한 결과:

```text
Filesystem                        Inodes IUsed    IFree IUse% Mounted on
/dev/mapper/vg_backup-lv_backup 15728640    17 15728623    1% /backup/storage01
```

디스크 공간과 inode 사용률이 모두 1%로, 현재 저장소에는 여유가 있는 것을 확인하였다.

## 4. 날짜별 백업본과 사용량 확인

스냅샷 디렉터리의 사용량을 확인하였다.

```bash
sudo du -sh /backup/storage01/snapshots
```

처음 확인한 결과:

```text
16K     /backup/storage01/snapshots
```

완료된 날짜별 백업본의 이름을 확인하였다.

```bash
sudo find /backup/storage01/snapshots \
  -mindepth 1 -maxdepth 1 -type d -name '20*' -printf '%f\n' |
  LC_ALL=C sort
```

결과:

```text
20261012-114802
20261012-122510-v1
20261012-123626-v2
20261012-145759
20261012-150433
20261012-155929
20261012-161514
```
snapshots 경로 바로 아래만 검색하여 날짜로 시작하는 백업 디렉터리 7개를 확인하였다.

.incomplete-* 폴더는 검색 조건에 맞지 않아 목록에서 제외된다.


## 5. 미완료 백업 폴더 확인

실패하거나 중단된 백업 작업의 폴더가 남아 있는지 확인하였다.

```bash
sudo find /backup/storage01/snapshots \
  -mindepth 1 -maxdepth 1 -type d -name '.incomplete-*' -printf '%f\n'
```

결과는 출력되지 않았다. 확인 시점에는 남아 있는 `.incomplete-*` 폴더가 없었다.

## 6. 정리 대상 미리보기 방법

먼저 **최신 5개만 보관한다는 가정**으로 정리 후보를 출력하였다.

```bash
sudo find /backup/storage01/snapshots \
  -mindepth 1 -maxdepth 1 -type d -name '20*' -printf '%f\n' |
  LC_ALL=C sort |
  head -n -5
```

결과:

```text
20261012-114802
20261012-122510-v1
```

`head -n -5`는 정렬된 목록의 **마지막 5줄을 제외하고** 출력한다. 따라서 7개 중 오래된 2개가 표시되었다.

이후 실습에서는 최신 7개 보관을 기준으로 정리 후보를 확인하였다.

## 7. 여덟 번째 백업본 생성

백업본이 7개인 상태에서 서비스를 수동 실행하여 새 백업본을 생성하였다.

```bash
sudo systemctl start backup-storage01.service
systemctl show -p Result -p ExecMainStatus backup-storage01.service
```

결과:

```text
Result=success
ExecMainStatus=0
```

서비스 로그도 확인하였다.

```bash
sudo journalctl -u backup-storage01.service -n 8 --no-pager
```

주요 결과:

```text
Oct 12 16:56:36 backup01 systemd[1]: Starting Back up storage01 NFS data...
Oct 12 16:56:36 backup01 backup-storage01.sh[8086]: PREVIOUS_BACKUP /backup/storage01/snapshots/20261012-161514
Oct 12 16:56:36 backup01 backup-storage01.sh[8098]: .d..tpog.a. ./
Oct 12 16:56:36 backup01 backup-storage01.sh[8086]: BACKUP_OK /backup/storage01/snapshots/20261012-165636
Oct 12 16:56:36 backup01 systemd[1]: Finished Back up storage01 NFS data.
```

이전 백업본 `20261012-161514`를 참조하여 새 백업본 `20261012-165636`이 정상 생성되었다.

## 8. 최신 7개 보관 기준의 정리 후보 확인

백업본이 8개가 된 후, 최신 7개를 제외한 정리 후보를 출력하였다.

```bash
sudo find /backup/storage01/snapshots \
  -mindepth 1 -maxdepth 1 -type d -name '20*' -printf '%f\n' |
  LC_ALL=C sort |
  head -n -7
```

결과:

```text
20261012-114802
```

`head -n -7`은 정렬된 목록의 마지막 7줄을 제외한다. 백업본 8개 중 가장 오래된 `20261012-114802` 하나만 정리 후보로 표시되었다.

이 명령은 **폴더 이름을 출력할 뿐 삭제하지 않는다.** 따라서 `-v1`과 `-v2` 실습 백업본도 그대로 유지되었다.

## 9. 백업 실행 후 용량 확인

새 백업본이 생성된 뒤 저장소 상태를 다시 확인하였다.

```bash
df -hT /backup/storage01
df -i /backup/storage01
sudo du -sh /backup/storage01/snapshots
```

결과:

```text
Filesystem                      Type  Size  Used Avail Use% Mounted on
/dev/mapper/vg_backup-lv_backup xfs    30G  247M   30G   1% /backup/storage01

Filesystem                        Inodes IUsed    IFree IUse% Mounted on
/dev/mapper/vg_backup-lv_backup 15728640    18 15728622    1% /backup/storage01

20K     /backup/storage01/snapshots
```

백업본이 하나 늘어난 뒤 스냅샷 디렉터리 사용량은 `16K`에서 `20K`로, 사용 중인 inode는 `17`개에서 `18`개로 증가하였다.

변경되지 않은 파일은 이전 백업본과 하드 링크로 데이터를 공유하므로, 새 백업본의 모든 파일이 별도 공간을 차지하는 것은 아니다. `df -hT`의 `247M`는 파일시스템 전체 사용량을 반올림하여 표시하므로 이번 작은 증가가 숫자에 드러나지 않았다.

단, 스냅샷 디렉터리 사용량이 작다는 사실만으로 모든 백업 파일의 내용이나 복원 가능성이 검증되는 것은 아니다.

## 10. 최종 백업본 목록

완료된 백업본 목록을 다시 확인하였다.

```bash
sudo find /backup/storage01/snapshots \
  -mindepth 1 -maxdepth 1 -type d -name '20*' -printf '%f\n' |
  LC_ALL=C sort
```

결과:

```text
20261012-114802
20261012-122510-v1
20261012-123626-v2
20261012-145759
20261012-150433
20261012-155929
20261012-161514
20261012-165636
```

완료된 백업본은 총 8개이다.

## 11. 작업 결과

백업 저장소가 정상적으로 마운트되어 있고, 디스크 공간과 inode 사용률이 모두 1%임을 확인하였다. 백업 서비스를 실행하여 여덟 번째 날짜별 백업본을 생성했으며, 서비스 결과 `success`와 `BACKUP_OK`를 확인하였다.

최신 7개 보관을 가정한 미리보기에서는 가장 오래된 `20261012-114802`만 정리 후보로 표시되었다. 이번 실습에서는 **정리 후보만 확인했으며, 실제 백업본 삭제나 자동 정리 설정은 수행하지 않았다.**
