pipeline {
  agent any
  options { timestamps(); buildDiscarder(logRotator(numToKeepStr: '20')); skipDefaultCheckout() }

  /***** 可按需修改的参数 *****/
  parameters {
    // 两个子 Job 名
    string(name: 'ENGINE_JOB',  defaultValue: 'uos-pulseaudio', description: 'pulseaudio 构建 Job 名称')
    string(name: 'SERVICE_JOB', defaultValue: 'uos-service',    description: 'service 构建 Job 名称')

    // 选择 “取哪个构建”的策略：lastSuccessful 或 指定构建号
    choice(name: 'ENGINE_SELECTOR',  choices: ['lastSuccessful','lastStable'], description: 'pulseaudio 制品选择器')
    choice(name: 'SERVICE_SELECTOR', choices: ['lastSuccessful','lastStable'], description: 'service 制品选择器')
    // 如果要指定构建号，可以新增参数 ENGINE_BUILD_NO / SERVICE_BUILD_NO 并在下面 selector 里改为 specific()

    // Debian 包相关
    string(name: 'PKG_NAME',     defaultValue: 'uos-audio',             description: '包名')
    string(name: 'PKG_VERSION',  defaultValue: '',                      description: '版本（留空则从 .so 文件名自动解析）')
    choice(name: 'DEB_ARCH',     choices: ['amd64','arm64'],            description: 'Debian 架构')
    string(name: 'PKGROOT',      defaultValue: 'driver',               description: '打包根目录（仓库内已有 DEBIAN/* 的那个目录）')

    // 产物要放入包内的目标路径（若你的 deb 仓库用自定义目录，只改这两项）
    string(name: 'DEST_SO_DIR',  defaultValue: 'usr/lib1', description: 'so 安装到 Deb 包内的目录（相对 PKGROOT）')
    string(name: 'DEST_LIBELEVOC_TINY_ENGINE_SO_DIR', defaultValue: 'opt/elevoc/lib', description: 'libelevoc-tiny-engine.so 安装到Deb包内的目录（相对 PKGROOT）')
    string(name: 'DEST_SVC_DIR', defaultValue: 'opt/elevoc/tmp1',                description: 'service 产物安装目录（相对 PKGROOT）')

        // 可选：自定义 RPATH（不填则按架构给默认值）
    string(name: 'CUSTOM_RPATH_AMD64', defaultValue: '', description: '自定义 amd64 RPATH（留空用默认：\$ORIGIN:/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu/pulseaudio:/lib64:/opt/elevoc/lib）')
    string(name: 'CUSTOM_RPATH_ARM64', defaultValue: '', description: '自定义 arm64 RPATH（留空用默认：\$ORIGIN:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu:/opt/elevoc/lib）')
  }

  environment {
    DIST_DIR = 'dist'     // 输出 .deb 的目录
  }

  stages {
    stage('Checkout packaging repo') {
      steps {
        deleteDir()
        checkout scm
        sh 'pwd && ls -al'
        sh '''
          test -d "${PKGROOT}/DEBIAN" || { echo "❌ 在仓库中找不到 ${PKGROOT}/DEBIAN，请确认 PKGROOT 参数与目录结构。"; exit 2; }
          mkdir -p "${DIST_DIR}"
          # 确保目标安装目录存在
          mkdir -p "${PKGROOT}/${DEST_SO_DIR}" "${PKGROOT}/${DEST_SVC_DIR}" "${PKGROOT}/${DEST_LIBELEVOC_TINY_ENGINE_SO_DIR}"
        '''
      }
    }

    stage('Inject Res & set control arch') {
      steps {
        sh '''
          set -e

          # 1) 选择 Res 子目录：amd64 -> x86；arm64 -> arm64
          case "${DEB_ARCH}" in
            amd64) RES_SUBDIR="x86"   ;;
            arm64) RES_SUBDIR="arm64" ;;
            *)     echo "[warn] 未知 DEB_ARCH=${DEB_ARCH}，默认用 x86"; RES_SUBDIR="x86" ;;
          esac

          SRC_RES="Res/${RES_SUBDIR}"
          DEST_DIR="${PKGROOT}/${DEST_SO_DIR}"   # 通常是 driver/usr/lib1
          mkdir -p "${DEST_DIR}"

          if [ -d "${SRC_RES}" ] && [ -n "$(ls -A "${SRC_RES}" 2>/dev/null)" ]; then
            echo "[info] 拷贝 Res/${RES_SUBDIR}/* -> ${DEST_DIR}"
            cp -v "${SRC_RES}"/* "${DEST_DIR}/"
          else
            echo "[warn] 未发现资源目录或为空：${SRC_RES}"
          fi

          echo "== 目标目录预览 =="
          ls -al "${DEST_DIR}" || true

          # 2) 修改 control 的 Architecture 字段
          CTRL="${PKGROOT}/DEBIAN/control"
          if [ -f "${CTRL}" ]; then
            echo "[info] 设置 Architecture: ${DEB_ARCH} -> ${CTRL}"
            # 用 sed 覆盖 Architecture: 这一行（保持键名大小写）
            sed -i -E "s/^(Architecture:[[:space:]]*).*/\\1${DEB_ARCH}/" "${CTRL}"
            echo "---- control 当前内容 ----"
            cat "${CTRL}"
            echo "-------------------------"
          else
            echo "[warn] 未找到 control 文件：${CTRL}"
          fi
        '''
      }
    }

    stage('Fetch artifacts from children') {
      steps {
        script {
          // selector 选择器
          def selEngine  = params.ENGINE_SELECTOR == 'lastStable' ? lastStable()  : lastSuccessful()
          def selService = params.SERVICE_SELECTOR == 'lastStable' ? lastStable()  : lastSuccessful()

          // 从 pulseaudio Job 复制 *.so
          copyArtifacts projectName: params.ENGINE_JOB,
                        selector: selEngine,
                        filter: 'artifacts/*.so',
                        fingerprintArtifacts: true,
                        target: "${env.WORKSPACE}/pulseaudio_artifacts"

          // 从 service Job 复制全部 artifacts（按你那边归档的真实路径来，这里假设都在 artifacts/ 下）
          copyArtifacts projectName: params.SERVICE_JOB,
                        selector: selService,
                        filter: 'artifacts/**',
                        fingerprintArtifacts: true,
                        target: "${env.WORKSPACE}/service_artifacts"
        }
        sh '''
          echo "== Pulseaudio artifacts ==" && ls -al pulseaudio_artifacts || true
          echo "== Service artifacts =="    && ls -alR service_artifacts  || true
        '''
      }
    }

    stage('Place payloads into package tree') {
      steps {
        sh '''
          set -e

          SRC_PULSE="pulseaudio_artifacts/artifacts"
          SRC_SVC="service_artifacts/artifacts"

          echo "== src pulse (top) ==";    ls -al "${SRC_PULSE}"  || true
          echo "== src service (top) ==";  ls -al "${SRC_SVC}"    || true

          # 目标目录
          mkdir -p "${PKGROOT}/${DEST_SO_DIR}" \
                  "${PKGROOT}/${DEST_LIBELEVOC_TINY_ENGINE_SO_DIR}" \
                  "${PKGROOT}/${DEST_SVC_DIR}"

          # ---- engine/lock -> DEST_SO_DIR ----
          if [ -d "${SRC_PULSE}" ]; then
            find "${SRC_PULSE}" -maxdepth 1 -type f -name "module-elevoc-engine_*.so" \
              -exec cp -v -t "${PKGROOT}/${DEST_SO_DIR}/" {} +
            find "${SRC_PULSE}" -maxdepth 1 -type f -name "module-lock-default-sink_*.so" \
              -exec cp -v -t "${PKGROOT}/${DEST_SO_DIR}/" {} +
            # ---- tiny -> DEST_LIBELEVOC_TINY_ENGINE_SO_DIR（不重命名） ----
            find "${SRC_PULSE}" -maxdepth 1 -type f -name "libelevoc-tiny-engine_*.so" \
              -exec cp -v -t "${PKGROOT}/${DEST_LIBELEVOC_TINY_ENGINE_SO_DIR}/" {} +
          else
            echo "[warn] no pulseaudio artifacts dir: ${SRC_PULSE}"
          fi

          # ---- service 产物 -> DEST_SVC_DIR（后续再重命名） ----
          if [ -d "${SRC_SVC}" ] && [ -n "$(ls -A "${SRC_SVC}" 2>/dev/null)" ]; then
            if [ -n "$(find "${SRC_SVC}" -maxdepth 1 -type f -print -quit 2>/dev/null)" ]; then
              find "${SRC_SVC}" -maxdepth 1 -type f -exec cp -v -t "${PKGROOT}/${DEST_SVC_DIR}/" {} +
            fi
            if [ -n "$(find "${SRC_SVC}" -maxdepth 1 -mindepth 1 -type d -print -quit 2>/dev/null)" ]; then
              find "${SRC_SVC}" -maxdepth 1 -mindepth 1 -type d -exec cp -rv -t "${PKGROOT}/${DEST_SVC_DIR}/" {} +
            fi
          else
            echo "[warn] no service artifacts under ${SRC_SVC}"
          fi

          echo "== preview =="
          ls -al "${PKGROOT}/${DEST_SO_DIR}" || true
          ls -al "${PKGROOT}/${DEST_LIBELEVOC_TINY_ENGINE_SO_DIR}" || true
          ls -al "${PKGROOT}/${DEST_SVC_DIR}" || true
        '''
      }
    }


    stage('Normalize names & manifest (方案A)') {
      steps {
        sh '''
          bash -lc '
            set -euo pipefail

            SO_DIR="${PKGROOT}/${DEST_SO_DIR}"                                  # engine/lock 所在
            TINY_DIR="${PKGROOT}/${DEST_LIBELEVOC_TINY_ENGINE_SO_DIR}"          # tiny 所在
            SVC_DIR="${PKGROOT}/${DEST_SVC_DIR}"                                # service 所在

            # 需要 objcopy
            if ! command -v objcopy >/dev/null 2>&1; then
              (sudo -n apt-get update || true)
              (sudo -n apt-get install -y binutils || true)
            fi

            manifest="${SO_DIR}/manifest.json"
            tmpm="$(mktemp)"
            {
              echo "["
            } > "$tmpm"
            first=1

            write_meta() {
              local so="$1" comp="$2" ver="$3" arch="$4" os="$5"
              local meta; meta="$(mktemp)"
              printf "component=%s\\nversion=%s\\narch=%s\\nos=%s\\n" "$comp" "$ver" "$arch" "$os" > "$meta"
              objcopy --remove-section .elevoc.meta "$so" 2>/dev/null || true
              objcopy --add-section .elevoc.meta="$meta" --set-section-flags .elevoc.meta=noload,readonly "$so"
              rm -f "$meta"
            }

            add_manifest_entry() {
              local f="$1" comp="$2" ver="$3" arch="$4" os="$5"
              local size
              size="$(stat -c %s "$f" 2>/dev/null || stat -f %z "$f" 2>/dev/null || echo 0)"
              if [ $first -eq 0 ]; then echo "," >> "$tmpm"; else first=0; fi
              printf "  {\\n"                                >> "$tmpm"
              printf "    \\"file\\": \\"%s\\",\\n"          "$(basename "$f")" >> "$tmpm"
              printf "    \\"component\\": \\"%s\\",\\n"     "$comp"            >> "$tmpm"
              printf "    \\"version\\": \\"%s\\",\\n"       "$ver"             >> "$tmpm"
              printf "    \\"arch\\": \\"%s\\",\\n"          "$arch"            >> "$tmpm"
              printf "    \\"os\\": \\"%s\\",\\n"            "$os"              >> "$tmpm"
              printf "    \\"size\\": %s\\n"                 "$size"            >> "$tmpm"
              printf "  }"                                   >> "$tmpm"
            }

            # ---- 处理 engine/lock（位于 SO_DIR）：重命名为规范名 ----
            if [ -d "$SO_DIR" ]; then
              for path in "$SO_DIR"/module-elevoc-engine_*.so "$SO_DIR"/module-lock-default-sink_*.so; do
                [ -f "$path" ] || continue
                base="$(basename "$path")"
                case "$base" in
                  module-elevoc-engine_* )
                    comp="engine"
                    os="$(  echo "$base" | sed -E "s/^[^_]*_([A-Za-z0-9]+)_.*/\\1/")"
                    ver="$( echo "$base" | sed -E "s/.*_([0-9.]+)_[A-Za-z0-9_]+\\.so$/\\1/")"
                    arch="$(echo "$base" | sed -E "s/.*_[0-9.]+_([A-Za-z0-9_]+)\\.so$/\\1/")"
                    norm="module-elevoc-engine.so"
                    ;;
                  module-lock-default-sink_* )
                    comp="lock"
                    os="$(  echo "$base" | sed -E "s/^[^_]*_([A-Za-z0-9]+)_.*/\\1/")"
                    ver="$( echo "$base" | sed -E "s/.*_([0-9.]+)_[A-Za-z0-9_]+\\.so$/\\1/")"
                    arch="$(echo "$base" | sed -E "s/.*_[0-9.]+_([A-Za-z0-9_]+)\\.so$/\\1/")"
                    norm="module-lock-default-sink.so"
                    ;;
                esac
                write_meta "$path" "$comp" "$ver" "$arch" "$os"
                cp -f "$path" "$SO_DIR/$norm"
                rm -f "$path"
                add_manifest_entry "$SO_DIR/$norm" "$comp" "$ver" "$arch" "$os"
                echo "[normalized] $base -> $norm {c=$comp v=$ver arch=$arch os=$os}"
                (readelf -p .elevoc.meta "$SO_DIR/$norm" || true)
              done
            fi

            # ---- 处理 tiny（位于 TINY_DIR）：重命名为 libelevoc-tiny-engine.so ----
            if [ -d "$TINY_DIR" ]; then
              for path in "$TINY_DIR"/libelevoc-tiny-engine_*.so; do
                [ -f "$path" ] || continue
                base="$(basename "$path")"
                comp="elevoc-tiny"
                os=""
                ver="$( echo "$base" | sed -E "s/.*_([0-9.]+)_[A-Za-z0-9_]+\\.so$/\\1/")"
                arch="$(echo "$base" | sed -E "s/.*_[0-9.]+_([A-Za-z0-9_]+)\\.so$/\\1/")"

                target="$TINY_DIR/libelevoc-tiny-engine.so"
                cp -f "$path" "$target"          # 复制到新名
                write_meta "$target" "$comp" "$ver" "$arch" "$os"   # 在新文件上写 meta
                rm -f "$path"                    # 删除旧的带版本文件

                add_manifest_entry "$target" "$comp" "$ver" "$arch" "$os"
                echo "[tiny-rename] $base -> $(basename "$target") {c=$comp v=$ver arch=$arch os=$os}"
                (readelf -p .elevoc.meta "$target" || true)
              done
            fi

            # ---- 处理 service（位于 SVC_DIR）：重命名为 detect-AudioDevice，并写 manifest ----
            if [ -d "$SVC_DIR" ]; then
              for path in "$SVC_DIR"/detect-AudioDevice-*; do
                [ -f "$path" ] || continue
                base="$(basename "$path")"
                comp="detect"   # 或改成 "service"
                os=""
                ver="$( echo "$base" | sed -E "s/^detect-AudioDevice-([0-9.]+)-[A-Za-z0-9_]+$/\\1/")"
                arch="$(echo "$base" | sed -E "s/^detect-AudioDevice-[0-9.]+-([A-Za-z0-9_]+)$/\\1/")"

                target="$SVC_DIR/detect-AudioDevice"
                cp -f "$path" "$target"
                rm -f "$path"
                chmod 0755 "$target" || true

                add_manifest_entry "$target" "$comp" "$ver" "$arch" "$os"
                echo "[svc-rename] $base -> $(basename "$target") {c=$comp v=$ver arch=$arch os=$os}"
              done
            fi

            echo "]" >> "$tmpm"
            mv -f "$tmpm" "$manifest"
            echo "== manifest.json =="; cat "$manifest" || true

            echo "== after normalize (SO_DIR) =="
            ls -al "$SO_DIR" || true
            echo "== after normalize (TINY_DIR) =="
            ls -al "$TINY_DIR" || true
            echo "== after normalize (SVC_DIR) =="
            ls -al "$SVC_DIR" || true
          '
        '''
      }
    }

    /* === 新增：用 patchelf 修改 RPATH === */
    stage('Patch RPATH (patchelf)') {
      steps {
        sh '''
          set -e

          # 1) 确保 patchelf 可用
          if ! command -v patchelf >/dev/null 2>&1; then
            echo "[info] installing patchelf ..."
            (sudo -n apt-get update || true)
            (sudo -n apt-get install -y patchelf || sudo apt-get install -y patchelf || apt-get install -y patchelf || true)
          fi
          command -v patchelf >/dev/null 2>&1 || { echo "[warn] patchelf 不可用，跳过 RPATH 修正"; exit 0; }

          # 2) 选定 RPATH（优先使用自定义参数）
          RPATH_AMD64="${CUSTOM_RPATH_AMD64:-'\$ORIGIN:/usr/lib/x86_64-linux-gnu:/usr/lib/x86_64-linux-gnu/pulseaudio:/lib64'}"
          RPATH_ARM64="${CUSTOM_RPATH_ARM64:-'\$ORIGIN:/usr/lib/aarch64-linux-gnu:/lib/aarch64-linux-gnu'}"
          case "${DEB_ARCH}" in
            amd64) RPATH="${RPATH_AMD64}" ;;
            arm64) RPATH="${RPATH_ARM64}" ;;
            *)     RPATH="$ORIGIN/platforms" ;;
          esac
          echo "[info] target RPATH: ${RPATH} (arch=${DEB_ARCH})"

          TARGET_DIR="${PKGROOT}/${DEST_SO_DIR}"
          TARGET_LIBELEVOC_DIR="${PKGROOT}/${DEST_LIBELEVOC_TINY_ENGINE_SO_DIR}"
          ENGINE=""
          TINY=""
          if [ -d "${TARGET_DIR}" ]; then
            ENGINE=$(ls "${TARGET_DIR}"/module-elevoc-engine_*.so "${TARGET_DIR}"/module-elevoc-engine*.so 2>/dev/null | head -n1 || true)
          fi
          if [ -d "${TARGET_LIBELEVOC_DIR}" ]; then
            TINY=$(ls "${TARGET_LIBELEVOC_DIR}"/libelevoc-tiny-engine_*.so "${TARGET_LIBELEVOC_DIR}"/libelevoc-tiny-engine.so 2>/dev/null | head -n1 || true)
          fi

          # 3) 只对两类目标做处理（存在就改）
          ENGINE=$(ls "${TARGET_DIR}"/module-elevoc-engine_*.so "${TARGET_DIR}"/module-elevoc-engine_UOS.so 2>/dev/null | head -n1 || true)
          TINY=$(ls "${TARGET_LIBELEVOC_DIR}"/libelevoc-tiny-engine_*.so "${TARGET_LIBELEVOC_DIR}"/libelevoc-tiny-engine.so 2>/dev/null | head -n1 || true)

          for so in "${ENGINE}" "${TINY}"; do
            [ -f "${so}" ] || continue
            echo "[info] patching $(basename "${so}") ..."
            echo "  old:"
            (readelf -d "${so}" | egrep 'RPATH|RUNPATH' || true)
            patchelf --set-rpath "${RPATH}" "${so}"
            echo "  new:"
            (readelf -d "${so}" | egrep 'RPATH|RUNPATH' || true)
          done

          if [ ! -f "${ENGINE}" ] && [ ! -f "${TINY}" ]; then
            echo "[warn] 未找到需要修改的 .so（module-elevoc-engine_* / libelevoc-tiny-engine_*），跳过"
          fi
        '''
      }
    }

    stage('Derive version from .so (optional)') {
      when { expression { return !params.PKG_VERSION?.trim() } }
      steps {
        script {
          def list = sh(
            script: 'ls pulseaudio_artifacts/artifacts/*.so 2>/dev/null | sed "s#.*/##"',
            returnStdout: true
          ).trim()
          def ver = ''
          if (list) {
            for (n in list.split("\\n")) {
              def m = (n =~ /module-(?:elevoc-engine|lock-default-sink)_[A-Za-z0-9]+_([0-9.]+)_[A-Za-z0-9]+\\.so/)
              if (m.find()) { ver = m.group(1); break }
            }
          }
          if (!ver) ver = '1.0.0'
          env.DEB_VER = ver
          echo "自动解析到版本：${ver}"
        }
      }
    }


    stage('Build .deb (dpkg-deb -b)') {
      steps {
        sh '''
          set -e
          VER="${PKG_VERSION:-${DEB_VER:-1.0.0}}"
          PKG="${PKG_NAME}"
          ARCH="${DEB_ARCH}"

          # 目录 0755、文件默认 0644
          find "${PKGROOT}" -type d -print0 | xargs -0 -r chmod 0755
          find "${PKGROOT}" -type f -print0 | xargs -0 -r chmod 0644

          # 若将来把可执行放 /usr/bin，这里会给 +x；现在你的可执行在 DEST_SVC_DIR，也给 +x
          if [ -d "${PKGROOT}/usr/bin" ]; then
            find "${PKGROOT}/usr/bin" -type f -print0 | xargs -0 -r chmod 0755
          fi
          if [ -d "${PKGROOT}/${DEST_SVC_DIR}" ]; then
            find "${PKGROOT}/${DEST_SVC_DIR}" -maxdepth 1 -type f -print0 | xargs -0 -r chmod 0755
          fi

          # 维护脚本必须可执行
          for s in preinst postinst prerm postrm; do
            [ -f "${PKGROOT}/DEBIAN/$s" ] && chmod 0755 "${PKGROOT}/DEBIAN/$s" || true
          done

          mkdir -p "${DIST_DIR}"
          OUT="${DIST_DIR}/${PKG}_${VER}_${ARCH}.deb"
          echo "== 构建 Deb =="

          dpkg-deb -b "${PKGROOT}" "${OUT}"
          echo "产物: ${OUT}"
          ls -lh "${OUT}"

          echo "== deb contents =="
          dpkg-deb -c "${OUT}" | sed 's/^/  /'
        '''
        archiveArtifacts artifacts: 'dist/*.deb', fingerprint: true
      }
    }

  }

}
