### 安装要求
联想开天X1 UOS专业版1060 && 开启开发者root权限
### 安装说明
1. 安装/卸载后请重启系统
2. 实时语音转文字功能默认自动开启，可在录音时查看/tmp/elevoc_recognizer.txt的输出。
3. 其他功能详见 阵列麦克风智能降噪说明

sudo dpkg-deb -b driver driver.deb
sudo dpkg-deb -b ui ui.deb

### 发版要求
每次发版修改：
1. 重命名包文件，格式：{名称}-{version}-{os}-{cpu}.deb 例如：elevoc_engine-2.1.6-KOS-x86_64.deb; elevoc_engine_ui-2.1.6-arm64.deb; ui包不区分uos和kos
2. control 版本号修改：2.1.6-elevoc-engine-amd64 -> 2.1.6-KOS/UOS-amd64；每次发版修改control文件
