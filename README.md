# Rocky Linux Infrastructure

Rocky Linux 기반으로 사내 웹 서비스 환경을 직접 구축하고, 스토리지·백업·보안·장애 복구 과정을 검증하는 개인 인프라 프로젝트입니다.

개별 명령어 실습이 아닌 여러 서버가 연결된 환경을 직접 설계하고 구축하는 것을 목표로 합니다. 모든 서버는 VMware Workstation에서 생성하며, 초기 구축은 자동화 도구 없이 수동으로 진행합니다.

## 1. 프로젝트 목표

- Rocky Linux 설치 및 기본 운영 환경 구성
- 서버 역할에 따른 시스템 분리
- Apache, PHP-FPM, MariaDB 기반 웹 서비스 구축
- RAID 6, LVM, XFS 기반 스토리지 구성
- NFS를 이용한 웹 서버와 스토리지 서버 연동
- rsync 및 DB dump 기반 백업 환경 구성
- SELinux와 firewalld를 이용한 접근 제어
- 서비스 상태 및 시스템 자원 점검
- 주요 장애 발생 및 원인 분석
- 백업 데이터 복원 및 장애 복구 검증
- 구축·운영·장애 처리 과정을 GitHub 문서로 기록

## 2. 전체 구성도

```text
                       HTTP/HTTPS
                ┌─────────────────────┐
                │                     ▼
          ┌──────────┐          ┌──────────┐
          │ client01 │          │  web01   │
          │ .104     │          │ .101     │
          └──────────┘          └────┬─────┘
             접속 및 테스트       Apache/PHP
                                  MariaDB
                                       │
                                       │ NFS
                                       ▼
                                ┌─────────────┐
                                │  storage01  │
                                │    .102     │
                                └──────┬──────┘
                                 RAID 6/LVM/XFS
                                       │
                                       │ SSH/rsync
                                       ▼
                                 ┌──────────┐
                                 │ backup01 │
                                 │   .103   │
                                 └──────────┘
                                  백업 및 복원
```

## 3. 서버 구성

| 서버 | IP | 역할 | 진행 상태 |
|---|---|---|---|
| `web01` | `10.10.10.101` | Apache, PHP-FPM, MariaDB | 기본 환경 구성 완료 |
| `storage01` | `10.10.10.102` | RAID 6, LVM, XFS, NFS | 설치 예정 |
| `backup01` | `10.10.10.103` | 웹·DB·파일 백업 | 설치 예정 |
| `client01` | `10.10.10.104` | 서비스 접속 및 장애 테스트 | 설치 예정 |

## 4. 네트워크 구성

```text
Network  : 10.10.10.0/24
Gateway  : 10.10.10.2
DNS      : 8.8.8.8, 1.1.1.1
VMware   : NAT Network
```

서버는 고정 IPv4 주소를 사용합니다. 서비스 구축 후에는 firewalld에서 서버 역할에 필요한 포트만 허용할 예정입니다.

## 5. 구축 환경

- VMware Workstation
- Rocky Linux 9.8
- systemd
- NetworkManager
- SELinux Enforcing
- firewalld
- Git 및 GitHub

## 6. 프로젝트 진행 상태

### 1단계: web01 기본 환경 구성

- [x] VMware 가상머신 생성
- [x] Rocky Linux 9.8 Minimal 설치
- [x] 일반 관리자 계정 생성
- [x] hostname을 `web01`로 설정
- [x] 고정 IP `10.10.10.101/24` 설정
- [x] Gateway 및 DNS 설정
- [x] 시간대를 `Asia/Seoul`로 설정
- [x] Chrony 시간 동기화 확인
- [x] SSH 원격 접속 확인
- [x] SELinux Enforcing 확인
- [x] firewalld 실행 확인
- [x] 실패한 systemd 서비스 점검
- [x] NetworkManager 부팅 장애 분석 및 해결

### 2단계: storage01 구축

- [ ] Rocky Linux 설치 및 기본 환경 구성
- [ ] 데이터용 가상 디스크 4개 추가
- [ ] RAID 6 구성
- [ ] RAID 장애 허용 범위 확인
- [ ] LVM 구성
- [ ] XFS 파일시스템 생성
- [ ] UUID 기반 영구 마운트
- [ ] NFS 서버 구성

### 3단계: 웹 서비스 구축

- [ ] Apache 설치 및 VirtualHost 구성
- [ ] PHP-FPM 연동
- [ ] MariaDB 설치
- [ ] 애플리케이션 전용 DB 계정 구성
- [ ] MariaDB 외부 접근 제한
- [ ] NFS 공유 디렉터리 연결
- [ ] SELinux 및 firewalld 정책 적용
- [ ] Client에서 전체 서비스 확인

### 4단계: 백업 및 복원

- [ ] backup01 설치
- [ ] 웹 설정 및 콘텐츠 백업
- [ ] MariaDB dump 생성
- [ ] NFS 데이터 백업
- [ ] rsync 기반 백업 구성
- [ ] 예약 백업 구성
- [ ] 파일 복원 테스트
- [ ] DB 복원 테스트

### 5단계: 장애 테스트

- [ ] RAID 디스크 장애 및 rebuild
- [ ] NFS 서비스 장애
- [ ] Apache 설정 오류
- [ ] Linux 파일 권한 오류
- [ ] SELinux 접근 차단
- [ ] 파일 삭제 및 복원
- [ ] DB 데이터 삭제 및 복원
- [ ] 디스크 사용량 증가 장애
- [ ] 장애별 원인 분석 및 복구 보고서 작성

## 7. web01 기본 사양

| 항목 | 설정 |
|---|---|
| OS | Rocky Linux 9.8 |
| 설치 유형 | Minimal Install |
| CPU | 2 vCPU |
| Memory | 2GB |
| OS Disk | 30GB |
| Hostname | `web01` |
| IP | `10.10.10.101/24` |
| Gateway | `10.10.10.2` |
| SELinux | Enforcing |
| Firewall | firewalld |
| 관리 계정 | `sysadmin` |

## 8. 트러블슈팅 기록

### NetworkManager-wait-online 부팅 실패

최초 부팅 후 다음 서비스가 실패 상태로 확인되었습니다.

```text
NetworkManager-wait-online.service
Result: exit-code
```

원인 분석 결과, 최초 부팅 당시 IPv4 네트워크 설정이 완료되지 않아 서비스가 네트워크 연결을 기다리다가 제한 시간 초과로 실패한 상태였습니다.

고정 IP와 자동 연결 설정을 완료하고 시스템을 재부팅한 후 다음과 같이 정상화되었습니다.

```text
Active: active (exited)
status=0/SUCCESS
```

최종적으로 실패한 systemd 서비스가 없음을 확인했습니다.

```text
0 loaded units listed.
```

세부 과정은 [web01 기본 운영 환경 구성](docs/01-web01-base-setup.md) 문서에 기록합니다.

## 9. 저장소 구조

```text
linux-infrastructure/
├── README.md
├── docs/
│   └── 01-web01-base-setup.md
├── configs/
├── scripts/
├── evidence/
├── .gitattributes
└── .gitignore
```

- `docs`: 구축 과정, 점검 결과 및 장애 보고서
- `configs`: 서비스별 설정 파일 예시
- `scripts`: 백업 및 점검 스크립트
- `evidence`: 주요 구축 및 장애 복구 증거
- `.gitignore`: 인증정보, VM 파일 및 임시 파일 제외
- `.gitattributes`: 문서와 스크립트의 줄바꿈 형식 관리

## 10. 보안 원칙

- 실제 비밀번호와 인증정보를 GitHub에 저장하지 않습니다.
- SSH 개인키를 저장소에 포함하지 않습니다.
- DB 비밀번호가 필요한 파일은 예제 파일로만 제공합니다.
- MariaDB는 웹 서버 외부에서 직접 접근할 수 없도록 구성합니다.
- SELinux를 비활성화하지 않고 필요한 정책을 적용합니다.
- firewalld에는 서비스 운영에 필요한 포트만 허용합니다.
- 장애 해결을 위해 무조건 `chmod 777`을 사용하지 않습니다.
- VMware 가상 디스크와 운영체제 ISO는 저장소에 포함하지 않습니다.

## 11. 문서

- [web01 기본 운영 환경 구성](docs/01-web01-base-setup.md)

프로젝트가 진행될 때마다 서버 구축 문서, 설정 파일, 점검 결과 및 장애 복구 보고서를 추가할 예정입니다.
