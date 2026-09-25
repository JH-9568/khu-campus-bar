# CampusBar

macOS 메뉴 막대에서 경희대학교 e-Campus의 할 일을 확인하는 앱입니다.

## 빌드

macOS 14 이상과 Xcode가 필요합니다.

```sh
sh scripts/build.sh
open build/CampusBar.app
```

앱을 처음 실행하면 학교 로그인 화면이 열립니다. 로그인하면 Canvas의 예정 일정·최근 공지와 LearningX의 영상 학습 기한을 자동으로 읽어 메뉴 막대에 표시합니다. 로그인 정보는 앱 코드나 Git 저장소에 저장하지 않습니다.

Chrome 로그인과 별개이므로 앱 안에서 로그인해야 합니다. 로그인되지 않은 경우 학교 로그인 창을 자동으로 엽니다. 학교 로그인 쿠키는 macOS 키체인에 보관해 앱 재시작 후 복원합니다. 비밀번호를 수집하지 않으며, 학교 서버에서 세션을 만료하면 재로그인이 필요합니다. **로그인 정보 지우기**로 앱의 쿠키와 키체인 저장값을 삭제할 수 있습니다.

로그인 후 앱이 **내 강의실 바로가기**와 같은 경로로 자동 이동합니다. 자료를 받으면 앱 창이 요약 화면으로 전환되며 메뉴 막대 책 아이콘에서도 같은 목록을 볼 수 있습니다. 이전 학기 자료가 보이면 **학교 연결 / 학기 선택**에서 원하는 학기를 선택하세요. 앱을 다시 빌드한 경우 기존 앱을 종료하고 새 앱을 열어야 변경된 버전이 실행됩니다.

앱은 30분마다 새로고침합니다. LearningX 마이페이지도 학교에서 약 30분 간격으로 데이터를 갱신하므로, 실제 완료 직후에는 표시가 늦을 수 있습니다.

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" swift test --disable-sandbox
node --test scripts/canvas-script.test.cjs
```
