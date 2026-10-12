# backup01 rsync 기반 버전별 파일 백업

## 1. 작업 목적

`storage01`의 NFS 데이터를 `backup01`에 날짜별로 백업하고, `rsync --link-dest`로 변경되지 않은 파일은 하드 링크로 재사용하며 변경된 파일은 별도로 저장되는지 확인하였다.

## 2. 작업 환경

| 항목 | 설정 |
|---|---|
| 원본 서버 | `storage01` (`10.10.10.102`) |
| 백업 서버 | `backup01` (`10.10.10.103`) |
| 원본 경로 | `/srv/nfs/webdata/` |
| 백업 파일시스템 | `/backup/storage01` |
| 기존 백업본 | `/backup/storage01/webdata/` |
| 날짜별 백업 경로 | `/backup/storage01/snapshots/` |
| 원격 읽기 계정 | `backupreader` |
| 원본 파일 소유 계정 | `webshare` |

백업 방향은 다음과 같다.

```text
storage01:/srv/nfs/webdata/
              │
              │ SSH를 통한 rsync
              ▼
backup01:/backup/storage01/snapshots/<날짜-시각>/
```

## 3. 백업 저장소 사전 확인

`backup01`에서 백업용 XFS 파일시스템이 마운트되어 있는지 확인하였다.

```bash
findmnt /backup/storage01
df -hT /backup/storage01
```

결과:

```text
TARGET            SOURCE                          FSTYPE OPTIONS
/backup/storage01 /dev/mapper/vg_backup-lv_backup xfs    rw,relatime,seclabel,attr2,inode64,logbufs=8,logbsize=32k,noquota

Filesystem                      Type  Size  Used Avail Use% Mounted on
/dev/mapper/vg_backup-lv_backup xfs    30G  247M   30G   1% /backup/storage01
```

기존 백업본의 파일과 데이터 크기를 확인하였다.

```bash
sudo du -sh /backup/storage01/webdata
sudo ls -la /backup/storage01/webdata
```

결과:

```text
8.0K    /backup/storage01/webdata

total 8
drwxrws---+ 2 2000 2000 53 Oct  8 16:49 .
drwxr-xr-x. 3 root root 21 Oct  8 16:16 ..
-rw-r--r--+ 1 2000 2000 40 Oct  1 10:21 nfs-status.txt
-rw-rw----+ 1 2000 2000 21 Oct  8 16:49 restore-drill.txt
```

`--numeric-ids`로 원본의 UID/GID를 숫자 그대로 보존하였다. 백업 서버에서 해당 UID/GID가 계정 이름으로 해석되지 않아 `ls` 결과에는 `2000:2000`으로 표시된다.

## 4. 첫 번째 날짜별 백업본 생성

먼저 기존 `/backup/storage01/webdata/`를 비교 대상으로 사용하는 날짜별 백업 디렉터리를 만들었다.

`backup01`에서 실행:

```bash
sudo mkdir -p /backup/storage01/snapshots

snapshot_dir="/backup/storage01/snapshots/$(date +%Y%m%d-%H%M%S)"
printf '%s\n' "$snapshot_dir"

sudo mkdir -m 700 "$snapshot_dir"
```

생성한 경로:

```text
/backup/storage01/snapshots/20261012-114802
```

실제 복사 전에 `--dry-run`으로 예정된 변경 사항을 확인하였다.

```bash
sudo rsync -aA --numeric-ids --itemize-changes --dry-run \
  --link-dest=/backup/storage01/webdata \
  -e 'ssh -i /home/sysadmin/.ssh/id_ed25519_backup01_storage01 -o IdentitiesOnly=yes -o PasswordAuthentication=no -o UserKnownHostsFile=/home/sysadmin/.ssh/known_hosts -o StrictHostKeyChecking=yes' \
  backupreader@10.10.10.102:/srv/nfs/webdata/ \
  "$snapshot_dir/"
```

결과:

```text
.d..tpog.a. ./
cf...p...a. restore-drill.txt
```

`--itemize-changes`는 처리한 항목을 표시하며, `.`은 해당 속성에 변경이 없다는 뜻이다.

- `.d..tpog.a. ./`: 백업 디렉터리의 수정 시각·권한·소유자·그룹·ACL을 원본에 맞춘다.
- `cf...p...a. restore-drill.txt`: 이전 백업본과 권한·ACL이 달라 하드 링크 대신 별도 파일로 만들고 속성을 맞춘다.

오류가 없는 것을 확인하고 `--dry-run`을 제외하여 실제 백업을 실행하였다.

```bash
sudo rsync -aA --numeric-ids --itemize-changes \
  --link-dest=/backup/storage01/webdata \
  -e 'ssh -i /home/sysadmin/.ssh/id_ed25519_backup01_storage01 -o IdentitiesOnly=yes -o PasswordAuthentication=no -o UserKnownHostsFile=/home/sysadmin/.ssh/known_hosts -o StrictHostKeyChecking=yes' \
  backupreader@10.10.10.102:/srv/nfs/webdata/ \
  "$snapshot_dir/"
```

결과:

```text
.d..tpog.a. ./
cf...p...a. restore-drill.txt
```

새 백업본의 파일을 확인하였다.

```bash
sudo ls -la "$snapshot_dir"
```

결과:

```text
total 8
drwxrws---+ 2 2000 2000 53 Oct  8 16:55 .
drwxr-xr-x. 3 root root 29 Oct 12 11:48 ..
-rw-r--r--+ 2 2000 2000 40 Oct  1 10:21 nfs-status.txt
-rw-r--r--+ 1 2000 2000 21 Oct  8 16:49 restore-drill.txt
```

디렉터리는 처음에 `mkdir -m 700`으로 생성했지만, 백업 후에는 `rsync -aA`가 원본 디렉터리의 소유권·권한·ACL을 반영하여 `drwxrws---+`, `2000:2000`으로 표시되었다.

## 5. 첫 번째 백업본의 하드 링크 확인

변경되지 않은 `nfs-status.txt`의 SHA-256 해시를 비교하였다.

```bash
sudo sha256sum \
  /backup/storage01/webdata/nfs-status.txt \
  /backup/storage01/snapshots/20261012-114802/nfs-status.txt
```

결과:

```text
44af27c30d923049b50ee944f86d3b54b46d42022d4433dda210b1f999881677  /backup/storage01/webdata/nfs-status.txt
44af27c30d923049b50ee944f86d3b54b46d42022d4433dda210b1f999881677  /backup/storage01/snapshots/20261012-114802/nfs-status.txt
```

두 경로의 장치번호, inode 번호, 링크 수를 확인하였다.

```bash
sudo stat -c '%d:%i links=%h %n' \
  /backup/storage01/webdata/nfs-status.txt \
  /backup/storage01/snapshots/20261012-114802/nfs-status.txt
```

결과:

```text
64770:132 links=2 /backup/storage01/webdata/nfs-status.txt
64770:132 links=2 /backup/storage01/snapshots/20261012-114802/nfs-status.txt
```

두 파일의 장치번호와 inode 번호가 모두 `64770:132`로 같고 링크 수가 `2`이므로, 두 경로는 같은 실제 파일을 가리키는 하드 링크이다.

반면 `restore-drill.txt`는 기존 백업본과 새 백업본의 권한·ACL에 차이가 있어 별도 파일로 생성되었으며, 새 백업본에서 링크 수가 `1`이었다.

## 6. 버전 비교용 원본 파일 생성

두 시점의 내용을 비교하기 위해 `storage01`에서 `webshare` 계정으로 실습용 파일을 생성하였다.

```bash
printf 'version 1\n' | \
sudo -u webshare tee /srv/nfs/webdata/version-test.txt
```
[O
결과:

```text
version 1
```

백업 전용 계정이 새 파일을 읽을 수 있는지 확인하였다.

```bash
sudo -u backupreader cat /srv/nfs/webdata/version-test.txt
```

결과:

```text
version 1
```

## 7. 버전 1 백업본 A 생성

`backup01`에서 기존 `20261012-114802` 백업본을 비교 대상으로 지정하고, 새로운 백업본 A의 경로를 생성하였다.

```bash
snapshot_v1="/backup/storage01/snapshots/$(date +%Y%m%d-%H%M%S)-v1"
printf 'A 경로: %s\n' "$snapshot_v1"

sudo mkdir -m 700 "$snapshot_v1"
```

결과:

```text
A 경로: /backup/storage01/snapshots/20261012-122510-v1
```

복사 예정 파일을 확인하였다.

```bash
sudo rsync -aA --numeric-ids --itemize-changes --dry-run \
  --link-dest=/backup/storage01/snapshots/20261012-114802 \
  -e 'ssh -i /home/sysadmin/.ssh/id_ed25519_backup01_storage01 -o IdentitiesOnly=yes -o PasswordAuthentication=no -o UserKnownHostsFile=/home/sysadmin/.ssh/known_hosts -o StrictHostKeyChecking=yes' \
  backupreader@10.10.10.102:/srv/nfs/webdata/ \
  "$snapshot_v1/"
```

결과:

```text
.d..tpog.a. ./
>f+++++++++ version-test.txt
```

`>f+++++++++`는 원본 서버에서 `version-test.txt`를 받아 새 백업본에 추가할 예정임을 나타낸다. 이를 확인한 뒤 실제 백업을 실행하였다.

```bash
sudo rsync -aA --numeric-ids --itemize-changes \
  --link-dest=/backup/storage01/snapshots/20261012-114802 \
  -e 'ssh -i /home/sysadmin/.ssh/id_ed25519_backup01_storage01 -o IdentitiesOnly=yes -o PasswordAuthentication=no -o UserKnownHostsFile=/home/sysadmin/.ssh/known_hosts -o StrictHostKeyChecking=yes' \
  backupreader@10.10.10.102:/srv/nfs/webdata/ \
  "$snapshot_v1/"
```

결과:

```text
.d..tpog.a. ./
>f+++++++++ version-test.txt
```

A에 저장된 파일 내용을 확인하였다.

```bash
sudo cat "$snapshot_v1/version-test.txt"
```

결과:

```text
version 1
```

## 8. 원본 파일의 내용 변경

A 백업이 완료된 뒤 `storage01`의 **원본 파일만** 수정하였다. 백업본 A의 파일은 수정하지 않았다.

```bash
printf 'version 2 - changed\n' | \
sudo -u webshare tee /srv/nfs/webdata/version-test.txt
```

결과:

```text
version 2 - changed
```

백업 전용 계정으로 변경된 내용을 다시 확인하였다.

```bash
sudo -u backupreader cat /srv/nfs/webdata/version-test.txt
```

결과:

```text
version 2 - changed
```

## 9. 버전 2 백업본 B 생성

`backup01`에서 A 백업본의 경로를 확인하였다.

```bash
snapshot_v1="/backup/storage01/snapshots/20261012-122510-v1"
sudo cat "$snapshot_v1/version-test.txt"
```

결과:

```text
version 1
```

새 백업본 B의 경로를 만들었다.

```bash
snapshot_v2="/backup/storage01/snapshots/$(date +%Y%m%d-%H%M%S)-v2"
printf 'B 경로: %s\n' "$snapshot_v2"

sudo mkdir -m 700 "$snapshot_v2"
```

결과:

```text
B 경로: /backup/storage01/snapshots/20261012-123626-v2
```

이번에는 A를 `--link-dest`의 비교 대상으로 지정하고, B를 새 목적지로 지정하였다. 먼저 `--dry-run`으로 확인하였다.

```bash
sudo rsync -aA --numeric-ids --itemize-changes --dry-run \
  --link-dest="$snapshot_v1" \
  -e 'ssh -i /home/sysadmin/.ssh/id_ed25519_backup01_storage01 -o IdentitiesOnly=yes -o PasswordAuthentication=no -o UserKnownHostsFile=/home/sysadmin/.ssh/known_hosts -o StrictHostKeyChecking=yes' \
  backupreader@10.10.10.102:/srv/nfs/webdata/ \
  "$snapshot_v2/"
```

결과:

```text
.d..tpog.a. ./
>f.st...... version-test.txt
```

오류가 없는 것을 확인한 뒤 실제 백업을 실행하였다.

```bash
sudo rsync -aA --numeric-ids --itemize-changes \
  --link-dest="$snapshot_v1" \
  -e 'ssh -i /home/sysadmin/.ssh/id_ed25519_backup01_storage01 -o IdentitiesOnly=yes -o PasswordAuthentication=no -o UserKnownHostsFile=/home/sysadmin/.ssh/known_hosts -o StrictHostKeyChecking=yes' \
  backupreader@10.10.10.102:/srv/nfs/webdata/ \
  "$snapshot_v2/"
```

결과:

```text
.d..tpog.a. ./
>f.st...... version-test.txt
```

`>f.st......`는 `version-test.txt`가 새 백업본으로 전송되었고, 이전 백업본과 파일 크기(`s`) 및 수정 시각(`t`)이 달랐음을 나타낸다.

## 10. 버전별 내용과 해시 검증

A와 B의 파일 내용을 확인하였다.

```bash
sudo cat "$snapshot_v1/version-test.txt"
sudo cat "$snapshot_v2/version-test.txt"
```

결과:

```text
version 1
version 2 - changed
```

두 파일의 SHA-256 해시를 비교하였다.

```bash
sudo sha256sum \
  "$snapshot_v1/version-test.txt" \
  "$snapshot_v2/version-test.txt"
```

결과:

```text
3a79bf37b571938d1f2907afb6a643f48088b83769dde8bc58f5ee866a5c3636  /backup/storage01/snapshots/20261012-122510-v1/version-test.txt
d81aa248a8bfc46b8aee5de66d9c51e0a51d1438f1fba7ee0093d1a5c62c3eaa  /backup/storage01/snapshots/20261012-123626-v2/version-test.txt
```

A에는 수정 전 내용, B에는 수정 후 내용이 남았으며 해시값도 서로 다르다.

## 11. 변경 파일과 미변경 파일의 inode 비교

내용이 변경된 `version-test.txt`의 inode를 비교하였다.

```bash
sudo stat -c '%d:%i links=%h %n' \
  /backup/storage01/snapshots/20261012-122510-v1/version-test.txt \
  /backup/storage01/snapshots/20261012-123626-v2/version-test.txt
```

결과:

```text
64770:50331777 links=1 /backup/storage01/snapshots/20261012-122510-v1/version-test.txt
64770:135 links=1 /backup/storage01/snapshots/20261012-123626-v2/version-test.txt
```

두 파일의 inode 번호가 다르고 각각 링크 수가 `1`이므로, 수정 전후 내용이 별도의 파일로 저장되었다.

변경되지 않은 `nfs-status.txt`의 inode도 비교하였다.

```bash
sudo stat -c '%d:%i links=%h %n' \
  /backup/storage01/snapshots/20261012-122510-v1/nfs-status.txt \
  /backup/storage01/snapshots/20261012-123626-v2/nfs-status.txt
```

결과:

```text
64770:132 links=4 /backup/storage01/snapshots/20261012-122510-v1/nfs-status.txt
64770:132 links=4 /backup/storage01/snapshots/20261012-123626-v2/nfs-status.txt
```

두 경로의 장치번호와 inode 번호가 동일하다. `links=4`는 현재 이 실제 파일을 가리키는 하드 링크가 네 개임을 의미하며, 파일 데이터가 네 번 저장됐다는 뜻은 아니다.

## 12. 작업 결과

이번 실습으로 `storage01`의 데이터에 대해 날짜별 백업본 A와 B를 생성하였다.

```text
변경된 version-test.txt
→ A: version 1
→ B: version 2 - changed
→ 서로 다른 inode로 저장

변경되지 않은 nfs-status.txt
→ A와 B에서 모두 조회 가능
→ 같은 inode를 가리키는 하드 링크로 저장
```

이를 통해 **변경된 파일의 이전 버전을 보관하면서, 변경되지 않은 파일의 저장 공간은 재사용하는 방식**을 확인하였다.
