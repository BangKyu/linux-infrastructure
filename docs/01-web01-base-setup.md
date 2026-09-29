# web01 기본 운영 환경 구성

## 1. 작업 목적

사내 웹 서비스를 제공하기 위해 `web01`을 신규 구축하였다.

이 서버에는 이후 Apache, PHP-FPM 및 MariaDB를 설치하고, `storage01`의 NFS 공유 디렉터리를 연결할 예정이다.

## 2. VM 사양

| 항목 | 설정 |
|---|---|
| VMware VM 이름 | `web01` |
| OS | Rocky Linux 9.8 |
| 설치 유형 | Minimal Install |
| CPU | 2 vCPU |
| Memory | 2GB |
| OS Disk | 30GB |
| Network | VMware NAT |
| 관리 계정 | `sysadmin` |

웹 서비스를 설치하기 전에 네트워크, 시간 동기화, SSH, SELinux 및 firewalld를 포함한 기본 운영 환경을 먼저 구성하였다.

## 3. Hostname 설정

서버 역할을 식별할 수 있도록 hostname을 설정하였다.

```bash
sudo hostnamectl set-hostname web01
```

확인:

```bash
hostnamectl --static
```

결과:

```text
web01
```

## 4. 네트워크 설정

NetworkManager 연결 이름은 `ens160`이다.

다음과 같이 고정 IPv4 주소를 설정하였다.

```text
IP Address : 10.10.10.101/24
Gateway    : 10.10.10.2
DNS        : 8.8.8.8, 1.1.1.1
```

설정 후 확인한 라우팅 정보:

```text
default via 10.10.10.2 dev ens160
10.10.10.0/24 dev ens160
```

게이트웨이, 외부 IP 및 DNS 조회를 통해 네트워크 연결을 검증하였다.

## 5. 시간 동기화

서버 시간대를 한국 표준시로 설정하였다.

```text
Time zone: Asia/Seoul
```

Chrony를 활성화하고 시스템 시간이 동기화된 것을 확인하였다.

```text
System clock synchronized: yes
NTP service: active
```

RTC는 UTC를 사용하도록 유지하였다.

```text
RTC in local TZ: no
```

## 6. 기본 서비스 상태

다음 서비스가 정상적으로 실행 중인 것을 확인하였다.

| 서비스 | 상태 |
|---|---|
| NetworkManager | active |
| chronyd | active |
| sshd | active |
| firewalld | active |

실패 상태인 systemd 서비스가 없는 것도 확인하였다.

```text
0 loaded units listed.
```

## 7. 보안 상태

SELinux는 비활성화하지 않고 Enforcing 상태로 유지하였다.

```text
Enforcing
```

firewalld도 활성화된 상태로 유지하였다. 현재는 서버 관리를 위한 SSH 접근을 사용하며, HTTP와 HTTPS는 웹 서비스를 구축할 때 필요한 항목만 추가로 허용할 예정이다.

## 8. 디스크 상태

현재 연결된 디스크는 30GB OS 디스크 한 개이다.

```text
nvme0n1       30G disk
├─nvme0n1p1    1G part xfs         /boot
└─nvme0n1p2   29G part LVM2_member
  ├─rl-root   27G lvm  xfs         /
  └─rl-swap    2G lvm  swap        [SWAP]
```

루트 파일시스템은 XFS이며 운영체제 설치 과정에서 LVM으로 구성되었다.
