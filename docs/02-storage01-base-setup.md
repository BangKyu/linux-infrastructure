# storage01 기본 운영 환경 구성

## 1. 작업 목적

웹 서비스에서 사용할 공유 데이터를 별도 서버에 저장하기 위해 `storage01`을 신규 구축하였다.

이 서버에는 이후 데이터 디스크 4개를 추가하여 RAID 6, LVM, XFS 및 NFS 환경을 구성할 예정이다.

## 2. VM 사양

| 항목 | 설정 |
|---|---|
| VMware VM 이름 | `storage01` |
| OS | Rocky Linux 9.8 |
| 설치 유형 | Minimal Install |
| CPU | 2 vCPU |
| Memory | 2GB |
| OS Disk | 30GB |
| Network | VMware NAT |
| 관리 계정 | `sysadmin` |

RAID용 데이터 디스크는 OS 설치가 끝난 후 별도로 추가하기 위해 초기 설치 단계에서는 OS 디스크만 연결하였다.

## 3. Hostname 설정

서버 역할을 식별할 수 있도록 hostname을 설정하였다.

```bash
sudo hostnamectl set-hostname storage01
```

확인:

```bash
hostnamectl --static
```

결과:

```text
storage01
```

## 4. 네트워크 설정

NetworkManager 연결 이름은 `ens160`이다.

다음과 같이 고정 IPv4 주소를 설정하였다.

```text
IP Address : 10.10.10.102/24
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

firewalld도 활성화된 상태로 유지하였다. 향후 NFS를 구축할 때 필요한 서비스만 추가로 허용할 예정이다.

## 8. 디스크 상태

현재 연결된 디스크는 30GB OS 디스크 한 개이다.

```text
nvme0n1       30G disk
├─nvme0n1p1    1G part xfs         /boot
└─nvme0n1p2   29G part LVM2_member
  ├─rl-root   27G lvm  xfs         /
  └─rl-swap    2G lvm  swap        [SWAP]
```

RAID용 데이터 디스크를 추가하기 전이므로 OS 디스크와 데이터 디스크를 명확하게 구분할 수 있다.

