# web01 Apache 보안 강화

## 1. 작업 목적

`web01`에서 운영 중인 Apache HTTP Server의 불필요한 정보 노출을 줄이고 기본적인 웹 보안 설정을 적용하였다.

Apache와 운영체제의 상세 버전 정보 노출을 제한하고, HTTP TRACE 메서드와 디렉터리 목록 출력을 차단하였다. 또한 브라우저 보안을 위한 HTTP 응답 헤더를 추가하였다.

설정 변경 전 백업과 문법 검사를 수행하고, Apache 서비스를 중단하지 않고 `reload` 방식으로 설정을 적용하였다.

## 2. 작업 환경

| 항목 | 설정 |
|---|---|
| 서버 | `web01` |
| IP 주소 | `10.10.10.101` |
| 운영체제 | Rocky Linux 9.8 |
| 웹 서버 | Apache HTTP Server |
| Apache 버전 | 2.4.62 |
| 서비스 포트 | TCP 80 |
| SELinux | `Enforcing` |
| 기본 페이지 | `/var/www/html/index.html` |
| NFS 웹 경로 | `/shared/` |
| NFS 마운트 지점 | `/var/www/intranet/shared` |

## 3. 작업 전 상태 확인

보안 설정을 적용하기 전에 HTTP 응답 헤더를 확인하였다.

```bash
curl -I http://127.0.0.1/
```

결과:

```text
HTTP/1.1 200 OK
Server: Apache/2.4.62 (Rocky Linux)
ETag: "154-65cbcdafc919a"
Content-Type: text/html; charset=UTF-8
```

응답 헤더를 통해 Apache의 상세 버전과 운영체제 정보가 외부에 노출되고 있었다.

서비스 상태와 설정 문법도 확인하였다.

```bash
systemctl status httpd --no-pager
sudo apachectl configtest
```

결과:

```text
Apache 서비스 : active (running)
설정 문법      : Syntax OK
```

## 4. Apache 설정 백업

설정 변경 전 복구에 사용할 백업 디렉터리를 생성하였다.

```bash
sudo mkdir -p /root/httpd-backup
```

Apache 기본 설정 파일을 백업하였다.

```bash
sudo cp -a /etc/httpd/conf/httpd.conf \
/root/httpd-backup/httpd.conf.before-hardening
```

NFS Alias 설정도 백업하였다.

```bash
sudo cp -a /etc/httpd/conf.d/nfs-shared.conf \
/root/httpd-backup/nfs-shared.conf.before-hardening
```

백업 파일 확인:

```bash
sudo ls -l /root/httpd-backup
```

결과:

```text
httpd.conf.before-hardening
nfs-shared.conf.before-hardening
```

설정 파일을 변경하기 전에 원본을 백업하여 장애 발생 시 이전 상태로 복구할 수 있도록 준비하였다.

## 5. Apache 헤더 모듈 확인

보안 응답 헤더를 설정하기 위해 `headers_module`이 활성화되어 있는지 확인하였다.

Apache 실행 파일인 `httpd`를 이용하여 모듈을 확인하였다.

```bash
sudo httpd -M | grep headers_module
```

결과:

```text
headers_module (shared)
```

보안 응답 헤더를 설정하는 데 필요한 모듈이 정상적으로 로드된 것을 확인하였다.

## 6. Apache 보안 설정 작성

기본 설정 파일을 직접 수정하지 않고 별도의 보안 설정 파일을 생성하였다.

```bash
sudo vi /etc/httpd/conf.d/security-hardening.conf
```

작성한 설정:

```apache
# Apache 및 운영체제의 상세 버전 정보 노출 제한
ServerTokens Prod
ServerSignature Off

# TRACE 메서드 비활성화
TraceEnable Off

# 파일 정보를 이용한 ETag 생성 제한
FileETag None

# 기본 웹 경로의 디렉터리 목록 출력 차단
<Directory "/var/www/html">
    Options -Indexes +FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

# 기본 HTTP 보안 헤더
Header always set X-Content-Type-Options "nosniff"
Header always set X-Frame-Options "SAMEORIGIN"
Header always set Referrer-Policy "strict-origin-when-cross-origin"
```

## 7. 보안 설정 설명

### 7.1 ServerTokens Prod

```apache
ServerTokens Prod
```

HTTP 응답의 `Server` 헤더에서 Apache의 상세 버전과 운영체제 정보를 숨긴다.

변경 전:

```text
Server: Apache/2.4.62 (Rocky Linux)
```

변경 후:

```text
Server: Apache
```

제품 이름은 남지만 상세 버전과 운영체제 정보는 노출되지 않는다.

### 7.2 ServerSignature Off

```apache
ServerSignature Off
```

Apache에서 생성한 오류 페이지 하단에 서버 버전과 운영체제 정보가 표시되지 않도록 설정한다.

### 7.3 TraceEnable Off

```apache
TraceEnable Off
```

클라이언트가 보낸 HTTP 요청을 그대로 응답하는 TRACE 메서드를 비활성화한다.

### 7.4 FileETag None

```apache
FileETag None
```

파일의 inode와 수정 시간 등의 정보를 이용한 ETag 생성을 제한한다.

적용 전 응답에는 다음 값이 있었다.

```text
ETag: "154-65cbcdafc919a"
```

적용 후에는 ETag 헤더가 출력되지 않았다.

### 7.5 Options -Indexes

```apache
Options -Indexes +FollowSymLinks
```

요청한 디렉터리에 `index.html` 등의 기본 문서가 없을 때 서버의 파일 목록이 노출되지 않도록 설정한다.

### 7.6 X-Content-Type-Options

```apache
Header always set X-Content-Type-Options "nosniff"
```

브라우저가 서버에서 전달한 Content-Type과 다른 형식으로 콘텐츠를 추측하여 처리하지 않도록 제한한다.

### 7.7 X-Frame-Options

```apache
Header always set X-Frame-Options "SAMEORIGIN"
```

동일한 출처의 페이지에서만 현재 웹 페이지를 프레임으로 불러올 수 있도록 제한한다.

### 7.8 Referrer-Policy

```apache
Header always set Referrer-Policy "strict-origin-when-cross-origin"
```

다른 사이트로 요청할 때 브라우저가 전달하는 출처 정보의 범위를 제한한다.

이번 설정은 HTTP 응답 보안을 강화하는 것이며 통신을 암호화하지는 않는다. HTTPS는 이후 별도의 실습에서 구성할 예정이다.

## 8. 설정 문법 검사

작성한 설정을 Apache에 적용하기 전에 문법을 검사하였다.

```bash
sudo apachectl configtest
```

결과:

```text
Syntax OK
```

문법 검사에 성공한 경우에만 설정을 적용하였다.

설정 오류가 발생했을 경우 서비스를 재시작하거나 다시 불러오지 않고, 오류가 발생한 파일과 줄 번호를 먼저 확인하도록 작업 절차를 구성하였다.

## 9. 서비스 중단 없는 설정 적용

Apache 프로세스를 완전히 재시작하지 않고 `reload` 방식으로 설정을 적용하였다.

```bash
sudo systemctl reload httpd
```

서비스 상태를 확인하였다.

```bash
systemctl is-active httpd
systemctl is-enabled httpd
systemctl --failed
```

결과:

```text
active
enabled
0 loaded units listed.
```

Apache 로그에서는 다음 기록을 확인하였다.

```text
Reloading The Apache HTTP Server...
Reloaded The Apache HTTP Server.
SIGUSR1 received. Doing graceful restart
```

메인 Apache 프로세스는 유지되고 작업 프로세스가 새 설정으로 교체되었다. 이를 통해 서비스 중단을 줄이면서 설정이 적용된 것을 확인하였다.

## 10. 서버 정보 노출 제한 검증

보안 설정 적용 후 응답 헤더를 다시 확인하였다.

```bash
curl -I http://127.0.0.1/
```

결과:

```text
HTTP/1.1 200 OK
Server: Apache
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN
Referrer-Policy: strict-origin-when-cross-origin
Content-Type: text/html; charset=UTF-8
```

변경 전 표시되었던 Apache 상세 버전과 Rocky Linux 정보가 더 이상 HTTP 응답에 나타나지 않았다.

```text
변경 전 : Server: Apache/2.4.62 (Rocky Linux)
변경 후 : Server: Apache
```

## 11. 보안 헤더 검증

기본 페이지에 보안 헤더가 적용되었는지 확인하였다.

```bash
curl -I http://127.0.0.1/
```

NFS 파일에도 동일하게 적용되는지 확인하였다.

```bash
curl -I http://127.0.0.1/shared/nfs-status.txt
```

두 요청 모두 다음 헤더를 반환하였다.

```text
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN
Referrer-Policy: strict-origin-when-cross-origin
```

Apache가 로컬 파일과 NFS 파일에 동일한 보안 헤더를 적용하는 것을 확인하였다.

## 12. TRACE 메서드 차단 검증

HTTP TRACE 요청을 전송하였다.

```bash
curl -i -X TRACE http://127.0.0.1/
```

결과:

```text
HTTP/1.1 405 Method Not Allowed
Server: Apache
```

응답 내용:

```text
The requested method TRACE is not allowed for this URL.
```

`405 Method Not Allowed`가 반환되어 TRACE 메서드가 정상적으로 차단된 것을 확인하였다.

## 13. 디렉터리 목록 차단 검증

NFS 공유 디렉터리 주소를 파일명 없이 요청하였다.

```bash
curl -I http://127.0.0.1/shared/
```

결과:

```text
HTTP/1.1 403 Forbidden
```

Apache 오류 로그에는 다음 내용이 기록되었다.

```text
Cannot serve directory /var/www/intranet/shared/:
No matching DirectoryIndex found,
and server-generated directory index forbidden by Options directive
```

이는 Apache 장애가 아니라 `Options -Indexes` 설정으로 디렉터리 파일 목록이 차단된 정상적인 결과이다.

정확한 파일 경로는 계속 정상적으로 제공되는지 확인하였다.

```bash
curl -I http://127.0.0.1/shared/nfs-status.txt
```

결과:

```text
HTTP/1.1 200 OK
```

최종 동작은 다음과 같다.

```text
/shared/                 → 403 Forbidden
/shared/nfs-status.txt   → 200 OK
```

디렉터리 파일 목록은 노출되지 않지만 허용된 파일은 정상적으로 제공된다.

## 14. 로그 확인

Apache 서비스 로그를 확인하였다.

```bash
sudo journalctl -u httpd -n 30 --no-pager
```

설정 다시 불러오기가 정상적으로 처리된 것을 확인하였다.

```text
Reloading The Apache HTTP Server...
Reloaded The Apache HTTP Server.
Server configured, listening on: port 80
```

Apache 오류 로그도 확인하였다.

```bash
sudo tail -n 30 /var/log/httpd/error_log
```

로그에 기록된 다음 메시지는 `reload`에 따른 정상적인 graceful restart 기록이다.

```text
SIGUSR1 received. Doing graceful restart
```

다음 메시지는 디렉터리 목록 차단 테스트로 발생한 기록이다.

```text
server-generated directory index forbidden by Options directive
```

HTTP 응답에서는 상세 버전 정보가 숨겨지지만, 서버 관리자가 확인하는 내부 로그에는 Apache 버전이 기록될 수 있다.

## 15. 재부팅 검증

보안 설정과 Apache 자동 시작 설정이 재부팅 후에도 유지되는지 확인하기 위해 서버를 재부팅하였다.

```bash
sudo reboot
```

재접속 후 설정 문법과 서비스 상태를 확인하였다.

```bash
sudo apachectl configtest
systemctl is-active httpd
systemctl is-enabled httpd
systemctl --failed
```

결과:

```text
Syntax OK
active
enabled
0 loaded units listed.
```

기본 페이지와 NFS 파일의 HTTP 응답을 확인하였다.

```bash
curl -I http://127.0.0.1/
curl -I http://127.0.0.1/shared/nfs-status.txt
```

두 요청 모두 다음 결과를 반환하였다.

```text
HTTP/1.1 200 OK
Server: Apache
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN
Referrer-Policy: strict-origin-when-cross-origin
```

TRACE 요청도 다시 확인하였다.

```bash
curl -i -X TRACE http://127.0.0.1/
```

결과:

```text
HTTP/1.1 405 Method Not Allowed
```

재부팅 이후에도 모든 보안 설정이 유지되는 것을 확인하였다.

## 16. 적용 전후 비교

| 항목 | 적용 전 | 적용 후 |
|---|---|---|
| Server 헤더 | `Apache/2.4.62 (Rocky Linux)` | `Apache` |
| ETag | 출력 | 미출력 |
| `X-Content-Type-Options` | 없음 | `nosniff` |
| `X-Frame-Options` | 없음 | `SAMEORIGIN` |
| `Referrer-Policy` | 없음 | 적용 |
| TRACE 메서드 | 미검증 | `405 Method Not Allowed` |
| 디렉터리 목록 | 미검증 | `403 Forbidden` |
| 기본 웹 페이지 | `200 OK` | `200 OK` |
| NFS 파일 | `200 OK` | `200 OK` |
| SELinux | `Enforcing` | `Enforcing` |
| 서비스 적용 방식 | 해당 없음 | 무중단 `reload` |

## 17. 최종 검증

최종적으로 다음 항목을 확인하였다.

```text
설정 파일 백업                 완료
headers_module                활성화
Apache 설정 문법              Syntax OK
Apache 상세 버전 정보         숨김
운영체제 정보                 숨김
ETag                          제거
기본 보안 헤더                적용
TRACE 메서드                  차단
디렉터리 파일 목록            차단
기본 페이지                   200 OK
NFS 파일                      200 OK
서비스 중단 없는 reload       정상
Apache 자동 시작              enabled
재부팅 후 보안 설정           유지
SELinux                       Enforcing
systemd 실패 서비스           없음
```

## 18. 작업 결과

이번 작업에서는 Apache 보안 설정을 별도 파일로 관리하고, 변경 전 백업과 문법 검사를 거친 뒤 서비스 중단을 줄이는 `reload` 방식으로 적용하였다.

단순히 설정을 추가하는 것에 그치지 않고 HTTP 응답, 차단 상태, Apache 로그와 재부팅 이후 상태를 확인하여 보안 설정이 실제로 적용된 것을 검증하였다.

