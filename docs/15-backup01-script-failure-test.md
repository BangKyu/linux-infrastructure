# backup01 백업 스크립트 정상 동작 및 실패 처리 검증

## 1. 작업 목적

`backup01`에서 작성한 백업 스크립트가 `storage01`의 NFS 데이터를 날짜별 백업본으로 저장하는지 확인하였다.

실제 디스크와 원본 데이터는 변경하지 않고, 스크립트 복사본의 경로를 수정해 두 가지 실패 상황을 재현하였다. 백업 저장소 미마운트와 원격 원본 경로 오류 모두에서 실패한 작업이 정상 백업으로 표시되지 않는지 확인하였다.

## 2. 작업 환경

| 항목 | 경로 또는 설정 |
|---|---|
| 백업 실행 서버 | `backup01` (`10.10.10.103`) |
| 백업 원본 서버 | `storage01` (`10.10.10.102`) |
| 원격 접속 계정 | `backupreader` |
| 백업 원본 | `/srv/nfs/webdata/` |
| 백업 저장소 | `/backup/storage01` |
| 날짜별 백업본 | `/backup/storage01/snapshots/` |
| 운영 스크립트 | `/usr/local/sbin/backup-storage01.sh` |

이번 실습 당시 백업 스크립트는 수동으로 실행하였다. 정기 실행을 위한 `systemd timer`는 아직 구성하지 않았다.

## 3. 스크립트의 기본 동작

스크립트는 다음 순서로 작업한다.

```text
백업 파일시스템 마운트 확인
→ 이전에 완료된 백업본 선택
→ .incomplete-날짜-시각 작업 폴더 생성
→ SSH와 rsync로 storage01의 데이터 백업
→ 전송에 성공하면 작업 폴더를 날짜-시각 완성본으로 변경
→ BACKUP_OK 출력
```

이전 백업본은 날짜가 포함된 디렉터리 이름을 정렬하여 선택한다. 이전 백업본과 동일한 파일은 `rsync --link-dest`를 통해 하드 링크로 재사용할 수 있다.

스크립트의 주요 실패 처리 부분은 다음과 같다.

```bash
if ! mountpoint -q "$backup_root"; then
    echo "ERROR: 백업 파일시스템이 마운트되지 않았습니다." >&2
    exit 1
fi
```

백업 저장소가 마운트되지 않았다면 `rsync`를 실행하기 전에 중단한다.

```bash
rsync -aA --numeric-ids --itemize-changes \
    --link-dest="$previous" \
    -e 'ssh ...' \
    backupreader@10.10.10.102:/srv/nfs/webdata/ \
    "$pending/"

mv -- "$pending" "$completed"
printf 'BACKUP_OK %s\n' "$completed"
```

`rsync`가 성공해야 작업 폴더의 이름을 완성본으로 변경하고 `BACKUP_OK`를 출력한다. 전송에 실패하면 완성본으로 표시하지 않는다.

## 4. 정상 백업 실행

먼저 운영 스크립트의 Bash 문법을 검사하였다.

```bash
sudo bash -n /usr/local/sbin/backup-storage01.sh
```

문법 오류가 없어 별도의 오류 메시지가 출력되지 않았다. `bash -n`은 문법만 확인하며, 실제 SSH 접속이나 파일 전송 성공까지 검증하지는 않는다.

스크립트를 실행하고 종료 코드를 확인하였다.

```bash
sudo /usr/local/sbin/backup-storage01.sh
echo $?
```

결과:

```text
PREVIOUS_BACKUP /backup/storage01/snapshots/20261012-145759
.d..tpog.a. ./
BACKUP_OK /backup/storage01/snapshots/20261012-150433
0
```

`PREVIOUS_BACKUP`은 이번 작업에서 참고한 이전 백업본이다. `BACKUP_OK`는 새 백업본이 완성되었다는 스크립트의 출력이며, 종료 코드 `0`은 스크립트가 정상 종료되었음을 뜻한다.

## 5. 새 백업본 내용 확인

새 백업본에 저장된 파일을 확인하였다.

```bash
sudo ls -la /backup/storage01/snapshots/20261012-150433
```

결과:

```text
total 12
drwxrws---+ 2 2000 2000  77 Oct 12 12:14 .
drwxr-xr-x. 7 root root 127 Oct 12 15:04 ..
-rw-r--r--+ 6 2000 2000  40 Oct  1 10:21 nfs-status.txt
-rw-r--r--+ 5 2000 2000  21 Oct  8 16:49 restore-drill.txt
-rw-rw----+ 3 2000 2000  20 Oct 12 12:35 version-test.txt
```

실습용 파일의 내용도 확인하였다.

```bash
sudo cat /backup/storage01/snapshots/20261012-150433/version-test.txt
```

결과:

```text
version 2 - changed
```

이전 백업본과 새 백업본에 있는 `version-test.txt`의 장치번호와 inode 번호를 비교하였다.

```bash
sudo stat -c '%d:%i links=%h %n' \
  /backup/storage01/snapshots/20261012-145759/version-test.txt \
  /backup/storage01/snapshots/20261012-150433/version-test.txt
```

결과:

```text
64770:135 links=3 /backup/storage01/snapshots/20261012-145759/version-test.txt
64770:135 links=3 /backup/storage01/snapshots/20261012-150433/version-test.txt
```

두 경로의 장치번호와 inode 번호가 같으므로, 변경되지 않은 파일이 하드 링크로 재사용된 것을 확인하였다.

## 6. 실패 실습 1: 백업 저장소 마운트 검사

운영 스크립트를 직접 변경하지 않고 실습용 복사본을 사용하였다.

```bash
sudo cp -a /usr/local/sbin/backup-storage01.sh \
  /root/backup-storage01-mount-test.sh

sudo vi /root/backup-storage01-mount-test.sh
```

복사본의 `backup_root`를 마운트되지 않은 실습용 경로로 변경하였다.

```bash
backup_root="/root/backup-storage01-not-mounted"
```

변경 사항과 문법을 확인하였다.

```bash
sudo grep -n '^backup_root=' /root/backup-storage01-mount-test.sh
sudo bash -n /root/backup-storage01-mount-test.sh
```

결과:

```text
4:backup_root="/root/backup-storage01-not-mounted"
```

복사본을 실행하고 종료 코드를 확인하였다.

```bash
sudo bash /root/backup-storage01-mount-test.sh
echo $?
```

결과:

```text
ERROR: 백업 파일시스템이 마운트되지 않았습니다.
1
```

스크립트는 마운트 검사 단계에서 중단되었다. 이 경우 `rsync`는 실행되지 않았으며 `BACKUP_OK`도 출력되지 않았다.

이번 실습은 실제 백업 디스크를 분리한 것이 아니라, 마운트되지 않은 경로를 지정하여 스크립트의 사전 검사 동작을 확인한 것이다.

## 7. 실패 실습 2: 원격 원본 경로 오류

다른 실습용 복사본을 만들었다.

```bash
sudo cp -a /usr/local/sbin/backup-storage01.sh \
  /root/backup-storage01-rsync-test.sh

sudo vi /root/backup-storage01-rsync-test.sh
```

백업 저장소 경로는 정상인 `/backup/storage01`로 유지하고, 원격 원본 경로만 존재하지 않는 경로로 변경하였다.

```bash
backupreader@10.10.10.102:/srv/nfs/webdata/__missing_backup_lab_source__/
```

변경 사항과 문법을 확인하였다.

```bash
sudo grep -nE 'backup_root=|backupreader@' \
  /root/backup-storage01-rsync-test.sh

sudo bash -n /root/backup-storage01-rsync-test.sh
```

결과:

```text
4:backup_root="/backup/storage01"
46:    backupreader@10.10.10.102:/srv/nfs/webdata/__missing_backup_lab_source__/ \
```

복사본을 실행하고 종료 코드를 확인하였다.

```bash
sudo bash /root/backup-storage01-rsync-test.sh
echo $?
```

결과:

```text
PREVIOUS_BACKUP /backup/storage01/snapshots/20261012-150433
rsync: [sender] change_dir "/srv/nfs/webdata/__missing_backup_lab_source__" failed: No such file or directory (2)
rsync error: some files/attrs were not transferred (see previous errors) (code 23) at main.c(1951) [Receiver=3.2.7]
rsync: [Receiver] write error: Broken pipe (32)
23
```

이번에는 백업 저장소 마운트 검사를 통과하여 `rsync`가 실행되었다. 그러나 지정한 원격 원본 폴더가 없어 전송에 실패하였다.

직접적인 원인은 `change_dir ... No such file or directory`이다. `Broken pipe`는 앞선 전송 실패에 뒤따라 표시된 메시지다. 스크립트는 종료 코드 `23`으로 끝났고 `BACKUP_OK`를 출력하지 않았다.

## 8. 실패한 백업 폴더 확인

백업본 목록을 확인하였다.

```bash
sudo find /backup/storage01/snapshots \
  -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
```

결과:

```text
20261012-114802
20261012-122510-v1
20261012-123626-v2
20261012-145759
20261012-150433
.incomplete-20261012-151619
```

실패한 작업의 `.incomplete-20261012-151619` 폴더는 남았지만, 같은 시각의 완성본 `20261012-151619`는 생성되지 않았다.

즉, 스크립트가 실패한 전송을 정상 백업으로 표시하지 않았음을 확인하였다. 작업 중 폴더는 실패 원인을 확인할 수 있도록 남으며 자동 삭제되지는 않는다.

## 9. 실패한 작업 폴더 정리

정리 전에 폴더의 내용을 확인하였다.

```bash
sudo ls -la /backup/storage01/snapshots/.incomplete-20261012-151619
```

결과:

```text
total 0
drwx------. 2 root root   6 Oct 12 15:16 .
drwxr-xr-x. 8 root root 162 Oct 12 15:16 ..
```

`.`과 `..` 외에 파일이 없는 빈 폴더인 것을 확인한 후, 해당 폴더만 제거하였다.

```bash
sudo rmdir /backup/storage01/snapshots/.incomplete-20261012-151619
```

`rmdir`는 폴더가 비어 있을 때만 제거하므로, 파일이 남아 있는 실패 폴더를 실수로 통째로 지우지 않는다. 기존 완성 백업본은 제거하지 않았다.

## 10. 실습 결과 비교

| 상황 | 실패한 단계 | 종료 코드 | `BACKUP_OK` | 완성 백업본 |
|---|---|---:|---|---|
| 정상 실행 | 없음 | `0` | 출력됨 | 생성됨 |
| 마운트되지 않은 경로 | `rsync` 실행 전 마운트 검사 | `1` | 출력되지 않음 | 생성되지 않음 |
| 존재하지 않는 원격 원본 경로 | `rsync` 전송 | `23` | 출력되지 않음 | 생성되지 않음 |

첫 번째 실패 실습에서는 `rsync`가 실행되지 않았고, 두 번째 실패 실습에서는 `rsync`가 실행된 뒤 원본 경로 오류로 실패하였다.

## 11. 작업 결과

정상 실행에서는 날짜별 백업본이 생성되고 `BACKUP_OK`와 종료 코드 `0`이 출력되었다. 새 백업본의 파일 내용과 하드 링크 재사용도 확인하였다.

백업 저장소가 마운트되지 않은 경우에는 `rsync` 실행 전에 중단되었고, 원격 원본 경로가 존재하지 않는 경우에는 `rsync` 오류로 중단되었다. 두 경우 모두 `BACKUP_OK`가 출력되지 않았으며 완성 백업본도 생성되지 않았다.

원격 원본 경로 오류로 남은 `.incomplete-*` 폴더는 비어 있음을 확인한 뒤 해당 폴더만 삭제하였다.
