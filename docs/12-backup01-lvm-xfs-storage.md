
# backup01 LVM 및 XFS 백업 저장소 구성

## 1. 작업 목적

`backup01`에 40GiB 데이터 디스크를 추가하고 LVM과 XFS 기반의 백업 저장소를 구성하였다.

40GiB 파티션 전체를 LVM Volume Group으로 구성한 뒤, 그중 30GiB를 Logical Volume에 할당하였다. 남은 약 10GiB는 다른 실습에 사용할 예정이다.

생성한 XFS 파일시스템을 `/backup/storage01`에 영구 마운트하고, 읽기·쓰기 및 재부팅 후 자동 마운트를 검증하였다.

## 2. 스토리지 구성

```text
40GiB NVMe 디스크 /dev/nvme0n2
        ↓
GPT 파티션 /dev/nvme0n2p1
        ↓
LVM Physical Volume
        ↓
Volume Group vg_backup
        ↓
Logical Volume lv_backup 30GiB
        ↓
XFS 파일시스템
        ↓
/backup/storage01
```

## 3. 데이터 디스크 확인

VMware에서 `backup01`에 40GiB NVMe 디스크를 추가하였다.

```bash
lsblk -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS
```

주요 디스크 확인 결과:

```text
NAME      TYPE  SIZE
nvme0n1   disk   30G
nvme0n2   disk   40G
```

`/dev/nvme0n1`은 운영체제 디스크이며, `/dev/nvme0n2`는 새로 추가한 백업용 데이터 디스크이다.

새 디스크의 기존 서명을 확인하였다.

```bash
sudo wipefs -n /dev/nvme0n2
```

출력이 없어 기존 파일시스템, RAID 또는 LVM 서명이 없는 것을 확인하였다.

## 4. GPT 파티션 구성

`/dev/nvme0n2`에 GPT 파티션 테이블을 생성하고 디스크 공간 전체를 사용하는 파티션 하나를 구성하였다.

```bash
sudo fdisk /dev/nvme0n2
```

최종 파티션 상태:

```text
Disklabel type: gpt

Device         Start      End  Sectors Size Type
/dev/nvme0n2p1  2048 83886046 83883999  40G Linux LVM
```

운영체제 디스크인 `/dev/nvme0n1`은 작업 대상에서 제외하였다.

## 5. LVM Physical Volume 생성

`/dev/nvme0n2p1`을 LVM Physical Volume으로 등록하였다.

```bash
sudo pvcreate /dev/nvme0n2p1
```

결과:

```text
Physical volume "/dev/nvme0n2p1" successfully created.
```

## 6. Volume Group 생성

백업용 Volume Group인 `vg_backup`을 생성하였다.

```bash
sudo vgcreate vg_backup /dev/nvme0n2p1
```

결과:

```text
Volume group "vg_backup" successfully created
```

## 7. Logical Volume 생성

`vg_backup`에서 30GiB 크기의 `lv_backup`을 생성하였다.

```bash
sudo lvcreate -L 30G -n lv_backup vg_backup
```

결과:

```text
Logical volume "lv_backup" created.
```

Logical Volume은 다음 경로로 접근할 수 있다.

```text
/dev/vg_backup/lv_backup
/dev/mapper/vg_backup-lv_backup
```

구성 후 VG에 약 10GiB의 공간이 남았다.

## 8. XFS 파일시스템 생성

`lv_backup`에 XFS 파일시스템을 생성하였다.

```bash
sudo mkfs.xfs /dev/vg_backup/lv_backup
```

파일시스템 정보를 확인하였다.

```bash
lsblk -f /dev/vg_backup/lv_backup
```

결과:

```text
FSTYPE : xfs
UUID   : 9f119478-3b3a-49e1-be7c-b407d3ffec89
```

`backup01`은 단일 디스크의 파티션 위에 LVM과 XFS를 구성하였다. 반면 `storage01`은 RAID 6 장치 위에 LVM과 XFS를 구성하였다. `backup01`에는 RAID 스트라이프 구조가 없어 XFS 생성 결과 `sunit=0`, `swidth=0`으로 표시되었다.

## 9. 마운트 지점 생성

`storage01`의 백업 데이터를 저장할 디렉터리를 생성하였다.

```bash
sudo mkdir -p /backup/storage01
```

이 경로는 이후 `rsync` 백업의 저장 위치로 사용할 예정이다.

## 10. 영구 마운트 설정

파일시스템 UUID를 확인하였다.

```bash
sudo blkid /dev/vg_backup/lv_backup
```

결과:

```text
/dev/vg_backup/lv_backup: UUID="9f119478-3b3a-49e1-be7c-b407d3ffec89" TYPE="xfs"
```

재부팅 후에도 자동으로 마운트되도록 `/etc/fstab`에 다음 항목을 추가하였다.

```fstab
UUID=9f119478-3b3a-49e1-be7c-b407d3ffec89 /backup/storage01 xfs defaults 0 0
```

설정을 검사하였다.

```bash
sudo findmnt --verify
```

결과:

```text
Success, no errors or warnings detected
```

설정을 반영하고 마운트하였다.

```bash
sudo systemctl daemon-reload
sudo mount -a
```

## 11. 마운트 상태 확인

```bash
findmnt /backup/storage01
df -hT /backup/storage01
```

결과:

```text
TARGET             SOURCE                            FSTYPE
/backup/storage01  /dev/mapper/vg_backup-lv_backup  xfs
```

```text
Filesystem                       Type  Size  Used Avail Use% Mounted on
/dev/mapper/vg_backup-lv_backup  xfs    30G  247M   30G   1% /backup/storage01
```

`lv_backup`이 XFS 파일시스템으로 `/backup/storage01`에 마운트된 것을 확인하였다.

## 12. 읽기·쓰기 검증

마운트된 파일시스템에 테스트 파일을 생성하였다.

```bash
echo "backup storage persistent mount test" | \
sudo tee /backup/storage01/mount-test.txt
```

파일 내용을 읽었다.

```bash
sudo cat /backup/storage01/mount-test.txt
```

결과:

```text
backup storage persistent mount test
```

이를 통해 마운트된 파일시스템에서 파일을 쓰고 읽을 수 있음을 확인하였다.

## 13. 재부팅 검증

테스트 파일을 유지한 상태로 서버를 재부팅하였다.

```bash
sudo reboot
```

재접속 후 자동 마운트와 파일 유지를 확인하였다.

```bash
findmnt /backup/storage01
df -hT /backup/storage01
sudo cat /backup/storage01/mount-test.txt
systemctl --failed
```

확인 결과:

```text
마운트 지점       : /backup/storage01
파일시스템        : XFS
크기              : 30G
테스트 파일 내용  : backup storage persistent mount test
실패한 서비스     : 0 loaded units listed
```

## 14. 최종 스토리지 상태

```bash
sudo pvs
sudo vgs
sudo lvs
```

백업용 LVM 구성 결과:

```text
PV               VG         PSize    PFree
/dev/nvme0n2p1   vg_backup  <40.00g  <10.00g
```

```text
VG         #PV #LV  VSize    VFree
vg_backup    1   1  <40.00g  <10.00g
```

```text
LV         VG         Attr        LSize
lv_backup  vg_backup  -wi-ao----  30.00g
```

최종 스토리지 계층은 다음과 같다.

```text
/dev/nvme0n2
└─ /dev/nvme0n2p1
   └─ vg_backup
      └─ lv_backup
         └─ XFS
            └─ /backup/storage01
```

## 15. 작업 결과

`backup01`에 독립적인 백업 저장소를 구성하였다.

```text
40GiB 데이터 디스크 추가         완료
GPT 및 Linux LVM 파티션 구성     완료
PV 및 vg_backup 생성            완료
lv_backup 30GiB 생성            완료
VG 여유 공간 약 10GiB 확보      완료
XFS 파일시스템 생성             완료
/backup/storage01 영구 마운트    완료
읽기·쓰기 검증                  완료
재부팅 후 자동 마운트 검증       완료
systemd 실패 서비스 없음         확인
```
