# storage01 LVM 및 XFS 온라인 확장

## 1. 작업 목적

`storage01`의 `lv_webdata` 용량을 12GB에서 16GB로 확장하고, 마운트 상태를 유지한 채 XFS 파일시스템의 크기를 확장하였다.

확장 전후의 파일 내용과 SHA-256 체크섬을 비교하고, NFS 클라이언트와 Apache를 통해 데이터 접근 상태를 검증하였다. 마지막으로 서버 재부팅 후에도 확장된 용량이 유지되는지 확인하였다.

## 2. 작업 환경

| 항목 | 설정 |
|---|---|
| 스토리지 서버 | `storage01` |
| 서버 IP | `10.10.10.102` |
| NFS 클라이언트 | `web01` |
| NFS 클라이언트 IP | `10.10.10.101` |
| RAID 장치 | `/dev/md0` |
| RAID Level | RAID 6 |
| Physical Volume | `/dev/md0` |
| Volume Group | `vg_storage` |
| Logical Volume | `lv_webdata` |
| LV 장치 경로 | `/dev/vg_storage/lv_webdata` |
| 파일시스템 | XFS |
| 마운트 지점 | `/srv/nfs/webdata` |
| web01 마운트 지점 | `/var/www/intranet/shared` |

## 3. 확장 구성

```text
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
        ↓ NFSv4.2
web01:/var/www/intranet/shared
        ↓
Apache /shared/
```

용량 확장 계획:

```text
확장 전 LV       : 12GB
추가 용량        : 4GB
확장 후 LV       : 16GB
확장 전 VG Free  : 약 7.98GB
확장 후 VG Free  : 약 3.98GB
```

VG의 남은 공간을 모두 사용하지 않고 약 3.98GB를 유지하여 이후 추가 확장이나 다른 LVM 실습에 사용할 수 있도록 하였다.

## 4. RAID 상태 확인

LVM 확장 전에 하위 스토리지인 RAID 상태를 확인하였다.

```bash
cat /proc/mdstat
```

결과:

```text
md0 : active raid6
      20951040 blocks super 1.2 level 6
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
Working Devices  : 5
Failed Devices   : 0
Spare Devices    : 1
```

RAID가 `clean` 상태이고 실패한 디스크가 없는 것을 확인한 후 LVM 확장을 진행하였다.

확장 작업 당시 디스크 역할:

```text
/dev/nvme0n2p1 : Hot Spare
/dev/nvme0n3p1 : Active Disk
/dev/nvme0n4p1 : Active Disk
/dev/nvme0n5p1 : Active Disk
/dev/nvme0n6p1 : Active Disk
```

## 5. 확장 전 LVM 상태 확인

Physical Volume 상태를 확인하였다.

```bash
sudo pvs
```

결과:

```text
PV             VG          PSize    PFree
/dev/md0       vg_storage  <19.98g  <7.98g
```

Volume Group 상태를 확인하였다.

```bash
sudo vgs
```

결과:

```text
VG          VSize    VFree
vg_storage  <19.98g  <7.98g
```

Logical Volume 상태를 확인하였다.

```bash
sudo lvs
```

결과:

```text
LV          VG          LSize
lv_webdata  vg_storage  12.00g
```

VG의 전체 크기는 약 19.98GB이며 약 7.98GB를 사용하지 않은 상태였다.

확장에 필요한 4GB보다 여유 공간이 충분한 것을 확인하였다.

## 6. 확장 전 XFS 상태 확인

파일시스템 마운트 상태를 확인하였다.

```bash
findmnt /srv/nfs/webdata
```

결과:

```text
TARGET            SOURCE                             FSTYPE
/srv/nfs/webdata  /dev/mapper/vg_storage-lv_webdata xfs
```

파일시스템 용량을 확인하였다.

```bash
df -hT /srv/nfs/webdata
```

결과:

```text
Filesystem                         Type  Size  Used  Avail Use% Mounted on
/dev/mapper/vg_storage-lv_webdata xfs    12G   119M   12G   1% /srv/nfs/webdata
```

XFS 상세 정보를 확인하였다.

```bash
sudo xfs_info /srv/nfs/webdata
```

확장 전 주요 정보:

```text
agcount : 16
bsize   : 4096
blocks  : 3143680
sunit   : 128 blocks
swidth  : 256 blocks
```

Logical Volume과 XFS 파일시스템이 모두 약 12GB인 것을 확인하였다.

## 7. LVM 메타데이터 백업

확장 작업 전에 `vg_storage`의 LVM 메타데이터를 백업하였다.

```bash
sudo vgcfgbackup vg_storage
```

결과:

```text
Volume group "vg_storage" successfully backed up.
```

백업 파일을 확인하였다.

```bash
sudo ls -l /etc/lvm/backup/vg_storage
```

결과:

```text
-rw-------. 1 root root 1411 Oct 6 12:40 /etc/lvm/backup/vg_storage
```

`vgcfgbackup`은 VG와 LV의 구성 정보만 백업하며, 파일시스템 안의 실제 데이터는 백업하지 않는다.

## 8. 데이터 무결성 기준 생성

확장 전후의 데이터 변화를 확인하기 위해 테스트 파일을 생성하였다.

```bash
echo "LVM XFS online extension test" | \
sudo -u webshare tee /srv/nfs/webdata/lvm-extension-test.txt
```

파일 내용을 확인하였다.

```bash
sudo -u webshare cat \
/srv/nfs/webdata/lvm-extension-test.txt
```

결과:

```text
LVM XFS online extension test
```

확장 전 SHA-256 체크섬을 계산하였다.

```bash
sudo -u webshare sha256sum \
/srv/nfs/webdata/lvm-extension-test.txt
```

결과:

```text
90c7467bfcbd9da55651854efcd7e28223bde7e7d65cb6e3309fa69f1a641091
```

해당 값을 확장 후 데이터 무결성 검증의 기준값으로 사용하였다.

## 9. Logical Volume 온라인 확장

확장 대상과 현재 용량을 다시 확인하였다.

```bash
sudo lvs \
-o lv_name,vg_name,lv_size \
/dev/vg_storage/lv_webdata
```

결과:

```text
LV          VG          LSize
lv_webdata  vg_storage  12.00g
```

`lv_webdata`에 4GB를 추가하였다.

```bash
sudo lvextend -L +4G \
/dev/vg_storage/lv_webdata
```

결과:

```text
Size of logical volume vg_storage/lv_webdata changed
from 12.00 GiB (3072 extents)
to 16.00 GiB (4096 extents).

Logical volume vg_storage/lv_webdata successfully resized.
```

확장된 LV 크기를 확인하였다.

```bash
sudo lvs \
-o lv_name,vg_name,lv_size \
/dev/vg_storage/lv_webdata
```

결과:

```text
LV          VG          LSize
lv_webdata  vg_storage  16.00g
```

## 10. LV와 파일시스템 용량 차이 확인

LV 확장 직후 XFS 파일시스템의 용량을 확인하였다.

```bash
df -hT /srv/nfs/webdata
```

결과:

```text
Filesystem                         Type  Size  Used  Avail Use% Mounted on
/dev/mapper/vg_storage-lv_webdata xfs    12G   119M   12G   1% /srv/nfs/webdata
```

확인된 상태:

```text
Logical Volume : 16GB
XFS 파일시스템 : 12GB
```

`lvextend`는 Logical Volume의 크기만 확장하므로 내부의 XFS 파일시스템은 기존 크기인 12GB로 유지되었다.

이를 통해 블록 장치 확장과 파일시스템 확장이 별도의 작업이라는 것을 확인하였다.

## 11. XFS 온라인 확장

XFS가 `/srv/nfs/webdata`에 마운트된 상태에서 온라인 확장을 실행하였다.

```bash
sudo xfs_growfs /srv/nfs/webdata
```

확장 결과:

```text
data blocks changed from 3143680 to 4194304
```

`xfs_growfs`에는 Logical Volume 장치 경로가 아니라 XFS 파일시스템의 마운트 지점을 지정하였다.

XFS는 마운트 상태에서 확장할 수 있으므로 파일시스템을 `umount`하거나 NFS 서비스를 중지하지 않고 작업을 수행하였다.

## 12. 확장 후 XFS 상태 확인

파일시스템 크기를 다시 확인하였다.

```bash
df -hT /srv/nfs/webdata
```

결과:

```text
Filesystem                         Type  Size  Used  Avail Use% Mounted on
/dev/mapper/vg_storage-lv_webdata xfs    16G   148M   16G   1% /srv/nfs/webdata
```

XFS 상세 정보:

```bash
sudo xfs_info /srv/nfs/webdata
```

확장 후 주요 정보:

```text
agcount : 22
bsize   : 4096
blocks  : 4194304
sunit   : 128 blocks
swidth  : 256 blocks
```

확장 전후 데이터 블록:

```text
확장 전 : 3143680 blocks
확장 후 : 4194304 blocks
```

XFS 파일시스템이 LV의 전체 크기인 약 16GB를 사용할 수 있게 되었다.

## 13. 확장 후 LVM 상태 확인

VG의 남은 공간을 확인하였다.

```bash
sudo vgs vg_storage \
-o vg_name,vg_size,vg_free
```

결과:

```text
VG          VSize    VFree
vg_storage  <19.98g  <3.98g
```

LV 크기를 확인하였다.

```bash
sudo lvs \
-o lv_name,vg_name,lv_size \
/dev/vg_storage/lv_webdata
```

결과:

```text
LV          VG          LSize
lv_webdata  vg_storage  16.00g
```

최종 LVM 상태:

```text
VG 전체 크기   : 약 19.98GB
lv_webdata     : 16GB
VG 남은 공간   : 약 3.98GB
```

## 14. 데이터 무결성 검증

확장 후 파일 내용을 확인하였다.

```bash
sudo -u webshare cat \
/srv/nfs/webdata/lvm-extension-test.txt
```

결과:

```text
LVM XFS online extension test
```

확장 후 체크섬을 계산하였다.

```bash
sudo -u webshare sha256sum \
/srv/nfs/webdata/lvm-extension-test.txt
```

결과:

```text
90c7467bfcbd9da55651854efcd7e28223bde7e7d65cb6e3309fa69f1a641091
```

확장 전후 SHA-256 값이 동일하여 기존 파일이 변경되지 않은 것을 확인하였다.

## 15. NFS 클라이언트 검증

`web01`에서 NFS 마운트 상태를 확인하였다.

```bash
findmnt /var/www/intranet/shared
```

결과:

```text
TARGET                    SOURCE                          FSTYPE
/var/www/intranet/shared  10.10.10.102:/srv/nfs/webdata nfs4
```

NFS 클라이언트에서 파일시스템 크기를 확인하였다.

```bash
df -hT /var/www/intranet/shared
```

결과:

```text
Filesystem                     Type  Size  Used  Avail Use% Mounted on
10.10.10.102:/srv/nfs/webdata nfs4   16G   147M   16G   1% /var/www/intranet/shared
```

`storage01`에서 확장한 XFS 용량이 `web01`에서도 약 16GB로 인식되는 것을 확인하였다.

## 16. Apache HTTP 검증

`web01`에서 NFS 테스트 파일의 HTTP 응답을 확인하였다.

```bash
curl -sI \
http://127.0.0.1/shared/lvm-extension-test.txt | head -n 1
```

결과:

```text
HTTP/1.1 200 OK
```

파일 내용 확인:

```bash
curl http://127.0.0.1/shared/lvm-extension-test.txt
```

결과:

```text
LVM XFS online extension test
```

NFS 클라이언트에서도 SHA-256 체크섬을 확인하였다.

```bash
sudo -u webshare sha256sum \
/var/www/intranet/shared/lvm-extension-test.txt
```

결과:

```text
90c7467bfcbd9da55651854efcd7e28223bde7e7d65cb6e3309fa69f1a641091
```

XFS 확장 후에도 Apache가 NFS에 저장된 파일을 정상적으로 제공하고 데이터 체크섬이 유지되는 것을 확인하였다.

## 17. 재부팅 전 상태 확인

재부팅 전에 RAID, LVM, XFS와 systemd 상태를 확인하였다.

```bash
cat /proc/mdstat
sudo lvs
df -hT /srv/nfs/webdata
systemctl --failed
```

결과:

```text
RAID 멤버       : [4/4] [UUUU]
lv_webdata      : 16.00g
XFS             : 16G
실패한 서비스   : 없음
```

정상 상태를 확인한 후 `storage01`을 재부팅하였다.

```bash
sudo reboot
```

## 18. 재부팅 후 검증

재접속 후 RAID 상태를 확인하였다.

```bash
cat /proc/mdstat
```

결과:

```text
md0 : active raid6
      [4/4] [UUUU]
```

LVM 상태를 확인하였다.

```bash
sudo pvs
sudo vgs
sudo lvs
```

결과:

```text
PV             : /dev/md0
VG             : vg_storage
VG Free        : 약 3.98GB
LV             : lv_webdata
LV Size        : 16.00GB
```

XFS 자동 마운트와 용량을 확인하였다.

```bash
findmnt /srv/nfs/webdata
df -hT /srv/nfs/webdata
```

결과:

```text
SOURCE                             FSTYPE MOUNTPOINT
/dev/mapper/vg_storage-lv_webdata xfs    /srv/nfs/webdata
```

```text
Filesystem                         Type  Size  Used  Avail Use% Mounted on
/dev/mapper/vg_storage-lv_webdata xfs    16G   148M   16G   1% /srv/nfs/webdata
```

NFS 서비스 상태를 확인하였다.

```bash
systemctl is-active nfs-server
```

결과:

```text
active
```

실패 상태인 systemd 서비스도 없었다.

```bash
systemctl --failed
```

결과:

```text
0 loaded units listed.
```

재부팅 이후에도 RAID 자동 조립, LVM 활성화, XFS 마운트와 NFS 서비스가 정상적으로 복구되었다.

## 19. 재부팅 후 web01 검증

`web01`에서 NFS 파일시스템 크기를 확인하였다.

```bash
df -hT /var/www/intranet/shared
```

결과:

```text
Filesystem                     Type  Size  Used  Avail Use% Mounted on
10.10.10.102:/srv/nfs/webdata nfs4   16G   147M   16G   1% /var/www/intranet/shared
```

Apache HTTP 응답을 확인하였다.

```bash
curl -sI \
http://127.0.0.1/shared/lvm-extension-test.txt | head -n 1
```

결과:

```text
HTTP/1.1 200 OK
```

파일 내용 확인:

```bash
curl http://127.0.0.1/shared/lvm-extension-test.txt
```

결과:

```text
LVM XFS online extension test
```

재부팅 후에도 `web01`에서 확장된 용량을 인식하고 Apache가 NFS 파일을 정상적으로 제공하였다.

## 20. 확장 전후 비교

| 항목 | 확장 전 | LV 확장 직후 | XFS 확장 후 |
|---|---:|---:|---:|
| `lv_webdata` | 12GB | 16GB | 16GB |
| XFS 파일시스템 | 12GB | 12GB | 16GB |
| VG 여유 공간 | 약 7.98GB | 약 3.98GB | 약 3.98GB |
| XFS 데이터 블록 | 3,143,680 | 3,143,680 | 4,194,304 |
| NFS 클라이언트 용량 | 12GB | 미측정 | 16GB |
| HTTP 응답 | 미측정 | 미측정 | `200 OK` |
| 데이터 체크섬 | 기준값 생성 | 미측정 | 기준값과 동일 |
| 파일시스템 마운트 | 마운트 상태 | 마운트 상태 | 마운트 상태 |

## 21. 최종 검증

최종적으로 다음 항목을 검증하였다.

```text
RAID 상태 확인                 [4/4] [UUUU]
VG 여유 공간 확인              약 7.98GB
LVM 메타데이터 백업            완료
데이터 무결성 기준 생성         완료
Logical Volume 확장            12GB → 16GB
LV 확장 직후 XFS 크기           12GB
XFS 온라인 확장                12GB → 16GB
VG 최종 여유 공간              약 3.98GB
파일시스템 마운트 상태          유지
데이터 체크섬                  확장 전후 동일
NFS 클라이언트 용량            16GB
Apache HTTP 응답              200 OK
재부팅 후 LV 크기              16GB
재부팅 후 XFS 크기             16GB
NFS 서비스                    active
systemd 실패 서비스            없음
```

## 22. 작업 결과

서비스 데이터를 저장하고 있는 `lv_webdata`의 용량을 12GB에서 16GB로 확장하였다.

`lvextend`로 Logical Volume을 확장한 후에 XFS는 기존 크기인 12GB를 유지하는 것을 확인하였다. 이후 마운트 상태에서 `xfs_growfs`를 실행하여 XFS를 16GB로 확장하였다.

확장 후 테스트 파일의 내용과 SHA-256 체크섬이 유지되었으며, `web01`의 NFS 마운트에서도 16GB를 인식하고 Apache가 테스트 파일을 `200 OK`로 제공하였다.

재부팅 후에도 RAID, LVM, XFS와 NFS 서비스가 정상적으로 복구되고 확장된 용량이 유지되는 것을 검증하였다.

최종 작업 절차는 다음과 같다.

```text
RAID 및 LVM 상태 확인
→ VG 여유 공간 확인
→ LVM 메타데이터 백업
→ 데이터 체크섬 생성
→ Logical Volume 확장
→ LV와 XFS 용량 차이 확인
→ XFS 온라인 확장
→ 데이터 및 서비스 검증
→ 재부팅 후 자동 복구 확인
```
