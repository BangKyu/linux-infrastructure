# storage01 데이터 백업 및 복원 검증

## 1. 작업 목적

`storage01`의 NFS 공유 데이터를 별도 서버인 `backup01`에 백업하고, 파일을 삭제한 뒤 백업본으로 복원하는 실습을 진행하였다.

이번 실습에서는 다음 항목을 확인하였다.

- 백업 전용 계정의 읽기 권한 구성
- SSH 키를 이용한 서버 간 접속
- `rsync`를 이용한 파일 단위 백업
- SHA-256 해시를 이용한 파일 내용 검증
- 삭제된 파일의 복원
- 복원 후 `web01`의 NFS 및 Apache 서비스 확인

## 2. 작업 환경

| 서버 | IP 주소 | 역할 |
|---|---|---|
| `storage01` | `10.10.10.102` | 백업할 원본 데이터 보관 |
| `backup01` | `10.10.10.103` | 백업 데이터 보관 |
| `web01` | `10.10.10.101` | NFS 데이터 사용 및 웹 서비스 제공 |

| 항목 | 경로 |
|---|---|
| 원본 데이터 | `storage01:/srv/nfs/webdata` |
| 백업 데이터 | `backup01:/backup/storage01/webdata` |
| NFS 클라이언트 마운트 | `web01:/var/www/intranet/shared` |
| 웹에서 확인하는 주소 | `http://127.0.0.1/shared/` |

## 3. 원본 데이터 확인

`storage01`에서 원본 파일시스템과 용량을 확인하였다.

```bash
df -hT /srv/nfs/webdata
```

결과:

```text
Filesystem                        Type  Size  Used Avail Use% Mounted on
/dev/mapper/vg_storage-lv_webdata xfs    16G  148M   16G   1% /srv/nfs/webdata
```

공유 데이터 계정과 원본 디렉터리의 파일을 확인하였다.

```bash
id webshare
sudo -u webshare ls -la /srv/nfs/webdata
sudo du -sh /srv/nfs/webdata
```

결과:

```text
uid=2000(webshare) gid=2000(webshare) groups=2000(webshare)

total 4
drwxrws---. 2 webshare webshare 28 Oct  6 14:44 .
drwxr-xr-x. 3 root     root     21 Sep 29 17:42 ..
-rw-r--r--. 1 webshare webshare 40 Oct  1 10:21 nfs-status.txt

4.0K    /srv/nfs/webdata
```

`df`의 사용량은 파일시스템 전체 기준이고, `du`의 값은 해당 디렉터리에 저장된 데이터 기준이므로 서로 다르게 표시된다.

`rsync` 설치 여부도 확인하였다.

```bash
rpm -q rsync
```

결과:

```text
rsync-3.2.7-1.el9_8.x86_64
```

## 4. 백업 저장소 확인

`backup01`에서 백업용 파일시스템을 확인하였다.

```bash
df -hT /backup/storage01
```

결과:

```text
Filesystem                      Type  Size  Used Avail Use% Mounted on
/dev/mapper/vg_backup-lv_backup xfs    30G  247M   30G   1% /backup/storage01
```

`backup01`에는 처음에 `rsync`가 설치되어 있지 않았다.

```bash
rpm -q rsync
```

결과:

```text
package rsync is not installed
```

관리자 권한으로 설치하였다.

```bash
sudo dnf install -y rsync
```

설치 결과:

```text
Installed:
  rsync-3.2.7-1.el9_8.x86_64

Complete!
```

백업 파일을 저장할 디렉터리를 준비하였다.

```bash
sudo install -d -m 700 /backup/storage01/webdata
```

## 5. 백업 전용 계정 권한 구성

`storage01`에서 백업 데이터를 읽을 전용 계정 `backupreader`를 구성하였다. 이 계정은 공유 데이터의 소유자인 `webshare` 그룹에 속하지 않도록 하였다.

```bash
id backupreader
```

결과:

```text
uid=2001(backupreader) gid=2001(backupreader) groups=2001(backupreader)
```

비밀번호를 이용한 로그인을 막기 위해 계정 비밀번호를 잠갔다.

```bash
sudo passwd -l backupreader
sudo passwd -S backupreader
```

결과:

```text
Locking password for user backupreader.
passwd: Success

backupreader LK 2026-10-08 0 99999 7 -1 (Password locked.)
```

`backupreader`가 원본 디렉터리를 탐색하고 파일을 읽을 수 있도록 ACL을 설정하였다.

```bash
sudo setfacl -m u:backupreader:r-x /srv/nfs/webdata
sudo setfacl -m u:backupreader:r-- /srv/nfs/webdata/nfs-status.txt
sudo setfacl -m d:u:backupreader:r-x /srv/nfs/webdata
```

디렉터리의 ACL을 확인하였다.

```bash
getfacl /srv/nfs/webdata
```

결과:

```text
# file: srv/nfs/webdata
# owner: webshare
# group: webshare
# flags: -s-
user::rwx
user:backupreader:r-x
group::rwx
mask::rwx
other::---
default:user::rwx
default:user:backupreader:r-x
default:group::rwx
default:mask::rwx
default:other::---
```

실제로 파일을 읽을 수 있는지 확인하였다.

```bash
sudo -u backupreader cat /srv/nfs/webdata/nfs-status.txt
```

결과:

```text
This file is served from storage01 NFS.
```

반면 원본 디렉터리에 쓰기 권한은 없는 것을 확인하였다.

```bash
sudo -u backupreader test -w /srv/nfs/webdata
echo $?
```

결과:

```text
1
```

`test` 명령의 종료 상태 `1`은 `backupreader`에게 해당 디렉터리의 쓰기 권한이 없음을 의미한다.

## 6. SSH 키 인증 확인

`backup01`의 `sysadmin` 계정에서 백업 접속용 SSH 키를 생성하였다.

```bash
ssh-keygen -t ed25519 \
  -f ~/.ssh/id_ed25519_backup01_storage01 \
  -C "backup01-to-storage01"
```

생성된 공개키의 지문을 확인하였다.

```bash
ssh-keygen -lf ~/.ssh/id_ed25519_backup01_storage01.pub
```

결과:

```text
256 SHA256:FtLSQilcOeNZlNgVHkerQPf/LewTqYGw1girqM00xv4 backup01-to-storage01 (ED25519)
```

공개키는 `storage01`의 `backupreader` 계정에 등록하였다. 접속 출발지를 `backup01`의 IP인 `10.10.10.103`으로 제한하는 옵션도 적용하였다.

```text
restrict,from="10.10.10.103" ssh-ed25519 ...
```

`backup01`에서 비밀번호 인증 없이 `storage01`에 접속되는지 확인하였다.

```bash
ssh -i ~/.ssh/id_ed25519_backup01_storage01 \
  -o IdentitiesOnly=yes \
  -o PasswordAuthentication=no \
  backupreader@10.10.10.102 'id'
```

결과:

```text
uid=2001(backupreader) gid=2001(backupreader) groups=2001(backupreader) context=unconfined_u:unconfined_r:unconfined_t:s0-s0:c0.c1023
```

비밀번호 인증을 끈 상태에서도 SSH 키로 접속이 성공하였다.

## 7. 첫 번째 백업

백업은 `backup01`에서 원격 원본 데이터를 가져오는 방식으로 진행하였다.

먼저 `--dry-run`으로 실제 파일을 변경하지 않고 복사 대상을 확인하였다.

```bash
sudo rsync -aA --numeric-ids --itemize-changes --dry-run \
  -e 'ssh -i /home/sysadmin/.ssh/id_ed25519_backup01_storage01 -o IdentitiesOnly=yes -o PasswordAuthentication=no -o UserKnownHostsFile=/home/sysadmin/.ssh/known_hosts -o StrictHostKeyChecking=yes' \
  backupreader@10.10.10.102:/srv/nfs/webdata/ \
  /backup/storage01/webdata/
```

결과에서 `nfs-status.txt`가 새로 복사될 파일로 표시되었다.

```text
.d..tpog.a. ./
>f+++++++++ nfs-status.txt
```

이후 `--dry-run`을 제외하고 실제 백업을 실행하였다.

```bash
sudo rsync -aA --numeric-ids --itemize-changes \
  -e 'ssh -i /home/sysadmin/.ssh/id_ed25519_backup01_storage01 -o IdentitiesOnly=yes -o PasswordAuthentication=no -o UserKnownHostsFile=/home/sysadmin/.ssh/known_hosts -o StrictHostKeyChecking=yes' \
  backupreader@10.10.10.102:/srv/nfs/webdata/ \
  /backup/storage01/webdata/
```

여기서 `-a`는 기본 파일 속성을 보존하고, `-A`는 ACL을 보존한다. `--numeric-ids`는 사용자·그룹 이름 대신 숫자 UID/GID를 기준으로 소유권을 유지한다.

백업 파일을 확인하였다.

```bash
sudo cat /backup/storage01/webdata/nfs-status.txt
sudo sha256sum /backup/storage01/webdata/nfs-status.txt
```

결과:

```text
This file is served from storage01 NFS.
44af27c30d923049b50ee944f86d3b54b46d42022d4433dda210b1f999881677  /backup/storage01/webdata/nfs-status.txt
```

원본 파일의 SHA-256 해시도 동일한 것을 확인하였다.

```text
44af27c30d923049b50ee944f86d3b54b46d42022d4433dda210b1f999881677  /srv/nfs/webdata/nfs-status.txt
```

## 8. 복원 실습용 파일 생성

복원 시험을 위해 `storage01`에서 `webshare` 계정으로 파일을 생성하였다.

```bash
printf 'backup restore drill\n' | \
sudo -u webshare tee /srv/nfs/webdata/restore-drill.txt
```

결과:

```text
backup restore drill
```

원본 파일의 내용을 확인하였다.

```bash
sudo -u backupreader cat /srv/nfs/webdata/restore-drill.txt
```

결과:

```text
backup restore drill
```

`web01`에서도 Apache를 통해 파일이 제공되는 것을 확인하였다.

```bash
curl -I http://127.0.0.1/shared/restore-drill.txt
curl http://127.0.0.1/shared/restore-drill.txt
```

결과:

```text
HTTP/1.1 200 OK

backup restore drill
```

## 9. 새 파일 백업 및 무결성 확인

`backup01`에서 `rsync`를 다시 실행하여 새로 생성한 파일을 백업하였다.

```bash
sudo rsync -aA --numeric-ids --itemize-changes \
  -e 'ssh -i /home/sysadmin/.ssh/id_ed25519_backup01_storage01 -o IdentitiesOnly=yes -o PasswordAuthentication=no -o UserKnownHostsFile=/home/sysadmin/.ssh/known_hosts -o StrictHostKeyChecking=yes' \
  backupreader@10.10.10.102:/srv/nfs/webdata/ \
  /backup/storage01/webdata/
```

결과:

```text
.d..t...... ./
>f+++++++++ restore-drill.txt
```

백업본의 내용과 SHA-256 해시를 확인하였다.

```bash
sudo cat /backup/storage01/webdata/restore-drill.txt
sudo sha256sum /backup/storage01/webdata/restore-drill.txt
```

결과:

```text
backup restore drill
7904f5099e8d22972a1187a08349c0e78c2c976aa771f92bc9974774419af4c2  /backup/storage01/webdata/restore-drill.txt
```

원본 파일의 SHA-256 해시도 확인하였다.

```bash
ssh -i ~/.ssh/id_ed25519_backup01_storage01 \
  -o IdentitiesOnly=yes \
  backupreader@10.10.10.102 \
  'sha256sum /srv/nfs/webdata/restore-drill.txt'
```

결과:

```text
7904f5099e8d22972a1187a08349c0e78c2c976aa771f92bc9974774419af4c2  /srv/nfs/webdata/restore-drill.txt
```

원본과 백업본의 해시가 일치하여 파일 내용이 동일한 것을 확인하였다.

## 10. 원본 파일 삭제 및 서비스 영향 확인

복원 상황을 재현하기 위해 `storage01`에서 **실습용 파일 하나만** 삭제하였다.

```bash
sudo -u webshare rm /srv/nfs/webdata/restore-drill.txt
sudo -u webshare ls -la /srv/nfs/webdata
```

결과:

```text
total 4
drwxrws---+ 2 webshare webshare 28 Oct  8 16:54 .
drwxr-xr-x. 3 root     root     21 Sep 29 17:42 ..
-rw-r--r--+ 1 webshare webshare 40 Oct  1 10:21 nfs-status.txt
```

기존 `nfs-status.txt`는 남아 있고, 실습용 파일만 삭제되었다.

`web01`에서 삭제된 파일의 URL을 요청하자 `404 Not Found`가 표시되었다.

```bash
curl http://127.0.0.1/shared/restore-drill.txt
```

결과 중 일부:

```text
<title>404 Not Found</title>
<h1>Not Found</h1>
```

따라서 원본 파일의 삭제가 웹 서비스에도 반영된 것을 확인하였다.

## 11. 백업본으로 파일 복원

`backup01`에 보관된 파일을 `storage01`의 `sysadmin` 홈 디렉터리로 먼저 전송하였다.

```bash
sudo scp -p \
  -o UserKnownHostsFile=/home/sysadmin/.ssh/known_hosts \
  -o StrictHostKeyChecking=yes \
  /backup/storage01/webdata/restore-drill.txt \
  sysadmin@10.10.10.102:/home/sysadmin/restore-drill.txt
```

그다음 `storage01`에서 파일의 소유자와 권한을 지정하여 원래 데이터 디렉터리에 설치하였다.

```bash
sudo install -p -m 644 -o webshare -g webshare \
  /home/sysadmin/restore-drill.txt \
  /srv/nfs/webdata/restore-drill.txt
```

백업 전용 계정의 읽기 ACL을 다시 설정하고 SELinux 파일 문맥을 확인하였다.

```bash
sudo setfacl -m u:backupreader:r-- \
  /srv/nfs/webdata/restore-drill.txt

sudo restorecon -v /srv/nfs/webdata/restore-drill.txt
```

이번 복원은 `scp`와 `install`을 사용했기 때문에 백업 파일의 모든 ACL과 SELinux 속성이 자동으로 복원된다고 가정하지 않았다. 필요한 권한을 다시 설정한 뒤 확인하였다.

## 12. 복원 결과 검증

`storage01`에서 복원된 파일의 소유권과 내용을 확인하였다.

```bash
sudo ls -ln /srv/nfs/webdata/restore-drill.txt
sudo -u webshare sha256sum /srv/nfs/webdata/restore-drill.txt
sudo -u backupreader cat /srv/nfs/webdata/restore-drill.txt
```

결과:

```text
-rw-r--r--+ 1 2000 2000 21 Oct  8 16:49 /srv/nfs/webdata/restore-drill.txt

7904f5099e8d22972a1187a08349c0e78c2c976aa771f92bc9974774419af4c2  /srv/nfs/webdata/restore-drill.txt

backup restore drill
```

소유권은 `webshare`의 UID/GID인 `2000:2000`으로 설정되었고, 복원 전 원본 및 백업본과 SHA-256 해시가 일치하였다.

`web01`에서 파일이 다시 제공되는지도 확인하였다.

```bash
curl -I http://127.0.0.1/shared/restore-drill.txt
curl http://127.0.0.1/shared/restore-drill.txt
curl -I http://127.0.0.1/shared/nfs-status.txt
```

결과:

```text
HTTP/1.1 200 OK

backup restore drill

HTTP/1.1 200 OK
```

복원한 파일과 기존 NFS 파일이 모두 Apache를 통해 제공되었다.

## 13. 실습 결과와 범위

이번 실습을 통해 `storage01`의 파일을 `backup01`에 백업하고, 원본에서 삭제된 실습용 파일을 복원하였다. 복원 전후의 SHA-256 해시가 일치했으며, `web01`에서도 파일을 다시 읽을 수 있었다.

