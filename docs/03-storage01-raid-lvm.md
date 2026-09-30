# storage01 RAID 6, LVM 및 XFS 구성

## 1. 작업 목적

`storage01`에 데이터 디스크를 추가하고 RAID 6, Hot Spare, LVM 및 XFS 기반의 스토리지 환경을 구성하였다.

웹 서비스에서 사용할 공유 데이터를 별도 Logical Volume에 저장하고, 이후 NFS를 통해 `web01`에 제공할 예정이다.

## 2. 스토리지 구성

```text
10GB NVMe Disk 4개
        ↓
RAID 6 /dev/md0
        ↓
LVM Physical Volume
        ↓
Volume Group vg_storage
        ↓
Logical Volume lv_webdata
        ↓
XFS
        ↓
/srv/nfs/webdata
```

## 3. 데이터 디스크 구성

| 장치 | 용량 | 역할 |
|---|---:|---|
| `/dev/nvme0n2p1` | 10GB | RAID 6 Active Disk |
| `/dev/nvme0n3p1` | 10GB | RAID 6 Active Disk |
| `/dev/nvme0n4p1` | 10GB | RAID 6 Active Disk |
| `/dev/nvme0n5p1` | 10GB | RAID 6 Active Disk |
| `/dev/nvme0n6p1` | 10GB | Hot Spare |


운영체제 디스크인 `/dev/nvme0n1`은 RAID 구성에서 제외하였다.

## 4. RAID 6 구성

Active Disk 네 개를 이용하여 `/dev/md0` RAID 6을 생성하였다.

```bash
sudo mdadm --create /dev/md0 \
  --level=6 \
  --raid-devices=4 \
  /dev/nvme0n2p1 \
  /dev/nvme0n3p1 \
  /dev/nvme0n4p1 \
  /dev/nvme0n5p1
```

RAID 생성 결과:

```text
Raid Level       : raid6
Array Size       : 19.98 GiB
Raid Devices     : 4
Active Devices   : 4
Failed Devices   : 0
State            : clean
Chunk Size       : 512K
Intent Bitmap    : Internal
```

RAID 6은 패리티를 위해 디스크 두 개 분량을 사용하므로 10GB 디스크 네 개에서 약 20GB를 사용할 수 있다.

## 5. Hot Spare 구성

`/dev/nvme0n6p1` 파티션을 Hot Spare로 추가하였다.

```bash
sudo mdadm /dev/md0 --add /dev/nvme0n6p1
```

최종 상태:

```text
Active Devices   : 4
Working Devices  : 5
Failed Devices   : 0
Spare Devices    : 1
```

`/proc/mdstat`에서도 Active Disk 네 개가 모두 정상인 것을 확인하였다.

```text
[4/4] [UUUU]
```

`nvme0n6p1`은 다음과 같이 Spare 상태로 표시되었다.

```text
nvme0n6p1[4](S)
```

Hot Spare는 RAID의 장애 허용 개수를 늘리는 디스크가 아니라, Active Disk 장애 시 자동으로 투입되어 복구를 시작하는 예비 디스크이다.

## 6. RAID 자동 조립 설정

현재 RAID 정보를 확인하였다.

```bash
sudo mdadm --detail --scan
```

`/etc/mdadm.conf`에 `/dev/md0`의 ARRAY 정보를 저장하였다.

```text
ARRAY /dev/md0 metadata=1.2 name=storage01:0 UUID=8db68105:e8199acd:be9092f7:a2d5a08c
```

부팅 환경에 설정을 반영하였다.

```bash
sudo dracut --force
```

서버를 재부팅한 후에도 `/dev/md0`이 자동으로 조립되고 Hot Spare가 유지되는 것을 확인하였다.

```text
State            : clean
Active Devices   : 4
Working Devices  : 5
Failed Devices   : 0
Spare Devices    : 1
```

## 7. LVM 구성

RAID 장치 전체를 LVM Physical Volume으로 등록하였다.

```bash
sudo pvcreate /dev/md0
```

`vg_storage` Volume Group을 생성하였다.

```bash
sudo vgcreate vg_storage /dev/md0
```

12GB 크기의 `lv_webdata` Logical Volume을 생성하였다.

```bash
sudo lvcreate -L 12G -n lv_webdata vg_storage
```

최종 LVM 상태:

```text
PV        : /dev/md0
VG        : vg_storage
VG Size   : 약 19.98GB
VG Free   : 약 7.98GB
LV        : lv_webdata
LV Size   : 12GB
```

남은 약 7.98GB는 이후 LVM 및 XFS 온라인 확장 실습에 사용할 예정이다.

## 8. XFS 파일시스템 구성

`lv_webdata`에 XFS 파일시스템을 생성하였다.

```bash
sudo mkfs.xfs /dev/vg_storage/lv_webdata
```

파일시스템 정보:

```text
UUID : 038c6a7e-2ebd-44b4-b927-f95fedc0eaaf
TYPE : xfs
```

XFS가 RAID의 Chunk Size를 감지하여 다음 값을 데이터 영역에 적용하였다.

```text
sunit  : 128 blocks
swidth : 256 blocks
```

4KiB 블록을 기준으로 `sunit`은 512KiB이며 RAID Chunk Size와 일치한다.

## 9. 영구 마운트 구성

마운트 디렉터리를 생성하였다.

```bash
sudo mkdir -p /srv/nfs/webdata
```

`/etc/fstab`에 다음 항목을 추가하였다.

```fstab
UUID=038c6a7e-2ebd-44b4-b927-f95fedc0eaaf /srv/nfs/webdata xfs defaults 0 0
```

설정 적용:

```bash
sudo systemctl daemon-reload
sudo mount -a
```

마운트 결과:

```text
Filesystem : /dev/mapper/vg_storage-lv_webdata
Type       : xfs
Size       : 12GB
Mount      : /srv/nfs/webdata
```

## 10. 재부팅 및 자동 마운트 검증

RAID, LVM 및 XFS 설정이 재부팅 후에도 자동으로 구성되는지 확인하기 위해 서버를 재부팅하였다.

재부팅 후 예상되는 스토리지 계층은 다음과 같다.

```text
/dev/md0
→ vg_storage
→ lv_webdata
→ XFS
→ /srv/nfs/webdata
```

RAID 자동 조립 상태를 확인하였다.

```bash
cat /proc/mdstat
sudo mdadm --detail /dev/md0
```

확인 결과 RAID가 `clean` 상태로 자동 조립되었고, Active Disk 네 개와 Hot Spare 한 개가 정상적으로 유지되었다.

```text
State            : clean
Active Devices   : 4
Working Devices  : 5
Failed Devices   : 0
Spare Devices    : 1
```

`/proc/mdstat`에서도 Active Disk 네 개가 모두 정상인 것을 확인하였다.

```text
[4/4] [UUUU]
```

LVM 활성화 상태를 확인하였다.

```bash
sudo pvs
sudo vgs
sudo lvs
```

확인 결과 `/dev/md0`이 `vg_storage`의 Physical Volume으로 활성화되었고, `lv_webdata`도 정상적으로 활성화되었다.

```text
PV      : /dev/md0
VG      : vg_storage
LV      : lv_webdata
LV Size : 12GB
VG Free : 약 7.98GB
```

XFS 파일시스템의 자동 마운트 상태를 확인하였다.

```bash
findmnt /srv/nfs/webdata
df -hT /srv/nfs/webdata
```

확인 결과:

```text
TARGET            SOURCE                              FSTYPE
/srv/nfs/webdata  /dev/mapper/vg_storage-lv_webdata  xfs
```

```text
Filesystem                             Type  Size  Used  Avail  Use%  Mounted on
/dev/mapper/vg_storage-lv_webdata      xfs    12G  119M    12G    1%  /srv/nfs/webdata
```

실패 상태인 systemd 서비스도 확인하였다.

```bash
systemctl --failed
```

결과:

```text
0 loaded units listed.
```

이를 통해 재부팅 후 다음 항목이 모두 자동으로 정상 구성되는 것을 확인하였다.

- `/dev/md0` RAID 6 자동 조립
- Hot Spare 유지
- `vg_storage` 자동 활성화
- `lv_webdata` 자동 활성화
- XFS 파일시스템 자동 마운트
- 실패한 systemd 서비스 없음

## 11. 읽기·쓰기 검증

자동 마운트된 XFS 파일시스템에서 실제 파일을 생성할 수 있는지 확인하였다.

테스트 파일 생성:

```bash
echo "persistent mount test" | sudo tee /srv/nfs/webdata/reboot-test.txt
```

명령 실행 후 다음 내용이 출력되었다.

```text
persistent mount test
```

`tee`의 화면 출력만으로는 저장된 파일을 다시 읽었다고 판단할 수 없으므로, `cat`을 이용해 실제 파일 내용을 확인하였다.

```bash
sudo cat /srv/nfs/webdata/reboot-test.txt
```

결과:

```text
persistent mount test
```

테스트 파일의 정보도 확인하였다.

```bash
sudo ls -l /srv/nfs/webdata/reboot-test.txt
```

파일 생성과 내용 확인이 끝난 후 테스트 파일을 삭제하였다.

```bash
sudo rm /srv/nfs/webdata/reboot-test.txt
```
