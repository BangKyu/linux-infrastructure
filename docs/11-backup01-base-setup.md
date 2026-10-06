# backup01 기본 운영 환경 구성

## 1. 작업 목적

`storage01`의 데이터를 별도 서버에 보관하고 백업 및 복원 실습을 진행하기 위해 `backup01`을 구축하였다.

`backup01`은 이후 별도의 데이터 디스크를 추가하여 LVM 및 XFS 기반 백업 저장소를 구성하고, `rsync`와 systemd timer를 이용한 자동 백업 대상으로 사용할 예정이다.

이번 단계에서는 Rocky Linux 설치, 고정 IP, 시간 동기화, 기본 서비스, SELinux와 방화벽을 구성하였다.

## 2. VM 사양

| 항목 | 설정 |
|---|---|
| VMware VM 이름 | `POC-backup01` |
| Hostname | `backup01` |
| OS | Rocky Linux 9.8 |
| 설치 유형 | Minimal Install |
| CPU | 2 vCPU |
| Memory | 2GB |
| OS Disk | 30GB |
| Network | VMware NAT |
| 관리 계정 | `sysadmin` |

백업용 데이터 디스크는 운영체제 설치와 기본 환경 구성이 끝난 후 별도로 추가하기 위해 초기 설치 단계에서는 OS 디스크만 연결하였다.

## 3. 서버 역할

`backup01`의 역할은 다음과 같다.

```text
storage01
/srv/nfs/webdata
        ↓
rsync over SSH
        ↓
backup01
백업 전용 데이터 디스크
```

향후 수행할 작업:

```text
백업용 데이터 디스크 구성
→ LVM 및 XFS 구성
→ 백업 전용 계정 생성
→ SSH 키 인증
→ rsync 수동 백업
→ systemd timer 자동화
→ 파일 삭제 및 복원 검증
```

## 4. Hostname 설정

서버 역할을 식별할 수 있도록 Hostname을 `backup01`로 설정하였다.

```bash
sudo hostnamectl set-hostname backup01
```

확인:

```bash
hostnamectl --static
```

결과:

```text
backup01
```

## 5. 운영체제 확인

설치된 운영체제 버전을 확인하였다.

```bash
cat /etc/rocky-release
```

결과:

```text
Rocky Linux release 9.8 (Blue Onyx)
```

## 6. 네트워크 설정

NetworkManager 연결 이름과 네트워크 인터페이스는 `ens160`이다.

고정 IPv4 주소를 다음과 같이 설정하였다.

```text
IP Address : 10.10.10.103/24
Gateway    : 10.10.10.2
DNS        : 8.8.8.8, 1.1.1.1
```

네트워크 인터페이스 상태를 확인하였다.

```bash
ip -br address
```

결과:

```text
lo       UNKNOWN  127.0.0.1/8 ::1/128
ens160   UP       10.10.10.103/24
```

라우팅 정보를 확인하였다.

```bash
ip route
```

결과:

[O```text
default via 10.10.10.2 dev ens160
10.10.10.0/24 dev ens160 src 10.10.10.103
```

기본 게이트웨이를 통해 외부 네트워크로 통신하도록 구성하였으며, 같은 내부망의 `web01`과 `storage01`에 접근할 수 있도록 설정하였다.

## 7. 시간 동기화

서버 시간대를 한국 표준시로 설정하였다.

```bash
sudo timedatectl set-timezone Asia/Seoul
```

시간 상태 확인:

```bash
timedatectl
```

결과:

```text
Time zone                 : Asia/Seoul (KST, +0900)
System clock synchronized : yes
NTP service               : active
RTC in local TZ           : no
```

Chrony를 활성화하여 시스템 시간을 동기화하고 RTC는 UTC를 사용하도록 유지하였다.

## 8. 기본 서비스 상태

다음 기본 서비스가 정상적으로 실행 중인지 확인하였다.

```bash
systemctl is-active NetworkManager
systemctl is-active chronyd
systemctl is-active sshd
systemctl is-active firewalld
```

결과:

```text
NetworkManager : active
chronyd        : active
sshd           : active
firewalld      : active
```

## 9. SELinux 상태

SELinux는 비활성화하지 않고 `Enforcing` 상태로 유지하였다.

```bash
getenforce
```

결과:

```text
Enforcing
```

향후 백업 서비스를 구성할 때도 SELinux를 유지하고 필요한 정책만 적용할 예정이다.

## 10. 방화벽 설정

초기 방화벽 상태를 확인하였다.

```bash
sudo firewall-cmd --list-all
```

초기 허용 서비스:

```text
services: cockpit dhcpv6-client ssh
```

이번 프로젝트에서는 Cockpit을 사용하지 않고 SSH로 서버를 관리하므로 Cockpit의 외부 접근 허용을 제거하였다.

```bash
sudo firewall-cmd --permanent \
--remove-service=cockpit
```

방화벽 설정을 다시 불러왔다.

```bash
sudo firewall-cmd --reload
```

최종 허용 서비스 확인:

```bash
sudo firewall-cmd --list-services
```

결과:

```text
dhcpv6-client ssh
```

Cockpit 패키지를 삭제하지 않고 방화벽의 접근 허용만 제거하였다.

현재 단계에서는 HTTP, NFS 또는 rsync 관련 포트를 추가로 허용하지 않았다. 이후 SSH 기반 rsync 백업을 구성할 예정이므로 SSH 서비스만 유지하였다.

## 11. 시스템 자원 확인

메모리 상태를 확인하였다.

```bash
free -h
```

결과:

```text
              total   used   free   shared   buff/cache   available
Mem:           1.6Gi  546Mi  499Mi     4Mi        802Mi       1.1Gi
Swap:          2.0Gi    2Mi  2.0Gi
```

파일시스템 상태를 확인하였다.

```bash
df -hT
```

주요 결과:

```text
Filesystem          Type  Size  Used  Avail Use% Mounted on
/dev/mapper/rl-root xfs    27G  2.0G    25G   8% /
/dev/nvme0n1p1      xfs   960M  453M   508M  48% /boot
```

## 12. 디스크 상태

현재 연결된 디스크는 30GB OS 디스크 한 개이다.

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

결과:

```text
nvme0n1       30G disk
├─nvme0n1p1    1G part xfs         /boot
└─nvme0n1p2   29G part LVM2_member
  ├─rl-root   27G lvm  xfs         /
  └─rl-swap    2G lvm  swap        [SWAP]
```

운영체제 디스크와 향후 추가할 백업 데이터 디스크를 명확하게 구분할 수 있다.

다음 단계에서 별도의 40GB 데이터 디스크를 추가하여 백업 저장소를 구성할 예정이다.

## 13. 최종 검증

최종적으로 다음 항목을 확인하였다.

```text
Hostname                   : backup01
운영체제                    : Rocky Linux 9.8
IP Address                 : 10.10.10.103/24
Gateway                    : 10.10.10.2
Time Zone                  : Asia/Seoul
System clock synchronized  : yes
NetworkManager             : active
NetworkManager-wait-online : active (exited)
chronyd                    : active
sshd                       : active
firewalld                  : active
SELinux                    : Enforcing
방화벽 허용 서비스          : dhcpv6-client, ssh
실패한 systemd 서비스       : 없음
OS Disk                    : 30GB
백업 데이터 디스크          : 아직 추가하지 않음
```

## 14. 작업 결과

`backup01`에 Rocky Linux 9.8을 설치하고 고정 IP, 시간 동기화, SSH, 방화벽과 SELinux를 포함한 기본 운영 환경을 구성하였다.

사용하지 않는 Cockpit의 방화벽 접근을 제거하고 SSH 관리에 필요한 서비스만 유지하였다.

