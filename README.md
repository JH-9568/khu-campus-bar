# CampusBar

macOS 메뉴 막대에서 경희대학교 e-Campus의 할 일을 확인하는 앱입니다.

## 빌드

macOS 14 이상과 Xcode가 필요합니다.

```sh
sh scripts/build.sh
open build/CampusBar.app
```

앱의 **e-Campus 로그인** 버튼에서 학교 로그인 화면을 열 수 있습니다. 로그인 후 **강의실 확인**을 누르면 Canvas의 예정 일정과 최근 공지를 읽어 메뉴 막대에 표시합니다. 로그인 정보는 앱 코드나 Git 저장소에 저장하지 않습니다.

학교 사이트의 로그인 상태는 앱 안의 웹 화면에 저장됩니다. Chrome 로그인과 별개이므로 앱에서 처음 한 번 로그인해야 합니다. Canvas 데이터를 읽지 못하면 새로고침하거나 다시 로그인하세요.

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" swift test --disable-sandbox
```
