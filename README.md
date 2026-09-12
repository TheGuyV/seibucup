# seibucup.online — 홈페이지 (GitHub Pages)

정적 사이트입니다. 빌드 도구 없음. 파일: `index.html` `download.html` `guide.html` `donate.html` `license.html` `style.css` `site.js` `CNAME`.
한/영 전환은 각 문장을 `<span class="ko">`/`<span class="en">`으로 나란히 두고 `site.js`가 `html[lang]`으로 하나만 보여 주는 방식입니다.

## 올리기 전에 바꿀 자리 (검색해서 치환)
- `CONTACT_EMAIL` — 권리자 문의용 메일 (license.html)
- `MAME 0.2XX` — 세이부 컵 사커가 정식 지원되는 실제 MAME 버전 (download.html)

## GitHub Pages 배포
1. GitHub에 저장소를 만들고(예: `seibucup`) 이 `site/` 폴더가 그대로 저장소 루트입니다 (git 저장소로 초기화됨).
2. 저장소 Settings → Pages → Source: `Deploy from a branch`, Branch `main` / 폴더 `/ (root)` (또는 `/docs`).
3. Settings → Pages → Custom domain에 `seibucup.online` 입력 → 저장. (`CNAME` 파일이 같은 값이어야 합니다.)
4. 도메인 등록업체 DNS에 다음 레코드를 추가합니다.
   | 종류 | 이름 | 값 |
   |---|---|---|
   | A | `@` | `185.199.108.153` |
   | A | `@` | `185.199.109.153` |
   | A | `@` | `185.199.110.153` |
   | A | `@` | `185.199.111.153` |
   | CNAME | `www` | `theguyv.github.io` |
   | CNAME | `relay` | `guyv.duckdns.org` ← 게임 서버(집 PC). 런처 상수를 `relay.seibucup.online`으로 바꾸면 서버를 옮겨도 런처 재배포 불필요 |
5. 전파(수 분~수 시간) 뒤 Pages 설정에서 **Enforce HTTPS** 체크.

## 다운로드 파일
런처 zip은 저장소의 **Releases**에 올리고(`/releases/latest` 링크가 자동으로 최신을 가리킴), 롬은 절대 올리지 않습니다.

## 로컬 미리보기
폴더에서 `python -m http.server 8080` 후 http://localhost:8080
