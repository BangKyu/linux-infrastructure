# storage01 NFS 서버 구성

## 1. 작업 목적

`storage01`의 RAID 6, LVM 및 XFS 기반 스토리지를 `web01`에서 사용할 수 있도록 NFS 서버를 구성하였다.

NFS 공유는 `web01`에서만 접근할 수 있도록 제한하고, 클라이언트의 root 권한이 서버에 그대로 적용되지 않도록 `root_squash`를 사용하였다.

## 2. NFS 구성 정보

| 항목         | 설정                 |
| ---------- | ------------------ |
| NFS 서버     | `storage01`        |
| 서버 IP      | `10.10.10.102`     |
| 공유 디렉터리    | `/srv/nfs/webdata` |
| 허용 클라이언트   | `10.10.10.101`     |
| 접근 권한      | 읽기·쓰기              |
| 동기화 방식     | `sync`             |
| root 권한 제한 | `root_squash`      |
| 서비스 계정     | `webshare`         |
| UID/GID    | `2000:2000`        |

전체 구성은 다음과 같다.

```text
/dev/md0
    ↓
vg_storage
    ↓
lv_webdata
    ↓
XFS
    ↓
/srv/nfs/webdata
    ↓ NFS
web01
```

## 3. 공유 디렉터리 확인

NFS로 공유할 디렉터리가 정상적으로 마운트되었는지 확인하였다.

```bash
findmnt /srv/nfs/webdata
```

확인 결과:

```text
SOURCE                            FSTYPE MOUNTPOINT
/dev/mapper/vg_storage-lv_webdata xfs    /srv/nfs/webdata
```

파일시스템 크기는 약 12GB이며 XFS로 구성되어 있다.

## 4. NFS 패키지 설치

NFS 서버 구성에 필요한 `nfs-utils` 패키지를 설치하였다.

```bash
sudo dnf install -y nfs-utils
```

설치 확인:

```bash
rpm -q nfs-utils
nfs-utils-2.5.4-42.el9.x86_64
```

## 5. 서비스 계정 구성

NFS 서버와 클라이언트에서 파일 소유권을 동일하게 인식할 수 있도록 전용 서비스 계정을 생성하였다.

먼저 UID와 GID `2000`의 사용 여부를 확인하였다.

```bash
getent passwd 2000
getent group 2000
```

사용 중인 계정과 그룹이 없는 것을 확인한 후 `webshare` 계정을 생성하였다.

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

`/sbin/nologin`을 사용하여 해당 계정으로 직접 로그인할 수 없도록 설정하였다.

## 6. 공유 디렉터리 권한 설정

NFS 공유 디렉터리의 소유자를 `webshare`로 변경하였다.

```bash
sudo chown webshare:webshare /srv/nfs/webdata
```

소유자와 그룹에게 전체 권한을 부여하고 SetGID를 적용하였다.

```bash
sudo chmod 2770 /srv/nfs/webdata
```

확인:

```bash
ls -ld /srv/nfs/webdata
```

결과:

```text
drwxrws---. webshare webshare /srv/nfs/webdata
```

`2770`의 의미는 다음과 같다.

| 값   | 의미           |
| --- | ------------ |
| `2` | SetGID 적용    |
| `7` | 소유자 읽기·쓰기·접근 |
| `7` | 그룹 읽기·쓰기·접근  |
| `0` | 기타 사용자 접근 금지 |

SetGID가 적용되어 공유 디렉터리 안에 생성되는 파일과 디렉터리는 `webshare` 그룹을 상속한다.

## 7. 로컬 읽기·쓰기 검증

NFS를 공유하기 전에 `webshare` 계정으로 디렉터리에 파일을 생성할 수 있는지 확인하였다.

```bash
sudo -u webshare sh -c \
'echo "local storage write test" > /srv/nfs/webdata/local-test.txt'
```

파일 내용 확인:

```bash
sudo -u webshare cat /srv/nfs/webdata/local-test.txt
```

검증 후 테스트 파일을 삭제하였다.

```bash
sudo -u webshare rm /srv/nfs/webdata/local-test.txt
```

## 8. NFS 공유 설정

기존 설정 파일을 백업하였다.

```bash
sudo cp -a /etc/exports /etc/exports.bak
```

`/etc/exports`에 다음 설정을 추가하였다.

```exports
/srv/nfs/webdata 10.10.10.101(rw,sync,root_squash)
```

각 옵션의 의미는 다음과 같다.

| 옵션            | 의미                     |
| ------------- | ---------------------- |
| `rw`          | 클라이언트의 읽기·쓰기 허용        |
| `sync`        | 변경 사항을 디스크에 기록한 후 응답   |
| `root_squash` | 클라이언트 root를 익명 사용자로 변환 |

허용 클라이언트를 `10.10.10.101`로 지정하여 `web01`만 공유 디렉터리에 접근할 수 있도록 제한하였다.

설정을 적용하였다.

```bash
sudo exportfs -rav
```

적용 결과 확인:

```bash
sudo exportfs -v
```

확인 결과 `/srv/nfs/webdata`가 `web01`에 읽기·쓰기와 `root_squash` 옵션으로 공유되었다.

## 9. NFS 서비스 구성

NFS 서버와 관련 서비스를 실행하였다.

```bash
sudo systemctl enable --now rpc-statd nfs-server
```

서비스 상태 확인:

```bash
systemctl is-active nfs-server
systemctl is-enabled nfs-server
systemctl is-active rpc-statd
```

확인 결과:

```text
nfs-server : active / enabled
rpc-statd  : active / static
```

`rpc-statd`의 `static` 표시는 오류가 아니다. 다른 서비스의 의존성에 따라 실행되는 서비스이므로 별도의 활성화 정보가 없다는 의미이다.

## 10. NFS 버전 확인

서버에서 지원하는 NFS 버전을 확인하였다.

```bash
sudo cat /proc/fs/nfsd/versions
```

결과:

```text
+3 +4 +4.1 +4.2
```

NFSv3와 NFSv4 계열을 지원하며, `web01`에서는 NFSv4.2를 사용하도록 구성하였다.

## 11. 방화벽 설정

NFS 관련 서비스를 모든 시스템에 공개하지 않고 `web01`의 IP 주소에서만 접근할 수 있도록 Rich Rule을 추가하였다.

```bash
sudo firewall-cmd --permanent \
--add-rich-rule='rule family="ipv4" source address="10.10.10.101/32" service name="nfs" accept'
```

```bash
sudo firewall-cmd --permanent \
--add-rich-rule='rule family="ipv4" source address="10.10.10.101/32" service name="rpc-bind" accept'
```

```bash
sudo firewall-cmd --permanent \
--add-rich-rule='rule family="ipv4" source address="10.10.10.101/32" service name="mountd" accept'
```

방화벽 설정을 다시 불러왔다.

```bash
sudo firewall-cmd --reload
```

적용된 Rich Rule 확인:

```bash
sudo firewall-cmd --list-rich-rules
```

설정 결과 `10.10.10.101/32`에서 들어오는 NFS 관련 요청만 허용되었다.

## 12. SELinux 상태

SELinux는 비활성화하지 않고 `Enforcing` 상태로 유지하였다.

```bash
getenforce
```

결과:

```text
Enforcing
```

이번 구성에서는 SELinux를 해제하거나 Permissive 상태로 변경하지 않았다.

## 13. 공유 상태 검증

NFS 공유 목록을 확인하였다.

```bash
showmount -e localhost
```

결과:

```text
Export list for localhost:
/srv/nfs/webdata 10.10.10.101
```

RPC 서비스 등록 상태도 확인하였다.

```bash
rpcinfo -p localhost
```

확인 결과 NFS의 기본 포트인 TCP 2049와 RPC 관련 서비스가 정상적으로 등록되어 있었다.

리스닝 포트 확인:

```bash
sudo ss -lntup | grep -E ':111|:2049|:20048'
```

## 14. 클라이언트 파일 확인

`web01`의 `webshare` 계정으로 생성한 파일이 `storage01`에서 정상적으로 저장되었는지 확인하였다.

```bash
sudo ls -ln /srv/nfs/webdata/web01-test.txt
```

결과:

```text
-rw-r--r--. 1 2000 2000 26 Sep 30 11:31 /srv/nfs/webdata/web01-test.txt
```

파일 내용 확인:

```bash
sudo cat /srv/nfs/webdata/web01-test.txt
```

결과:

```text
NFS write test from web01
```

이를 통해 클라이언트에서 생성한 파일이 NFS 서버의 XFS 파일시스템에 정상적으로 저장되고 UID/GID `2000:2000`이 유지되는 것을 확인하였다.

## 15. 최종 검증

실패 상태인 systemd 서비스가 없는지 확인하였다.

```bash
systemctl --failed
```

결과:

```text
0 loaded units listed.
```

최종적으로 다음 항목을 검증하였다.

```text
NFS 공유 설정             정상
web01 접근 제한           정상
NFS 서비스 실행           정상
방화벽 Rich Rule          정상
SELinux Enforcing 유지    정상
UID/GID 2000:2000 유지    정상
클라이언트 파일 저장      정상
root_squash 적용          정상
systemd 실패 서비스       없음
```
