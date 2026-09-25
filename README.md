# CampusBar

macOS 메뉴 막대에서 경희대학교 e-Campus의 할 일을 확인하는 앱입니다.

## 빌드

macOS 14 이상과 Xcode가 필요합니다.

```sh
sh scripts/build.sh
open build/CampusBar.app
```

앱의 **e-Campus 로그인** 버튼에서 학교 로그인 화면을 열 수 있습니다. 로그인 후 **강의실 확인**을 누르면 Canvas의 예정 일정·최근 공지와 LearningX의 영상 학습 기한을 읽어 메뉴 막대에 표시합니다. 로그인 정보는 앱 코드나 Git 저장소에 저장하지 않습니다.

학교 사이트의 로그인 상태는 앱 안의 웹 화면에 저장됩니다. Chrome 로그인과 별개이므로 앱 안에서 로그인해야 합니다. 학교의 로그인 세션이 만료되거나 앱을 재시작한 뒤에는 다시 로그인해야 할 수 있습니다.

로그인 후 학교 홈페이지가 나타나면 앱이 **내 강의실 바로가기**와 같은 경로로 자동 이동합니다. 로그인 창은 인증용이며, 과제·영상·공지는 메뉴 막대의 책 아이콘에서 확인합니다. 앱을 다시 빌드한 경우 기존 앱을 종료하고 새 앱을 열어야 변경된 버전이 실행됩니다.

앱은 30분마다 새로고침합니다. LearningX 마이페이지도 학교에서 약 30분 간격으로 데이터를 갱신하므로, 실제 완료 직후에는 표시가 늦을 수 있습니다.

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache" swift test --disable-sandbox
```
