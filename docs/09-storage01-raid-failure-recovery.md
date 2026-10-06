# storage01 RAID 6 디스크 장애 및 Hot Spare 복구

## 1. 작업 목적

`storage01`의 RAID 6 환경에서 Active Disk 한 개에 장애가 발생한 상황을 만들어서 Hot Spare 자동 투입과 데이터 복구 과정을 실습하였다.

복구 후에는 장애 디스크를 배열에서 제거하고 이전 RAID 메타데이터를 초기화한 뒤 새로운 Hot Spare로 재등록하였다.

데이터 체크섬, NFS, HTTP 서비스 및 재부팅 후 RAID 자동 조립 상태를 검증하였다.

## 2. 스토리지 구성

```text
10GB NVMe Active Disk 4개
        +
10GB NVMe Hot Spare 1개
        ↓
RAID 6 /dev/md0
        ↓
LVM PV
        ↓
vg_storage
        ↓
lv_webdata
        ↓
XFS
        ↓
/srv/nfs/webdata
        ↓ NFSv4.2
web01 Apache
```

## 3. 작업 환경

| 항목 | 설정 |
|---|---|
| 스토리지 서버 | `storage01` |
| 서버 IP | `10.10.10.102` |
| NFS 클라이언트 | `web01` |
| 웹 서버 IP | `10.10.10.101` |
| RAID 장치 | `/dev/md0` |
| RAID Level | RAID 6 |
| RAID 용량 | 약 19.98GiB |
| Active Disk | 4개 |
| Hot Spare | 1개 |
| Chunk Size | 512KiB |
| LVM PV | `/dev/md0` |
| Volume Group | `vg_storage` |
| Logical Volume | `lv_webdata` |
| 파일시스템 | XFS |
| 마운트 지점 | `/srv/nfs/webdata` |


## 4. 장애 발생 전 RAID 상태

장애 실습을 시작하기 전에 RAID 상태를 확인하였다.

```bash
cat /proc/mdstat
```

결과:

```text
md0 : active raid6
      20951040 blocks super 1.2 level 6
      [4/4] [UUUU]
```

상세 상태도 확인하였다.

```bash
sudo mdadm --detail /dev/md0
```

확인 결과:

```text
State            : clean
Active Devices   : 4
Working Devices  : 5
Failed Devices   : 0
Spare Devices    : 1
```

장애 발생 전 디스크 역할은 다음과 같았다.

| 장치 | 역할 |
|---|---|
| `/dev/nvme0n2p1` | Active Disk |
| `/dev/nvme0n3p1` | Active Disk |
| `/dev/nvme0n4p1` | Active Disk |
| `/dev/nvme0n5p1` | Active Disk |
| `/dev/nvme0n6p1` | Hot Spare |


## 5. LVM 및 파일시스템 상태 확인

RAID 위에 구성된 LVM 상태를 확인하였다.

```bash
sudo pvs
sudo vgs
sudo lvs
```

확인 결과:

```text
PV : /dev/md0
VG : vg_storage
LV : lv_webdata
```

XFS 마운트 상태를 확인하였다.

```bash
df -hT /srv/nfs/webdata
```

결과:

```text
Filesystem                        Type  Size  Used Avail Use% Mounted on
/dev/mapper/vg_storage-lv_webdata xfs    12G  119M   12G   1% /srv/nfs/webdata
```

파일시스템 크기는 약 12GB이며 정상적으로 읽기·쓰기 상태로 마운트되어 있었다.

```bash
systemctl --failed
```

결과:

```text
0 loaded units listed.
```

실패 상태인 systemd 서비스도 없었다.

## 6. mdadm 설정 백업

RAID 장애 실습 전에 자동 조립 설정 파일을 백업하였다.

```bash
sudo cp -a /etc/mdadm.conf \
/root/mdadm.conf.before-raid-drill
```

백업 파일 확인:

```bash
sudo ls -l /root/mdadm.conf.before-raid-drill
```

결과:

```text
-rw-r--r--. 1 root root 78 Sep 29 17:24 /root/mdadm.conf.before-raid-drill
```

## 7. 데이터 무결성 기준 생성

RAID 장애 전후의 데이터 변화를 확인하기 위해 테스트 파일을 생성하였다.

```bash
echo "RAID recovery data integrity test" | \
sudo -u webshare tee /srv/nfs/webdata/raid-recovery-test.txt
```

파일 내용을 확인하였다.

```bash
sudo -u webshare cat \
/srv/nfs/webdata/raid-recovery-test.txt
```

결과:

```text
RAID recovery data integrity test
```

장애 전 SHA-256 체크섬을 계산하였다.

```bash
sudo -u webshare sha256sum \
/srv/nfs/webdata/raid-recovery-test.txt
```

결과:

```text
ad0360b21ccf1f4cb20b5d02412bf6765962ec926d5197b5282d390610dcaf1d
```

해당 값을 장애 복구 후 데이터 무결성 검증의 기준으로 사용하였다.

## 8. Active Disk 장애 처리

Active Disk인 `/dev/nvme0n2p1`을 Faulty 상태로 변경하였다.

장애 처리 명령:

```bash
sudo mdadm /dev/md0 --fail /dev/nvme0n2p1
```

이 명령은 가상 디스크 자체를 삭제하는 것이 아니라 mdadm에서 해당 RAID 멤버를 Faulty 상태로 변경한다.

## 9. RAID degraded 및 rebuild 확인

장애 처리 후 RAID 상태를 확인하였다.

```bash
sudo mdadm --detail /dev/md0
```

확인 결과:

```text
State            : clean, degraded, recovering
Active Devices   : 3
Working Devices  : 4
Failed Devices   : 1
Spare Devices    : 1
Rebuild Status   : 21% complete
```

디스크 역할:

```text
/dev/nvme0n2p1 : faulty
/dev/nvme0n6p1 : spare rebuilding
```

`/proc/mdstat`에서도 복구 진행 상태를 확인하였다.

```bash
cat /proc/mdstat
```

결과:

```text
[4/3] [_UUU]
recovery = 50.0%
```

각 표시의 의미는 다음과 같다.

| 표시 | 의미 |
|---|---|
| `[4/3]` | 필요한 디스크 4개 중 3개가 Active 상태 |
| `[_UUU]` | 첫 번째 RAID 슬롯의 디스크가 장애 상태 |
| `recovery` | Hot Spare에 데이터 재구성 중 |
| `(F)` | Faulty Disk |
| `spare rebuilding` | Hot Spare가 장애 디스크를 대체하는 중 |

복구 진행률은 다음 명령으로 관찰하였다.

```bash
watch -n 1 cat /proc/mdstat
```

RAID 6은 두 개의 패리티 정보를 사용하므로 한 개의 디스크가 장애 상태인 동안에도 데이터를 제공할 수 있다. Hot Spare는 장애 디스크를 대신하여 자동으로 rebuild를 시작하였다.

## 10. Hot Spare 자동 복구 완료

rebuild 완료 후 RAID 상태를 확인하였다.

```bash
cat /proc/mdstat
```

결과:

```text
[4/4] [UUUU]
```

상세 상태:

```bash
sudo mdadm --detail /dev/md0
```

결과:

```text
State            : clean
Active Devices   : 4
Working Devices  : 4
Failed Devices   : 1
Spare Devices    : 0
```

디스크 역할은 다음과 같이 변경되었다.

```text
/dev/nvme0n2p1 : faulty
/dev/nvme0n3p1 : active sync
/dev/nvme0n4p1 : active sync
/dev/nvme0n5p1 : active sync
/dev/nvme0n6p1 : active sync
```

기존 Hot Spare였던 `/dev/nvme0n6p1`이 장애가 발생한 첫 번째 RAID 슬롯에 투입되어 Active Disk로 승격되었다.

`[4/4] [UUUU]` 상태로 돌아왔지만 기존 장애 디스크가 배열에 Faulty 상태로 남아 있고 Hot Spare가 소모되었으므로 추가 복구 작업이 필요하였다.

## 11. 데이터 및 서비스 검증

`storage01`에서 복구 후 체크섬을 확인하였다.

```bash
sudo -u webshare sha256sum \
/srv/nfs/webdata/raid-recovery-test.txt
```

결과:

```text
ad0360b21ccf1f4cb20b5d02412bf6765962ec926d5197b5282d390610dcaf1d
```

장애 전후 체크섬이 동일하여 데이터가 변경되지 않은 것을 확인하였다.

`web01`에서 NFS 파일을 확인하였다.

```bash
sudo -u webshare cat \
/var/www/intranet/shared/raid-recovery-test.txt
```

결과:

```text
RAID recovery data integrity test
```

Apache를 통한 HTTP 응답도 확인하였다.

```bash
curl -sI \
http://127.0.0.1/shared/raid-recovery-test.txt | head -n 1
```

결과:

```text
HTTP/1.1 200 OK
```

파일 내용 확인:

```bash
curl http://127.0.0.1/shared/raid-recovery-test.txt
```

결과:

```text
RAID recovery data integrity test
```

`web01`에서도 체크섬을 확인하였다.

```bash
sudo -u webshare sha256sum \
/var/www/intranet/shared/raid-recovery-test.txt
```

결과:

```text
ad0360b21ccf1f4cb20b5d02412bf6765962ec926d5197b5282d390610dcaf1d
```

RAID 복구 후에도 NFS와 Apache를 통해 데이터에 접근할 수 있으며 체크섬이 유지되는 것을 확인하였다.

## 12. Faulty Disk 제거

rebuild가 완료되고 RAID 상태가 `[4/4] [UUUU]`로 복구된 후 Faulty Disk를 배열에서 제거하였다.

```bash
sudo mdadm /dev/md0 --remove /dev/nvme0n2p1
```

결과:

```text
mdadm: hot removed /dev/nvme0n2p1 from /dev/md0
```

제거 후 RAID 상태:

```text
State            : clean
Active Devices   : 4
Working Devices  : 4
Failed Devices   : 0
Spare Devices    : 0
```

`/dev/nvme0n2p1`은 더 이상 `/dev/md0`의 멤버로 표시되지 않았다.

## 13. 이전 RAID 메타데이터 초기화

배열에서 제거된 `/dev/nvme0n2p1`에는 기존 RAID 메타데이터가 남아 있으므로 초기화하였다.

```bash
sudo mdadm --zero-superblock /dev/nvme0n2p1
```

메타데이터 제거 여부를 확인하였다.

```bash
sudo mdadm --examine /dev/nvme0n2p1
```

결과:

```text
mdadm: No md superblock detected on /dev/nvme0n2p1.
```

파일시스템 정보를 확인하였다.

```bash
lsblk -f /dev/nvme0n2
```

결과:

```text
nvme0n2
└─nvme0n2p1
```

`FSTYPE`과 UUID가 표시되지 않아 기존 RAID 메타데이터가 제거된 것을 확인하였다.

## 14. 새로운 Hot Spare 등록

초기화한 `/dev/nvme0n2p1`을 `/dev/md0`의 새로운 Hot Spare로 추가하였다.

```bash
sudo mdadm /dev/md0 --add /dev/nvme0n2p1
```

결과:

```text
mdadm: added /dev/nvme0n2p1
```

`/proc/mdstat` 확인:

```bash
cat /proc/mdstat
```

결과:

```text
md0 : active raid6
      nvme0n2p1[5](S)
      [4/4] [UUUU]
```

`(S)`는 해당 장치가 Spare 상태임을 의미한다.

상세 상태:

```bash
sudo mdadm --detail /dev/md0
```

결과:

```text
State            : clean
Active Devices   : 4
Working Devices  : 5
Failed Devices   : 0
Spare Devices    : 1
```

최종 디스크 역할:

| 장치 | 최종 역할 |
|---|---|
| `/dev/nvme0n2p1` | Hot Spare |
| `/dev/nvme0n3p1` | Active Disk |
| `/dev/nvme0n4p1` | Active Disk |
| `/dev/nvme0n5p1` | Active Disk |
| `/dev/nvme0n6p1` | Active Disk |

장애 전과 Active Disk의 위치는 달라졌지만 `Active 4개 + Spare 1개` 구성이 다시 복구되었다.

## 15. RAID 자동 조립 설정 확인

현재 RAID 정보를 확인하였다.

```bash
sudo mdadm --detail --scan
```

결과:

```text
ARRAY /dev/md0 metadata=1.2 spares=1 UUID=8db68105:e8199acd:be9092f7:a2d5a08c
```

`/etc/mdadm.conf` 내용도 확인하였다.

```bash
sudo cat /etc/mdadm.conf
```

결과:

```text
ARRAY /dev/md0 metadata=1.2 spares=1 UUID=8db68105:e8199acd:be9092f7:a2d5a08c
```

배열 UUID와 Hot Spare 수가 현재 RAID 상태와 일치하였다.

배열 UUID가 변경되지 않았으므로 기존 자동 조립 설정을 그대로 사용할 수 있었다.

## 16. 재부팅 후 자동 복구 검증

RAID 자동 조립과 XFS 영구 마운트 확인을 위해 `storage01`을 재부팅하였다.

```bash
sudo reboot
```

재접속 후 RAID 상태를 확인하였다.

```bash
cat /proc/mdstat
sudo mdadm --detail /dev/md0
```

결과:

```text
State            : clean
Active Devices   : 4
Working Devices  : 5
Failed Devices   : 0
Spare Devices    : 1
[4/4] [UUUU]
```

재부팅 후에도 `/dev/nvme0n2p1`이 Hot Spare 상태로 유지되었다.

```text
/dev/nvme0n2p1 : spare
/dev/nvme0n3p1 : active sync
/dev/nvme0n4p1 : active sync
/dev/nvme0n5p1 : active sync
/dev/nvme0n6p1 : active sync
```

## 17. XFS 및 fstab 검증

XFS 파일시스템 마운트 상태를 확인하였다.

```bash
df -hT /srv/nfs/webdata
```

결과:

```text
Filesystem                        Type  Size  Used Avail Use% Mounted on
/dev/mapper/vg_storage-lv_webdata xfs    12G  119M   12G   1% /srv/nfs/webdata
```

`fstab` 설정 문법을 확인하였다.

```bash
sudo findmnt --verify
```

결과:

```text
Success, no errors or warnings detected
```

실제 마운트 설정을 확인하였다.

```bash
sudo grep -vE '^[[:space:]]*(#|$)' /etc/fstab
```

스토리지 마운트 항목:

```fstab
UUID=038c6a7e-2ebd-44b4-b927-f95fedc0eaaf /srv/nfs/webdata xfs defaults 0 0
```

재부팅 이후에도 RAID, LVM, XFS 계층이 정상적으로 구성되고 파일시스템이 자동으로 마운트되었다.

## 18. NFS 서비스 검증

재부팅 후 NFS 서버 상태를 확인하였다.

```bash
systemctl is-active nfs-server
```

결과:

```text
active
```

NFS 공유 설정 확인:

```bash
sudo exportfs -v
```

결과:

```text
/srv/nfs/webdata
    10.10.10.101(sync,wdelay,hide,no_subtree_check,sec=sys,rw,secure,root_squash,no_all_squash)
```

`web01`에서만 NFS 공유에 접근할 수 있으며 `root_squash`가 유지되고 있었다.

실패 상태인 systemd 서비스도 없었다.

```bash
systemctl --failed
```

결과:

```text
0 loaded units listed.
```

## 19. 테스트 파일 정리

데이터 무결성 검증이 끝난 후 테스트 파일을 삭제하였다.

```bash
sudo -u webshare rm \
/srv/nfs/webdata/raid-recovery-test.txt
```

삭제 결과 확인:

```bash
sudo ls /srv/nfs/webdata/
```

결과:

```text
nfs-status.txt
```

`raid-recovery-test.txt`가 표시되지 않아 정상적으로 삭제된 것을 확인하였다.


## 20. 장애 전후 비교

| 항목 | 장애 발생 전 | rebuild 중 | 최종 복구 후 |
|---|---|---|---|
| RAID State | `clean` | `clean, degraded, recovering` | `clean` |
| Active Devices | 4 | 3 | 4 |
| Working Devices | 5 | 4 | 5 |
| Failed Devices | 0 | 1 | 0 |
| Spare Devices | 1 | 1 (`rebuilding`) | 1 |
| RAID 멤버 | `[UUUU]` | `[_UUU]` | `[UUUU]` |
| Active 슬롯 0 | `nvme0n2p1` | 복구 중 | `nvme0n6p1` |
| Hot Spare | `nvme0n6p1` | rebuild에 투입 | `nvme0n2p1` |
| 데이터 체크섬 | 기준값 생성 | 미측정 | 기준값과 동일 |
| HTTP 응답 | 미측정 | 미측정 | `200 OK` |
| NFS 파일 접근 | 미측정 | 미측정 | 정상 |

## 21. 최종 검증

최종적으로 다음 항목을 검증하였다.

```text
장애 전 RAID 상태 확인           clean
RAID 설정 파일 백업             완료
데이터 무결성 기준 생성          완료
Active Disk 장애 처리           완료
RAID degraded 상태 확인         완료
Hot Spare 자동 투입             성공
온라인 rebuild                  성공
rebuild 진행률 확인              21%, 50%
RAID 멤버 복구                  [UUUU]
Faulty Disk 제거                성공
기존 RAID 메타데이터 초기화      성공
제거 디스크 Hot Spare 재등록     성공
Active Devices                  4
Working Devices                 5
Failed Devices                  0
Spare Devices                   1
데이터 체크섬                   장애 전후 동일
NFS 파일 접근                   정상
HTTP 응답                       200 OK
RAID 자동 조립                  정상
LVM 및 XFS 자동 구성            정상
NFS 서비스                      active
fstab 문법                      정상
systemd 실패 서비스             없음
```

## 22. 작업 결과

이번 실습에서는 RAID 6의 Active Disk 한 개를 Faulty 상태로 변경하여 실제 디스크 장애 상황을 발생시켰다.

Hot Spare가 자동으로 장애 디스크의 RAID 슬롯에 투입되고 온라인 rebuild가 수행되는 과정을 확인하였다. rebuild 완료 후에도 테스트 파일의 SHA-256 체크섬이 장애 전과 동일했으며 NFS와 Apache를 통해 파일에 정상적으로 접근할 수 있었다.

Faulty Disk를 배열에서 제거하고 이전 RAID 메타데이터를 초기화한 후 새로운 Hot Spare로 등록하여 `Active 4개 + Spare 1개` 구성을 다시 구성하였다.

재부팅 후에도 RAID 자동 조립, LVM 활성화, XFS 마운트와 NFS 서비스가 정상적으로 복구되는 것을 검증하였다.

최종 장애 대응 절차는 다음과 같다.

```text
장애 감지
→ RAID 상세 상태 확인
→ Hot Spare 자동 투입 및 rebuild 관찰
→ 데이터와 서비스 상태 확인
→ Faulty Disk 제거
→ 교체 디스크 RAID 메타데이터 초기화
→ 새로운 Hot Spare 등록
→ RAID 상태 및 데이터 무결성 검증
→ 재부팅 후 자동 복구 확인
```
