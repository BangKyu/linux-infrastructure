# web01 Apache 설정 장애 분석 및 복구

## 1. 작업 목적

운영 중인 Apache HTTP Server에 잘못된 설정이 추가된 상황을 가정하여 장애 탐지, 원인 분석 및 복구 절차를 실습하였다.

잘못된 설정으로 `reload`가 실패하더라도 기존 Apache 프로세스와 웹 서비스가 유지되는지 확인하고, 문제가 있는 설정 파일을 분리한 뒤 정상 상태로 복구하였다.

## 2. 장애 시나리오

이번 실습에서 가정한 장애 상황은 다음과 같다.

```text
운영자가 잘못된 Apache 설정 파일 추가
        ↓
설정 문법 오류 발생
        ↓
Apache reload 실패
        ↓
기존 Apache 프로세스는 이전 설정으로 서비스 유지
        ↓
configtest 및 journal 로그로 원인 분석
        ↓
잘못된 설정 파일 분리
        ↓
문법 검사 성공
        ↓
정상 reload 및 서비스 검증
```

서비스 중단 위험을 줄이기 위해 실습 중 `restart`와 `reboot`는 사용하지 않았다.

## 3. 작업 환경

| 항목 | 설정 |
|---|---|
| 서버 | `web01` |
| IP 주소 | `10.10.10.101` |
| 운영체제 | Rocky Linux 9.8 |
| 웹 서버 | Apache HTTP Server |
| 서비스 | `httpd` |
| 서비스 포트 | TCP 80 |
| 기본 페이지 | `/var/www/html/index.html` |
| NFS 웹 경로 | `/shared/` |
| NFS 파일 | `/shared/nfs-status.txt` |
| SELinux | `Enforcing` |

## 4. 장애 발생 전 상태 확인

설정 오류를 발생시키기 전에 Apache 설정 문법을 확인하였다.

```bash
sudo apachectl configtest
```

결과:

```text
Syntax OK
```

Apache 서비스 상태를 확인하였다.

```bash
systemctl is-active httpd
```

결과:

```text
active
```

기본 페이지와 NFS 파일의 HTTP 응답을 확인하였다.

```bash
curl -I http://127.0.0.1/
curl -I http://127.0.0.1/shared/nfs-status.txt
```

결과:

```text
HTTP/1.1 200 OK
Server: Apache
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN
Referrer-Policy: strict-origin-when-cross-origin
```

기본 페이지와 NFS 파일이 모두 `200 OK`를 반환하였다.

장애 전 Apache 메인 프로세스 번호도 기록하였다.

```bash
systemctl show httpd -p MainPID
```

결과:

```text
MainPID=977
```

## 5. 설정 파일 백업

장애 대응 실습 전에 현재 보안 설정 파일을 백업하였다.

```bash
sudo cp -a /etc/httpd/conf.d/security-hardening.conf \
/root/httpd-backup/security-hardening.conf.before-incident
```

백업 결과를 확인하였다.

```bash
sudo ls -l /root/httpd-backup
```

확인된 파일:

```text
httpd.conf.before-hardening
nfs-shared.conf.before-hardening
security-hardening.conf.before-incident
```

설정 변경 전에 기존 파일을 백업하여 필요한 경우 이전 상태로 복구할 수 있도록 준비하였다.

## 6. 의도적인 설정 오류 생성

장애 대응 실습을 위한 별도의 설정 파일을 생성하였다.

```bash
sudo vi /etc/httpd/conf.d/zz-lab-invalid.conf
```

작성한 내용:

```apache
# 장애 대응 실습용 잘못된 설정
InvalidDirectiveForLab On
```

`InvalidDirectiveForLab`은 Apache에서 지원하지 않는 설정 지시어이므로 문법 오류가 발생한다.

이 단계에서는 설정 파일만 생성했으며, 변경된 설정을 반영하는 `reload` 또는 `restart` 작업을 수행하지 않았기 때문에 기존 Apache 프로세스에는 영향을 주지 않는다.

## 7. configtest를 이용한 오류 탐지

잘못된 설정을 실제 서비스에 적용하기 전에 문법 검사를 수행하였다.

```bash
sudo apachectl configtest
```

결과:

```text
AH00526: Syntax error on line 2 of /etc/httpd/conf.d/zz-lab-invalid.conf:
Invalid command 'InvalidDirectiveForLab', perhaps misspelled or defined by a module not included in the server configuration
```

문법 검사 결과를 통해 다음 정보를 확인하였다.

```text
오류 파일 : /etc/httpd/conf.d/zz-lab-invalid.conf
오류 위치 : 2번 줄
오류 원인 : InvalidDirectiveForLab 지시어를 인식할 수 없음
```

설정 파일을 줄 번호와 함께 확인하였다.

```bash
sudo nl -ba /etc/httpd/conf.d/zz-lab-invalid.conf
```

결과:

```text
1  # 장애 대응 실습용 잘못된 설정
2  InvalidDirectiveForLab On
```

`configtest`가 출력한 파일과 줄 번호가 실제 오류 위치와 일치하는 것을 확인하였다.

## 8. 설정 오류 상태에서 기존 서비스 확인

설정 파일에는 오류가 있지만 아직 새 설정이 적용되지 않았으므로 기존 Apache 서비스 상태를 확인하였다.

```bash
systemctl is-active httpd
```

결과:

```text
active
```

기본 페이지와 NFS 파일을 다시 요청하였다.

```bash
curl -I http://127.0.0.1/
curl -I http://127.0.0.1/shared/nfs-status.txt
```

결과:

```text
HTTP/1.1 200 OK
HTTP/1.1 200 OK
```

설정 파일에 오류가 생겼더라도 실행 중인 Apache 프로세스는 이전에 적용된 설정을 사용하므로 웹 서비스가 즉시 중단되지 않는다.

## 9. 잘못된 설정으로 reload 시도

설정 오류가 있는 상태에서 Apache 설정의 `reload`를 시도하였다.

```bash
sudo systemctl reload httpd
```

결과:

```text
Job for httpd.service failed.
See "systemctl status httpd.service" and
"journalctl -xeu httpd.service" for details.
```

설정 문법 오류로 인해 `reload` 작업이 실패하였다.

## 10. reload 실패 후 서비스 연속성 확인

reload 실패 후 Apache 서비스 상태를 확인하였다.

```bash
systemctl is-active httpd
```

결과:

```text
active
```

Apache 메인 프로세스 번호를 확인하였다.

```bash
systemctl show httpd -p MainPID
```

결과:

```text
MainPID=977
```

장애 발생 전과 동일한 PID `977`이 유지되고 있었다.

기본 페이지의 HTTP 응답도 확인하였다.

```bash
curl -I http://127.0.0.1/
```

결과:

```text
HTTP/1.1 200 OK
```

이를 통해 새로운 설정을 적용하는 `reload` 작업은 실패했지만 기존 Apache 프로세스는 이전 설정으로 계속 요청을 처리하고 있음을 확인하였다.

```text
reload 작업      : 실패
Apache 서비스    : active
MainPID           : 977 유지
HTTP 응답         : 200 OK
```

## 11. systemctl 상태 분석

Apache의 상세 상태를 확인하였다.

```bash
systemctl status httpd --no-pager -l
```

결과에서 다음 내용을 확인하였다.

```text
Active: active (running)
ExecReload=/usr/sbin/httpd ... -k graceful
code=exited, status=1/FAILURE
Main PID: 977
```

로그에는 설정 오류와 reload 실패가 표시되었다.

```text
AH00526: Syntax error on line 2 of /etc/httpd/conf.d/zz-lab-invalid.conf
Invalid command 'InvalidDirectiveForLab'
Control process exited, code=exited, status=1/FAILURE
Reload failed for The Apache HTTP Server.
```

`ExecReload`는 실패했지만 `Active` 상태가 `active (running)`으로 유지되는 것을 확인하였다.

이는 Apache 서비스 자체의 장애가 아니라 새 설정을 적용하는 제어 작업의 실패이다.

## 12. journal 로그 분석

Apache 서비스의 최근 로그를 확인하였다.

```bash
sudo journalctl -u httpd -n 30 --no-pager
```

확인된 핵심 로그:

```text
Reloading The Apache HTTP Server...
AH00526: Syntax error on line 2 of /etc/httpd/conf.d/zz-lab-invalid.conf:
Invalid command 'InvalidDirectiveForLab'
httpd.service: Control process exited, code=exited, status=1/FAILURE
Reload failed for The Apache HTTP Server.
```

로그 분석을 통해 다음 순서로 원인을 파악하였다.

```text
reload 실패 확인
→ Apache 설정 문법 오류 확인
→ 오류 파일 확인
→ 오류 줄 번호 확인
→ 잘못된 지시어 확인
```

## 13. 잘못된 설정 파일 분리

Apache는 `/etc/httpd/conf.d/*.conf` 형식의 파일을 불러오므로, 문제가 있는 설정 파일을 삭제하지 않고 `.conf.disabled`로 확장자를 변경하여 Apache 설정 대상에서 제외하였다.

```bash
sudo mv /etc/httpd/conf.d/zz-lab-invalid.conf \
/etc/httpd/conf.d/zz-lab-invalid.conf.disabled
```

변경 결과를 확인하였다.

```bash
sudo ls -l /etc/httpd/conf.d/zz-lab-invalid*
```

결과:

```text
/etc/httpd/conf.d/zz-lab-invalid.conf.disabled
```

## 14. 설정 문법 복구 확인

문제 파일을 분리한 후 설정 문법을 다시 검사하였다.

```bash
sudo apachectl configtest
```

결과:

```text
Syntax OK
```

잘못된 설정 파일이 더 이상 Apache 설정에 포함되지 않아 문법 검사가 정상적으로 완료되었다.

## 15. 정상 설정 reload

문법 검사에서 `Syntax OK`를 확인한 후 Apache 설정을 다시 불러왔다.

```bash
sudo systemctl reload httpd
```

서비스 상태를 확인하였다.

```bash
systemctl is-active httpd
systemctl is-enabled httpd
systemctl show httpd -p MainPID
systemctl --failed
```

결과:

```text
active
enabled
MainPID=977
0 loaded units listed.
```

Apache 메인 프로세스가 유지된 상태로 정상적인 `reload`가 완료되었다.

## 16. 서비스 복구 검증

기본 페이지의 HTTP 응답을 확인하였다.

```bash
curl -I http://127.0.0.1/
```

결과:

```text
HTTP/1.1 200 OK
```

NFS 파일의 HTTP 응답도 확인하였다.

```bash
curl -I http://127.0.0.1/shared/nfs-status.txt
```

결과:

```text
HTTP/1.1 200 OK
```

NFS 파일 내용 확인:

```bash
curl http://127.0.0.1/shared/nfs-status.txt
```

결과:

```text
This file is served from storage01 NFS.
```

보안 헤더가 유지되는지도 확인하였다.

```bash
curl -sI http://127.0.0.1/ | \
grep -E 'HTTP/|Server:|X-Content|X-Frame|Referrer'
```

결과:

```text
HTTP/1.1 200 OK
Server: Apache
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN
Referrer-Policy: strict-origin-when-cross-origin
```

장애 복구 이후에도 기존 Apache 보안 설정과 NFS 연동이 정상적으로 유지되었다.

## 17. systemctl --failed 결과 해석

reload 실패 전후에 실패 상태인 systemd 서비스를 확인하였다.

```bash
systemctl --failed
```

결과:

```text
0 loaded units listed.
```

reload가 실패했음에도 `systemctl --failed`에서 Apache가 표시되지 않은 이유는 서비스 자체가 중단되지 않았기 때문이다.

```text
Apache 서비스 상태 : active
reload 제어 작업    : 실패
기존 프로세스       : 계속 실행
HTTP 서비스         : 정상
```

`systemctl --failed`는 현재 상태가 `failed`인 유닛을 표시한다. 이번 상황에서는 `ExecReload` 작업만 실패했고 Apache 서비스는 `active` 상태를 유지했으므로 실패한 서비스가 0개로 표시되었다.

## 18. 실습 파일 정리

장애 원인 분석을 위해 보관한 잘못된 설정 파일을 Apache 설정 디렉터리에서 백업 디렉터리로 이동하였다.

```bash
sudo mv /etc/httpd/conf.d/zz-lab-invalid.conf.disabled \
/root/httpd-backup/
```

이동 결과 확인:

```bash
sudo ls -l \
/root/httpd-backup/zz-lab-invalid.conf.disabled
```

결과:

```text
-rw-r--r--. 1 root root 69 Oct 6 10:01 /root/httpd-backup/zz-lab-invalid.conf.disabled
```

최종 설정 문법과 서비스 상태를 확인하였다.

```bash
sudo apachectl configtest
systemctl is-active httpd
systemctl --failed
```

결과:

```text
Syntax OK
active
0 loaded units listed.
```

## 19. 장애 전후 비교

| 항목 | 장애 발생 전 | 설정 오류 발생 후 | 복구 후 |
|---|---|---|---|
| 설정 문법 | `Syntax OK` | 오류 | `Syntax OK` |
| reload | - | 실패 | 성공 |
| Apache 상태 | `active` | `active` | `active` |
| MainPID | `977` | `977` | `977` |
| 기본 페이지 | `200 OK` | `200 OK` | `200 OK` |
| NFS 파일 | `200 OK` | `200 OK` | `200 OK` |
| 보안 헤더 | 정상 | 기존 설정 유지 | 정상 |
| 실패한 서비스 | 없음 | 없음 | 없음 |

## 20. 최종 검증

최종적으로 다음 항목을 검증하였다.

```text
장애 전 기준 정보 수집          완료
설정 파일 백업                 완료
의도적인 설정 오류 생성         완료
configtest 오류 탐지           성공
오류 파일과 줄 번호 확인         성공
reload 실패 확인               성공
기존 Apache 프로세스 유지       확인
MainPID 유지                   확인
장애 중 HTTP 200 응답           확인
journal 로그 원인 분석          완료
잘못된 설정 파일 분리           완료
설정 문법 복구                 Syntax OK
정상 reload                    성공
기본 페이지                    200 OK
NFS 파일                       200 OK
보안 헤더                      유지
Apache 서비스                  active / enabled
systemd 실패 서비스            없음
실습 파일 백업 디렉터리 이동     완료
```

## 21. 작업 결과

이번 실습에서는 Apache 설정 오류와 Apache 서비스 장애를 구분하여 분석하였다.

새로운 설정을 적용하는 `reload` 작업은 실패했지만 기존 Apache 프로세스는 이전 정상 설정을 사용하여 웹 서비스를 계속 제공하였다.

`configtest`, `systemctl status`, `journalctl`, 파일 줄 번호 확인을 통해 장애 원인을 찾아냈으며, 문제가 있는 파일을 설정 대상에서 제외한 후 문법 검사와 정상 `reload`를 거쳐 서비스를 복구하였다.

이를 통해 다음과 같은 Apache 설정 변경 및 장애 대응 절차를 수립하였다.

```text
백업
→ 설정 변경
→ 문법 검사
→ reload
→ 서비스 상태 확인
→ HTTP 응답 검증
→ 로그 확인
→ 문제 발생 시 설정 분리 및 복구
```
