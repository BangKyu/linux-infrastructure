# web01 NFS 클라이언트 구성

## 1. 작업 목적

`storage01`에서 제공하는 NFS 공유 디렉터리를 `web01`에 연결하였다.

NFS 공유 디렉터리를 향후 Apache 웹 서비스에서 사용할 수 있도록 `/var/www/intranet/shared`에 마운트하고, 동일한 UID/GID를 사용하는 `webshare` 계정을 통해 파일을 관리하도록 구성하였다.

## 2. NFS 연결 정보

| 항목 | 설정 |
|---|---|
| NFS 서버 | `storage01` |
| 서버 IP | `10.10.10.102` |
| 서버 공유 경로 | `/srv/nfs/webdata` |
| 클라이언트 | `web01` |
| 클라이언트 IP | `10.10.10.101` |
| 마운트 지점 | `/var/www/intranet/shared` |
| NFS 버전 | NFSv4.2 |
| 서비스 계정 | `webshare` |
| UID/GID | `2000:2000` |

전체 연결 구조는 다음과 같다.

```text
web01
/var/www/intranet/shared
        │
        │ NFSv4.2
        ▼
storage01
/srv/nfs/webdata
        │
        ▼
XFS → LVM → RAID 6
```

## 3. 서버 통신 확인

`web01`에서 `storage01`로 통신할 수 있는지 확인하였다.

```bash
ping -c 3 10.10.10.102
```

패킷 손실 없이 정상적으로 통신되는 것을 확인하였다.

## 4. NFS 클라이언트 패키지 설치

NFS 공유를 마운트하기 위해 `nfs-utils` 패키지를 설치하였다.

```bash
sudo dnf install -y nfs-utils
```

설치 확인:

```bash
rpm -q nfs-utils
```

## 5. 서비스 계정 구성

NFS에서는 서버와 클라이언트가 파일 소유자를 UID와 GID 숫자로 구분한다.

`storage01`과 동일한 파일 소유권을 사용하기 위해 UID/GID `2000`의 사용 여부를 확인하였다.

```bash
getent passwd 2000
getent group 2000
```

사용 중인 UID와 GID가 없는 것을 확인한 후 `webshare` 계정을 생성하였다.

```bash
sudo groupadd -g 2000 webshare
sudo useradd -u 2000 -g webshare -M -s /sbin/nologin webshare
```

계정 정보 확인:

```bash
id webshare
```

결과:

```text
uid=2000(webshare) gid=2000(webshare) groups=2000(webshare)
```

서버와 클라이언트에서 동일한 UID/GID를 사용하므로 NFS를 통해 생성한 파일의 소유권이 동일하게 유지된다.

## 6. 마운트 지점 생성

NFS 공유를 연결할 디렉터리를 생성하였다.

```bash
sudo mkdir -p /var/www/intranet/shared
```

서버의 공유 경로와 클라이언트의 마운트 지점은 서로 같을 필요가 없다.

```text
서버 공유 경로   : /srv/nfs/webdata
클라이언트 경로 : /var/www/intranet/shared
```

## 7. NFS 수동 마운트

영구 마운트를 설정하기 전에 NFSv4.2를 사용하여 수동으로 연결하였다.

```bash
sudo mount -t nfs -o vers=4.2 \
10.10.10.102:/srv/nfs/webdata \
/var/www/intranet/shared
```

마운트 상태 확인:

```bash
findmnt /var/www/intranet/shared
```

확인 결과:

```text
TARGET                    SOURCE                         FSTYPE
/var/www/intranet/shared  10.10.10.102:/srv/nfs/webdata nfs4
```

파일시스템 용량 확인:

```bash
df -hT /var/www/intranet/shared
```

결과:

```text
Filesystem                    Type Size Used Avail Use% Mounted on
10.10.10.102:/srv/nfs/webdata nfs4  12G 118M   12G   1% /var/www/intranet/shared
```

## 8. 읽기·쓰기 검증

`webshare` 사용자로 NFS 공유 디렉터리에 테스트 파일을 생성하였다.

```bash
sudo -u webshare sh -c \
'echo "NFS write test from web01" > /var/www/intranet/shared/web01-test.txt'
```

파일 내용 확인:

```bash
sudo -u webshare cat \
/var/www/intranet/shared/web01-test.txt
```

결과:

```text
NFS write test from web01
```

파일의 숫자 UID/GID를 확인하였다.

```bash
sudo -u webshare ls -ln \
/var/www/intranet/shared/web01-test.txt
```

서버에서도 다음과 같이 UID/GID `2000:2000`으로 확인되었다.

```text
-rw-r--r--. 1 2000 2000 26 Sep 30 11:31 web01-test.txt
```

이를 통해 NFS 클라이언트의 쓰기 작업과 서버·클라이언트 간 UID/GID 일치가 정상임을 확인하였다.

## 9. root_squash 검증

일반 `webshare` 계정은 공유 디렉터리에서 파일을 생성하고 읽을 수 있었지만, `web01`의 root 계정은 파일에 접근할 수 없었다.

```bash
sudo ls -ln \
/var/www/intranet/shared/web01-test.txt
```

결과:

```text
ls: cannot access '/var/www/intranet/shared/web01-test.txt': Permission denied
```

공유 디렉터리의 권한은 다음과 같다.

```text
drwxrws---. webshare webshare
```

NFS 서버에 설정한 `root_squash`에 의해 클라이언트의 root는 서버에서 익명 사용자로 변환된다.

공유 디렉터리는 기타 사용자 권한이 `---`이므로 익명 사용자는 디렉터리에 접근할 수 없다.

```text
web01 root
    ↓ root_squash
익명 사용자
    ↓
공유 디렉터리의 기타 사용자 권한 없음
    ↓
Permission denied
```

이 결과를 통해 `root_squash`가 정상적으로 적용되고 있음을 확인하였다.

## 10. 수동 마운트 해제

읽기·쓰기 테스트를 완료한 후 수동 마운트를 해제하였다.

```bash
sudo umount /var/www/intranet/shared
```

해제 확인:

```bash
findmnt /var/www/intranet/shared
```

출력이 없는 것을 통해 마운트가 정상적으로 해제된 것을 확인하였다.

## 11. 영구 마운트 설정

기존 `/etc/fstab` 파일을 백업하였다.

```bash
sudo cp -a /etc/fstab /etc/fstab.bak-nfs
```

백업 파일 확인:

```bash
ls -l /etc/fstab.bak-nfs
```

`/etc/fstab`에 다음 항목을 추가하였다.

```fstab
10.10.10.102:/srv/nfs/webdata /var/www/intranet/shared nfs4 rw,_netdev,vers=4.2 0 0
```

각 옵션의 의미는 다음과 같다.

| 옵션 | 의미 |
|---|---|
| `nfs4` | NFSv4 파일시스템 사용 |
| `rw` | 읽기·쓰기 허용 |
| `_netdev` | 네트워크가 준비된 후 마운트 |
| `vers=4.2` | NFSv4.2 사용 |
| `0 0` | dump 및 로컬 파일시스템 검사 제외 |

설정 문법을 검사하였다.

```bash
sudo findmnt --verify
```

결과:

```text
Success, no errors or warnings detected
```

설정을 적용하였다.

```bash
sudo systemctl daemon-reload
sudo mount -a
```

## 12. fstab 마운트 검증

`/etc/fstab` 설정에 따라 NFS가 정상적으로 마운트되는지 확인하였다.

```bash
findmnt -no SOURCE,FSTYPE,OPTIONS \
/var/www/intranet/shared
```

결과:

```text
10.10.10.102:/srv/nfs/webdata nfs4 rw,relatime,vers=4.2,...
```

`webshare` 계정으로 파일을 생성하였다.

```bash
sudo -u webshare sh -c \
'echo "NFS fstab mount test" > /var/www/intranet/shared/fstab-test.txt'
```

파일 내용 확인:

```bash
sudo -u webshare cat \
/var/www/intranet/shared/fstab-test.txt
```

결과:

```text
NFS fstab mount test
```

검증 후 테스트 파일을 삭제하였다.

```bash
sudo -u webshare rm \
/var/www/intranet/shared/fstab-test.txt
```

## 13. 재부팅 후 자동 마운트 검증

`/etc/fstab` 영구 마운트 설정을 검증하기 위해 `web01`을 재부팅하였다.

```bash
sudo reboot
```

재접속 후 마운트 상태를 확인하였다.

```bash
findmnt /var/www/intranet/shared
df -hT /var/www/intranet/shared
```

결과:

```text
TARGET                    SOURCE                         FSTYPE
/var/www/intranet/shared  10.10.10.102:/srv/nfs/webdata nfs4
```

```text
Filesystem                    Type Size Used Avail Use% Mounted on
10.10.10.102:/srv/nfs/webdata nfs4  12G 118M   12G   1% /var/www/intranet/shared
```

재부팅 후에도 NFSv4.2 공유가 자동으로 마운트된 것을 확인하였다.

## 14. 재부팅 후 읽기·쓰기 검증

재부팅 후 `webshare` 계정으로 테스트 파일을 생성하였다.

```bash
sudo -u webshare sh -c \
'echo "NFS reboot test" > /var/www/intranet/shared/reboot-test.txt'
```

파일 내용 확인:

```bash
sudo -u webshare cat \
/var/www/intranet/shared/reboot-test.txt
```

결과:

```text
NFS reboot test
```

검증 후 테스트 파일을 삭제하였다.

```bash
sudo -u webshare rm \
/var/www/intranet/shared/reboot-test.txt
```

이를 통해 재부팅 후에도 NFS 자동 마운트와 읽기·쓰기 기능이 정상적으로 작동하는 것을 확인하였다.

## 15. 시스템 상태 확인

실패 상태인 systemd 서비스가 없는지 확인하였다.

```bash
systemctl --failed
```

결과:

```text
0 loaded units listed.
```

## 16. 최종 검증

최종적으로 다음 항목을 검증하였다.

```text
storage01 통신             정상
NFSv4.2 수동 마운트       정상
webshare 읽기·쓰기        정상
UID/GID 2000:2000 유지    정상
root_squash               정상
fstab 문법 검사           정상
fstab 영구 마운트         정상
재부팅 후 자동 마운트     정상
재부팅 후 읽기·쓰기       정상
systemd 실패 서비스       없음
```
