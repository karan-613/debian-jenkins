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
    string(name: 'DEST_SVC_DIR', defaultValue: 'usr/opt/elevoc/lib',                description: 'service 产物安装目录（相对 PKGROOT）')
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
          mkdir -p "${PKGROOT}/${DEST_SO_DIR}" "${PKGROOT}/${DEST_SVC_DIR}"
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
          # 安装 .so 到包内目录
          if ls pulseaudio_artifacts/*.so >/dev/null 2>&1; then
            cp -v pulseaudio_artifacts/*.so "${PKGROOT}/${DEST_SO_DIR}/"
          else
            echo "⚠️ 未发现 *.so，继续但最终包可能缺少模块"
          fi

          # 安装 service 产物（兼容文件或目录）
          if [ -d service_artifacts ]; then
            # 优先复制一级文件到目标 bin 目录
            find service_artifacts -maxdepth 1 -type f -print -exec cp -v {} "${PKGROOT}/${DEST_SVC_DIR}/" \\; || true
          fi

          echo "== 包内文件预览 =="
          ls -al "${PKGROOT}/${DEST_SO_DIR}" || true
          ls -al "${PKGROOT}/${DEST_SVC_DIR}" || true
        '''
      }
    }

    stage('Derive version from .so (optional)') {
      when { expression { return !params.PKG_VERSION?.trim() } }
      steps {
        script {
          // 从 engine 或 lock 的文件名解析 _UOS_<VER>_ARCH
          def list = sh(script: 'ls pulseaudio_artifacts/*.so 2>/dev/null | sed "s#.*/##"', returnStdout: true).trim()
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

          # 统一权限（可按需调整）
          find "${PKGROOT}" -type d -print0 | xargs -0 chmod 0755
          # 可执行放 0755，其它 0644
          find "${PKGROOT}" -type f -print0 | xargs -0 chmod 0644
          find "${PKGROOT}/${DEST_SVC_DIR}" -type f -print0 | xargs -0 chmod 0755 || true

          OUT="${DIST_DIR}/${PKG}_${VER}_${ARCH}.deb"
          echo "== 构建 Deb =="
          dpkg-deb -b "${PKGROOT}" "${OUT}"
          echo "产物: ${OUT}"
          ls -lh "${OUT}"
        '''
        archiveArtifacts artifacts: 'dist/*.deb', fingerprint: true
      }
    }
  }
}
