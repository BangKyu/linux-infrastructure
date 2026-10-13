# Rocky Linux Infrastructure PoC

Rocky Linux 가상머신 3대를 이용해 웹 서비스, 공유 스토리지, 백업 서버를 수동으로 구축하고 장애 대응과 데이터 복원을 검증한 개인 인프라 프로젝트입니다.

단일 서버에서 명령어만 실행하는 실습이 아니라, **스토리지에 저장된 파일이 NFS를 거쳐 웹 서비스로 제공되고, 백업 서버의 이전 시점 파일을 다시 복원하는 전체 흐름**을 확인하는 것을 목표로 하였습니다.


## 1. 프로젝트 구성

```text
                   사용자
                     │
                HTTP (TCP 80)
                     ▼
          ┌──────────────────────────┐
          │ web01                    │
          │ 10.10.10.101             │
          │ Apache + NFS client      │
          └────────────┬─────────────┘
                       │ NFS 마운트
                       ▼
          ┌──────────────────────────┐
          │ storage01                │
          │ 10.10.10.102             │
          │ RAID 6 → LVM → XFS → NFS │
          └────────────▲─────────────┘
                       │
             SSH/rsync로 원본 읽기
                       │
          ┌────────────┴─────────────┐
          │ backup01                 │
          │ 10.10.10.103             │
          │ rsync + systemd timer    │
          └──────────────────────────┘
```

`backup01`은 SSH를 이용해 `storage01`의 NFS 데이터 원본을 읽고, 백업 데이터를 자신의 로컬 디스크에 저장합니다. `web01`은 `storage01`의 NFS 공유를 마운트하여 Apache로 파일을 제공합니다.

## 2. 서버별 역할

| 서버 | IP 주소 | 주요 역할 |
|---|---|---|
| `web01` | `10.10.10.101` | Apache 웹 서비스, NFS 클라이언트, 웹 보안 설정 |
| `storage01` | `10.10.10.102` | RAID 6, Hot Spare, LVM, XFS, NFS 서버 |
| `backup01` | `10.10.10.103` | 파일 백업 저장소, rsync 날짜별 백업, systemd 예약 실행 및 상태 점검 |

모든 서버는 VMware Workstation의 NAT 네트워크에서 Rocky Linux 9.8을 사용합니다. 서버의 기본 운영 환경은 NetworkManager, chronyd, sshd, firewalld 및 SELinux 상태를 확인하며 구성하였습니다.

## 3. 주요 구축 내용

### 스토리지와 NFS

- `storage01`에 10GiB 데이터 디스크 4개로 RAID 6을 구성하고, 디스크 1개를 Hot Spare로 추가
- RAID 장치 `/dev/md0` 위에 `vg_storage/lv_webdata` LVM과 XFS 파일시스템 구성
- `/srv/nfs/webdata`를 영구 마운트하고 NFS로 제공
- `web01`에서 NFS 공유를 `/var/www/intranet/shared`에 마운트
- `lv_webdata`와 XFS를 서비스 중 12GiB에서 16GiB로 확장

### 웹 서비스와 보안

- `web01`에 Apache HTTP Server 구성
- NFS 공유 파일을 `/shared/` HTTP 경로로 제공
- SELinux를 Enforcing으로 유지하고 Apache의 NFS 접근 설정 적용
- firewalld를 통해 필요한 접근만 허용
- Apache 상세 버전 정보 노출 제한, TRACE 메서드 차단, 디렉터리 목록 차단 및 기본 보안 응답 헤더 적용

### 백업과 복원

- `backup01`에 별도 30GiB XFS 백업 파일시스템 구성
- 읽기 전용 `backupreader` 계정과 ACL을 이용해 백업 원본 접근 범위 제한
- SSH와 rsync를 이용해 `storage01`의 파일을 `backup01`로 가져오기
- 날짜별 백업본과 `--link-dest` 하드 링크 재사용 검증
- 백업 스크립트를 systemd 서비스와 매일 03:00 타이머에 연결
- 매일 04:00 실행하도록 백업 상태 점검 타이머 구성
- 이전 시점 백업본의 파일을 별도 이름으로 복원하고 NFS·Apache 경로까지 검증

## 4. 장애 및 운영 검증

| 실습 | 확인한 내용 |
|---|---|
| Apache 설정 오류 | 잘못된 설정으로 `reload`가 실패해도 기존 서비스가 유지되는지 확인하고 설정 복구 |
| RAID 디스크 장애 | Active Disk 장애 시 Hot Spare 투입과 rebuild 확인 |
| LVM·XFS 온라인 확장 | 파일시스템을 마운트한 상태에서 용량 확장 및 웹 서비스 접근 확인 |
| 백업 스크립트 실패 처리 | 백업 저장소 경로와 원격 원본 경로 오류를 모의해 실패한 작업이 완성 백업본으로 표시되지 않는지 확인 |
| 백업 타이머 | 시험용 예약 시각에 백업 서비스가 실제 실행되는지 확인 |
| 백업 상태 점검 | 최신 백업본의 경과 시간 검사 및 시험용 타이머 자동 실행 확인 |
| 이전 버전 복원 | `version 1`을 별도 파일로 복원하고 기존 `version 2`가 유지되는지 확인 |

매일 **03:00 백업**과 **04:00 상태 점검**은 해당 시각으로 설정하고 시험용 예약 시각의 자동 실행을 검증했습니다. 정규 03:00·04:00 실행 기록과 VM이 꺼져 있던 동안 놓친 작업의 보충 실행은 별도로 확인해야 합니다.

백업 보존 실습에서는 정리 후보와 저장소 사용량을 **조회만** 했습니다. 백업본 자동 삭제 정책은 구현하지 않았습니다.

## 5. 최종 통합 복원 결과

`backup01`의 이전 시점 백업본에 있던 `version 1` 파일을 `storage01`의 `/srv/nfs/webdata/version-restored-v1.txt`로 복원했습니다. 기존 `version-test.txt`는 `version 2 - changed`로 유지했습니다.

`web01`에서는 NFS를 통해 복원 파일을 읽었고, Apache의 `/shared/version-restored-v1.txt` 경로에서 `HTTP/1.1 200 OK`와 `version 1`을 확인했습니다. 백업본과 복원 파일의 SHA-256 값도 일치했습니다.

자세한 절차와 출력은 [이전 시점 백업본 통합 복원 검증](docs/19-integrated-restore.md)에 기록했습니다.

## 6. 실습 문서

### 기본 환경 및 스토리지

1. [web01 기본 운영 환경 구성](docs/01-web01-base-setup.md)
2. [storage01 기본 운영 환경 구성](docs/02-storage01-base-setup.md)
3. [storage01 RAID 6, LVM 및 XFS 구성](docs/03-storage01-raid-lvm.md)
4. [storage01 NFS 서버 구성](docs/04-storage01-nfs-server.md)
5. [web01 NFS 클라이언트 구성](docs/05-web01-nfs-client.md)

### 웹 서비스 및 장애 대응

6. [web01 Apache 및 NFS 연동 구성](docs/06-web01-apache-nfs.md)
7. [web01 Apache 보안 강화](docs/07-web01-apache-security-hardening.md)
8. [web01 Apache 설정 장애 분석 및 복구](docs/08-web01-apache-config-incident-recovery.md)
9. [storage01 RAID 6 디스크 장애 및 Hot Spare 복구](docs/09-storage01-raid-failure-recovery.md)
10. [storage01 LVM 및 XFS 온라인 확장](docs/10-storage01-lvm-xfs-extension.md)

### 백업 서버 및 복원

11. [backup01 기본 운영 환경 구성](docs/11-backup01-base-setup.md)
12. [backup01 LVM 및 XFS 백업 저장소 구성](docs/12-backup01-lvm-xfs-storage.md)
13. [storage01 데이터 백업 및 복원 검증](docs/13-storage01-backup-restore.md)
14. [backup01 rsync 기반 버전별 파일 백업](docs/14-backup01-versioned-backup.md)
15. [backup01 백업 스크립트 정상 동작 및 실패 처리 검증](docs/15-backup01-script-failure-test.md)
16. [backup01 systemd 서비스 및 백업 타이머 구성](docs/16-backup01-systemd-timer.md)
17. [backup01 백업 보존 대상 및 저장소 용량 점검](docs/17-backup01-retention-capacity.md)
18. [backup01 백업 상태 점검 및 자동 실행](docs/18-backup01-health-check.md)
19. [이전 시점 백업본 통합 복원 검증](docs/19-integrated-restore.md)

## 7. 저장소 구조

```text
linux-infrastructure/
├── README.md
├── docs/                 # 01~19번 실습 기록
├── images/               # 웹 서비스 화면 증거
├── .gitattributes
└── .gitignore
```

## 8. 프로젝트 범위와 한계

- 이 프로젝트는 **수동 구축 중심의 프로젝트 PoC**입니다. Ansible 등의 구성 자동화는 포함하지 않았습니다.
- RAID 6은 디스크 장애 대응 수단이며 백업을 대체하지 않습니다.
- 백업 데이터는 별도 VM에 저장하지만 동일한 실습 환경에 있으므로 원격지·오프사이트 백업을 검증한 것은 아닙니다.
- Apache는 HTTP로 제공하며 HTTPS 암호화는 구성하지 않았습니다.
- PHP-FPM, MariaDB, DB dump 및 애플리케이션 데이터베이스 복원은 현재 실습 범위에 포함되지 않습니다.
- 비밀번호와 SSH 개인키는 저장소에 게시하지 않습니다.
