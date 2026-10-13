# 이전 시점 백업본 통합 복원 검증

## 1. 작업 목적

`backup01`에 보관된 이전 시점의 파일을 `storage01`에 복원하고, `web01`의 NFS 마운트와 Apache를 통해 정상적으로 제공되는지 확인하였다.

현재 서비스 중인 파일을 덮어쓰지 않기 위해 백업본을 별도 이름으로 복원하였다. 복원 파일의 SHA-256 값을 비교하여 내용이 일치하는지도 검증하였다.

## 2. 작업 환경

| 서버 | IP 주소 | 역할 |
|---|---|---|
| `backup01` | `10.10.10.103` | 이전 시점 백업본 보관 |
| `storage01` | `10.10.10.102` | 파일 복원 및 NFS 제공 |
| `web01` | `10.10.10.101` | NFS 클라이언트 및 Apache 서비스 |

이번 실습에 사용한 경로는 다음과 같다.

| 항목 | 경로 |
|---|---|
| 이전 시점 백업본 | `/backup/storage01/snapshots/20261012-122510-v1/version-test.txt` |
| `backup01` 임시 파일 | `/home/sysadmin/restore-v1-staging.txt` |
| `storage01` 임시 파일 | `/home/sysadmin/restore-v1-staging.txt` |
| 복원 대상 파일 | `/srv/nfs/webdata/version-restored-v1.txt` |
| 기존 서비스 파일 | `/srv/nfs/webdata/version-test.txt` |
| `web01` NFS 마운트 | `/var/www/intranet/shared` |
| 복원 파일 HTTP 경로 | `/shared/version-restored-v1.txt` |

## 3. 복원 전 파일 상태 확인

`backup01`에서 이전 시점 백업본의 내용과 SHA-256 값을 확인하였다.

```bash
sudo cat /backup/storage01/snapshots/20261012-122510-v1/version-test.txt
sudo sha256sum /backup/storage01/snapshots/20261012-122510-v1/version-test.txt
```

결과:

```text
version 1
3a79bf37b571938d1f2907afb6a643f48088b83769dde8bc58f5ee866a5c3636  /backup/storage01/snapshots/20261012-122510-v1/version-test.txt
```

`storage01`에서는 현재 서비스 중인 파일의 내용과 파일시스템 마운트 상태를 확인하였다.

```bash
sudo -u webshare cat /srv/nfs/webdata/version-test.txt
findmnt /srv/nfs/webdata
```

결과:

```text
version 2 - changed
```

```text
TARGET           SOURCE                            FSTYPE
/srv/nfs/webdata /dev/mapper/vg_storage-lv_webdata xfs
```

이전 백업본은 `version 1`이고 현재 파일은 `version 2 - changed`이다. 현재 파일을 보존하기 위해 이전 백업본을 별도 파일명으로 복원하기로 하였다.

## 4. 임시 파일 경로 확인

`backup01`에서 사용할 임시 파일 경로에 기존 파일이 없는지 확인하였다.

```bash
sudo test ! -e /home/sysadmin/restore-v1-staging.txt && \
  echo BACKUP_STAGING_PATH_FREE
```

결과:

```text
BACKUP_STAGING_PATH_FREE
```

`storage01`의 임시 파일 경로도 SSH를 통해 확인하였다.

```bash
ssh sysadmin@10.10.10.102 \
  'test ! -e /home/sysadmin/restore-v1-staging.txt && echo STORAGE_STAGING_PATH_FREE'
```

결과:

```text
STORAGE_STAGING_PATH_FREE
```

두 서버 모두 해당 임시 파일 경로가 사용 중이지 않은 것을 확인하였다.

## 5. backup01에서 복원용 파일 준비

`backup01`에서 이전 시점 백업본을 `sysadmin` 계정이 전송할 수 있는 임시 파일로 복사하였다.

```bash
sudo install -m 600 -o sysadmin -g sysadmin \
  /backup/storage01/snapshots/20261012-122510-v1/version-test.txt \
  /home/sysadmin/restore-v1-staging.txt
```

임시 파일의 SHA-256 값을 확인하였다.

```bash
sha256sum /home/sysadmin/restore-v1-staging.txt
```

결과:

```text
3a79bf37b571938d1f2907afb6a643f48088b83769dde8bc58f5ee866a5c3636  /home/sysadmin/restore-v1-staging.txt
```

임시 파일의 해시가 이전 시점 백업본의 해시와 일치하였다.

## 6. storage01로 임시 파일 전송

`backup01`에서 `scp`를 사용하여 임시 파일을 `storage01`의 `sysadmin` 홈 디렉터리로 전송하였다.

```bash
scp /home/sysadmin/restore-v1-staging.txt \
  sysadmin@10.10.10.102:/home/sysadmin/
```

`storage01`에서 전송된 파일의 내용과 SHA-256 값을 확인하였다.

```bash
cat /home/sysadmin/restore-v1-staging.txt
sha256sum /home/sysadmin/restore-v1-staging.txt
```

결과:

```text
version 1
3a79bf37b571938d1f2907afb6a643f48088b83769dde8bc58f5ee866a5c3636  /home/sysadmin/restore-v1-staging.txt
```

전송 후에도 파일 내용과 해시가 백업본과 일치하였다.

기존 서비스 파일은 변경되지 않았는지 다시 확인하였다.

```bash
sudo -u webshare cat /srv/nfs/webdata/version-test.txt
```

결과:

```text
version 2 - changed
```

## 7. storage01에 별도 파일로 복원

복원 대상 경로에 기존 파일이 없는지 먼저 확인하였다.

```bash
findmnt /srv/nfs/webdata

sudo test ! -e /srv/nfs/webdata/version-restored-v1.txt && \
  echo RESTORE_TARGET_FREE
```

결과:

```text
TARGET           SOURCE                            FSTYPE
/srv/nfs/webdata /dev/mapper/vg_storage-lv_webdata xfs

RESTORE_TARGET_FREE
```

NFS로 제공할 XFS 파일시스템이 마운트되어 있고, 복원 대상 파일명이 사용 중이지 않은 것을 확인하였다.

임시 파일을 `webshare` 소유의 새 파일로 복사하였다.

```bash
sudo install -m 644 -o webshare -g webshare \
  /home/sysadmin/restore-v1-staging.txt \
  /srv/nfs/webdata/version-restored-v1.txt
```

복원 파일의 내용, SHA-256 값, 소유권 및 권한을 확인하였다.

```bash
sudo -u webshare cat /srv/nfs/webdata/version-restored-v1.txt
sudo sha256sum /srv/nfs/webdata/version-restored-v1.txt
sudo ls -l /srv/nfs/webdata/version-restored-v1.txt
```

결과:

```text
version 1
3a79bf37b571938d1f2907afb6a643f48088b83769dde8bc58f5ee866a5c3636  /srv/nfs/webdata/version-restored-v1.txt
-rw-r--r--. 1 webshare webshare 10 Oct 13 09:39 /srv/nfs/webdata/version-restored-v1.txt
```

복원 파일의 해시가 백업본과 일치하며, 파일 소유자가 `webshare`인 것을 확인하였다.

기존 서비스 파일의 내용도 다시 확인하였다.

```bash
sudo -u webshare cat /srv/nfs/webdata/version-test.txt
```

결과:

```text
version 2 - changed
```

기존 파일은 덮어쓰지 않았으며 이전 버전은 별도 파일로 복원되었다.

## 8. web01의 NFS 접근 검증

`web01`에서 NFS 공유가 마운트되어 있는지 확인하였다.

```bash
findmnt /var/www/intranet/shared
```

결과:

```text
TARGET                   SOURCE                        FSTYPE
/var/www/intranet/shared 10.10.10.102:/srv/nfs/webdata nfs4
```

`webshare` 계정으로 복원 파일을 읽고 SHA-256 값을 확인하였다.

```bash
sudo -u webshare cat \
  /var/www/intranet/shared/version-restored-v1.txt

sudo -u webshare sha256sum \
  /var/www/intranet/shared/version-restored-v1.txt
```

결과:

```text
version 1
3a79bf37b571938d1f2907afb6a643f48088b83769dde8bc58f5ee866a5c3636  /var/www/intranet/shared/version-restored-v1.txt
```

`web01`에서 NFS를 통해 읽은 복원 파일의 내용과 해시가 백업본과 일치하였다.

## 9. Apache를 통한 제공 검증

`web01`에서 Apache가 복원 파일을 제공하는지 확인하였다.

```bash
curl -sI http://127.0.0.1/shared/version-restored-v1.txt | head -n 1
curl http://127.0.0.1/shared/version-restored-v1.txt
```

결과:

```text
HTTP/1.1 200 OK
version 1
```

기존 서비스 파일도 계속 이전과 동일하게 제공되는지 확인하였다.

```bash
curl http://127.0.0.1/shared/version-test.txt
```

결과:

```text
version 2 - changed
```

복원 파일은 Apache를 통해 정상적으로 제공되었고, 기존 서비스 파일은 변경되지 않았다.

## 10. 작업 결과

`backup01`의 이전 시점 백업본을 `storage01`에 별도 파일로 복원하였다. 백업본, 전송용 임시 파일, 복원 파일, `web01`에서 NFS로 읽은 파일의 SHA-256 값이 모두 일치하였다.

`web01`의 Apache는 복원 파일을 `HTTP/1.1 200 OK`와 `version 1`로 제공하였다. 기존 `version-test.txt`는 복원 전후 모두 `version 2 - changed`로 유지되었다.

```text
backup01 이전 시점 백업본
→ storage01 별도 파일로 복원
→ web01 NFS 접근
→ Apache HTTP 제공
```

이번 실습으로 이전 시점의 파일을 현재 파일에 영향을 주지 않고 복원하여, 스토리지·백업·NFS·웹 서비스가 연결된 복원 경로를 검증하였다.
